#! /usr/bin/env bash

# Purpose of this script is to install / uninstall Julia on Linux and FreeBSD systems.

# THE SOFTWARE IS PROVIDED ‘AS IS’, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT.


## options

set -o noclobber
set -o errexit
set -o pipefail
set -o nounset


## consts

HELP="Usage: install_julia.sh [command] [argument]\n\n

Run without any parameters to enter interactive mode. Following commands and\n
arguments are supportet for non-interactive usage:\n\n

install [latest|lts|<version>]\t install the latest stable release (default), the current LTS version or a specific version, e.g. \"1.11.0-alpha2\"\n
list\t\t\t\t list all installed versions\n
uninstall <version>\t\t uninstall a specific julia version\n
help\t\t\t\t show this help text\n\n

Version:\n
 a specific version can be specified as \"julia-x.y.z[-abc]\" or "x.y.z[-abc]"\n\n

Examples:\n
 install_julia.sh install 1.11.0-alpha2\t\t # install julia-1.11.0-alpha2\n
 install_julia.sh uninstall 1.10.0\t # uninstall julia-1.10.0
"


## functions

# print a error (default), warn or info message
# first argument is the message, second argument the message type
print_msg() {
    if [[ $# -eq 2 ]]; then
        if [[ ${2} == "warn" ]]; then
            echo -e "\n\033[33m WARNING: \033[0;39m${1}\n"
        elif [[ ${2} == "info" ]]; then
            echo -e "\n INFO: ${1}\n"
        elif [[ ${2} == "error" ]]; then
            echo -e "\n\033[31m ERROR: \033[0;39m${1}\n"
        else
            print_msg "invalid message type: ${2}"
        fi
    else
        echo -e "\n\033[31m ERROR: \033[0;39m${1}\n"
    fi    
}

check_permissions() {
    if [[ $(whoami) != "root" ]]; then
        print_msg "Root privileges required for this operation. Try to prepend \"sudo\"."
        exit 1
    fi
}

# check if all dependencies and permissions are fulfilled
check_dependencies() {
    if ! which curl > /dev/null; then
        print_msg "Missing dependency \"curl\""
        exit 2
    fi
    if ! which tar > /dev/null; then
        print_msg "Missing dependency \"tar\""
        exit 2
    fi
    if ! which lscpu > /dev/null; then
        print_msg "Missing dependency \"lscpu\""
        exit 2
    fi
    if ! which sed > /dev/null; then
        print_msg "Missing dependency \"sed\""
        exit 2
    fi
}

# parse arguments
check_agrs() {
    if [[ $# -eq 0 ]]; then
        # interactive mode
        get_installed_versions
        get_available_versions        
        main_menu
    else
        # non-interactive mode
        if [[ $# -gt 2 ]]; then
            print_msg "Invalid number of arguments."
            exit 1
        fi
        case $1 in
            -h | --help | h | help)
            echo -e ${HELP}
            exit 0
            ;;
            install | i)
            get_available_versions
            if [[ $# -eq 1 ]]; then
                install $latest
                exit 0
            elif [[ $2 == "latest" ]]; then
                install $latest
                exit 0
            elif [[ $2 == "lts" ]]; then
                install $lts
                exit 0
            elif [[ $# -eq 2 ]]; then
                install $(get_full_version_string $2)
                exit 0
            else
                print_msg "Invalid number of arguments."
                exit 1
            fi
            ;;
            list)
            get_installed_versions
            show_installed_versions
            exit 0
            ;;
            uninstall)
            if [[ $# -eq 2 ]]; then
                get_installed_versions
                uninstall $2
                exit 0
            else
                print_msg "No version specified."
                exit 1
            fi
            ;;
            *)
            print_msg "Invalid command, try \"help\" to show help."
            exit 1
        esac
    fi
}

# set installation directory
set_install_directory() {
    if [[ $(uname) = "Linux" ]]; then
        install_dir="/opt/"
    elif [[ $(uname) = "FreeBSD" ]]; then
        install_dir="/usr/local/"
    else
        print_msg "Unsupportet operating system: \"$(uname)\", only Linux and FreeBSD are supportet by this installation script."
    fi
}

# scrap available versions from Julia website
get_available_versions() {
    source=$(curl -s https://julialang.org/downloads/#current_stable_release)
    latest=$(echo "${source}" | grep "id=current_stable_release" | grep -Eo v[0-9]+\.[0-9]+\.[0-9]+ )
    latest=${latest:1}
    lts=$(echo "${source}" | grep "id=long_term_support_release" | grep -Eo v[0-9]+\.[0-9]+\.[0-9]+ )
    lts=${lts:1}
}

# check for installed julia versions
get_installed_versions() {
    if [[ $(ls ${install_dir} | grep -E "^julia-[0-9]+\.[0-9]+\.[0-9](-.+)?$" | wc -l) -eq 0  ]]; then
        installed_versions=""
    else
        readarray -t installed_versions < <(ls ${install_dir} | grep -E "^julia-[0-9]+\.[0-9]+\.[0-9](-.+)?$")
    fi
}


# display all installed versions, if argument "num" is provided, the entries are prefixed with numbers to be selected by a user
show_installed_versions() {
    if [[ $# -eq 0 ]]; then
        for i in $(seq ${#installed_versions[*]}); do
            echo -en "${installed_versions[$((${i}-1))]}\n"
        done
    elif [[ $# -eq 1 && $1 == "num" ]]; then
        echo ""
        for i in $(seq ${#installed_versions[*]}); do
            echo -en "[${i}] "
            echo -en "${installed_versions[$((${i}-1))]}\n"
        done
        echo ""
    fi
}

# set arch variable for this system
set_architecture() {
    case $(lscpu | grep Architecture | tr -s " " | cut -d " " -f 2) in
        x86_64 | amd64)
        arch="x86_64"
        ;;
        i686)
        arch="i686"
        ;;
        aarch64)
        arch="aarch64"
        ;;
        ppc64le)
        arch="ppc64le"
        ;;
        *)
        arch=""
        ;;
    esac
}


# return a julia version string including architecture and os parts as used in download URLs
# on linux this always assumes glibc and doesn't work for musl
# e.g. "julia-1.11.0-linux-aarch64" for a given input "1.11.0"
get_full_version_string() {
    local full_name

    if [[ ${1:0:5} != "julia" ]]; then
        full_name=$(echo "julia-$1")
    else
        full_name=$1
    fi

    if [[ $(uname) == "Linux" ]]; then
        echo "${full_name}-linux-${arch}"
    else
        echo "${full_name}-freebsd-${arch}"
    fi
}


# return all available installtion options from Julia website
show_all_install_options() {
    readarray -t install_options < <(echo "${source}" | grep -Eo julia-\(${latest}\|${lts}\)-\(linux\|musl\|freebsd\).+\.tar.gz\" | sed s/.tar.gz\"//g)

    for i in $(seq ${#install_options[@]}); do
        echo "[${i}] ${install_options[$((${i}-1))]}"
    done
}

# return the suggested installation options for this machine
show_suggested_install_options() {
    if [[ -z ${arch} ]]; then
        show_all_install_options
    else
        if [[ $(uname) == "Linux" ]]; then
            readarray -t install_options < <(echo "${source}" | grep -Eo julia-\(${latest}\|${lts}\)-\(linux\|musl\)-${arch}\.tar.gz\" | sed s/.tar.gz\"//g)
        else
            readarray -t install_options < <(echo "${source}" | grep -Eo julia-\(${latest}\|${lts}\)-freebsd-${arch}\.tar.gz\" | sed s/.tar.gz\"//g)
        fi        
        for i in $(seq ${#install_options[@]}); do
            echo "[${i}] ${install_options[$((${i}-1))]}"
        done
    fi
}

# install a specific version of julia
install() {
    check_permissions

    local download_url=$(echo "${source}" | grep -Eo https://.+${1}.tar.gz | head -n 1)
    local name=$(echo ${1} | sed -r s/-\(linux\|musl\|freebsd\)-${arch}//g)
    local input

    clear
    if [[ -d ${install_dir}${name} ]]; then
        print_msg "${name} is already installed on this system" warn
        exit 0
    fi

    echo -e "download ${1} ...\n"
    curl -o ${install_dir}${1}.tag.gz ${download_url}
    clear
    echo "download ${1} ... done"
    
    echo -n "extract archive ..."
    tar -C ${install_dir} -xf ${install_dir}${1}.tag.gz
    echo " done"
    
    echo -n "remove archive ..."
    rm ${install_dir}${1}.tag.gz
    echo " done"
    
    echo -n "create version specific link ..."
    ln -s ${install_dir}${name}/bin/julia /usr/bin/${name}
    echo " done"

    echo -e "\nInstallation completed successfully!"
    echo -e "Installation directory: ${install_dir}${name}\n"
    while true; do
        read -p "Set ${name} as default julia version on this system [Y/n]: " input
        case ${input} in
            "" | y | Y | yes | Yes | YES)
            if [[ -h /usr/bin/julia ]]; then
                rm /usr/bin/julia                
            fi
            ln -s ${install_dir}${name}/bin/julia /usr/bin/julia
            break
            ;;
            n | N | no | No | NO)
            break
            ;;
            *)
            print_msg "invalid input, enter \"y\" (yes) or \"n\" (no)" warn
            ;;
        esac
    done

    exit 0
}

# install menu, if argument "all" is provided, all install options from Julia website will be listed
install_menu() {
    local input
    local command
    clear
    echo -e "Install Julia\n"
    if [[ $# -eq 1 && ${1} == "all" ]]; then
        show_all_install_options
    else
        show_suggested_install_options
    fi
    if [[ $# -eq 0 && -n ${arch} ]]; then
        echo -en "\n[a] Show all install options"
    elif [[ $# -eq 1 && ${1} == "all" && -n ${arch} ]]; then
        echo -en "\n[s] Suggested install options"
    fi
    echo -e "\n[b] Back to main menu\n[q] Quit\n"
    while true; do
        read -p "Select an option [1]: " input
        case ${input} in
            a)
            command="install_menu all"
            break
            ;;
            s)
            command=install_menu
            break
            ;;
            q)
            exit 0
            ;;
            b)
            command=main_menu
            break
            ;;
            "")
            command="install ${install_options[0]}"
            break
            ;;
            *)
            if [[ ${input} =~ [0-9]+ && ${input} -ge 1 && ${input} -le ${#install_options[*]} ]]; then
                command="install ${install_options[$((${input} - 1))]}"
                echo $command
            else
                print_msg "invalid input" warn
            fi
            break
            ;;
        esac
    done
    $command
}


# unsinstall a specific julia version
uninstall() {
    check_permissions
    local version

    # prepend 'julia-' to version string if required
    if [[ ${1:0:6} != "julia-" ]]; then
        version="julia-${1}"
    else
        version=${1}
    fi

    # validate version string with installed versions
    if [[ ! $(echo ${installed_versions[*]} | grep -o ${version}) ]]; then
        print_msg "Invalid Julia version: ${version}" error
        exit 1
    fi

    if [[ -d ${install_dir}${version} ]]; then
        # check for default installation
        if [[ $(readlink -f /usr/bin/julia | grep -o ${version}) ]]; then
            rm /usr/bin/julia
        fi
        rm /usr/bin/${version}
        rm -r ${install_dir}${version}
        if [[ ${?} ]]; then
            print_msg "${version} deleted successfully" info
            exit 0
        else
            exit 1
        fi
    else
        print_msg "Installation directory: '${install_dir}${1}' not found." error
        exit 1
    fi
}


# uninstall menu, if argument noclear is set, the console will not be cleared
uninstall_menu() {
    local input
    local command
    clear
    echo -e "Uninstall Julia"
    show_installed_versions "num"
    echo -e "[b] Back to main menu\n[q] Quit\n"
    while true; do
        read -p "Select an option [1]: " input
        case ${input} in            
            q)
            exit 0
            ;;
            b)
            command=main_menu
            break
            ;;
            "")
            command="uninstall ${installed_versions[0]}"
            break
            ;;
            *)
            if [[ ${input} =~ [0-9]+ && ${input} -ge 1 && ${input} -le ${#installed_versions[*]} ]]; then
                command="uninstall ${installed_versions[$((${input} - 1))]}"
            else
                print_msg "invalid input" warn
            fi
            break
            ;;
        esac
    done
    ${command}
}


# main menu
main_menu() {
    local input
    local command

    if [[ $# -eq 0 || ${1} != "noclear" ]]; then
        clear
    fi
    
    if [[ -z ${installed_versions} ]]; then
        print_msg "no Julia installation found in directory ${install_dir}" info
    else
        if [[ ${#installed_versions[*]} -eq 1 ]]; then
            echo -e "Julia installation found:"
        else
            echo -e "Multiple Julia installations found:"
        fi
        echo ""
        show_installed_versions
        echo ""
    fi
    
    echo -e "[i] Install"
    if [[ -n ${installed_versions} ]]; then
        echo -e "[u] Uninstall"
    fi
    echo -e "[q] Quit\n"

    while true; do
        read -p "Select an option [i]: " input
        case ${input} in
            q)
            exit 0
            ;;
            i | "")
            command=install_menu
            break
            ;;
            u)
            if [[ -n ${installed_versions} ]]; then
                command=uninstall_menu
            else
                print_msg "invalid input" warn
            fi
            break
            ;;
            *)
            print_msg "invalid input" warn
            ;;
        esac
    done
    ${command}
}


## entry point

check_dependencies
set_architecture
set_install_directory
check_agrs $@

exit 0
