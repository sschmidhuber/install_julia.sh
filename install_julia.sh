#! /usr/bin/env bash

# Purpose of this script is to install / uninstall Julia on Linux systems.

# THE SOFTWARE IS PROVIDED ‘AS IS’, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT.


## options

set -o noclobber
set -o errexit
set -o pipefail
set -o nounset


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

# check if all dependencies and permissions are fulfilled
check_prerequisites() {
    if [[ $(whoami) != "root" ]]; then
        print_msg "This script needs to be executed with root permissions. Try \"sudo ./install_julia.sh\""
        exit 1
    fi
    if ! which curl > /dev/null; then
        print_msg "Missing dependency \"curl\""
        exit 2
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
    if [[ $(ls /opt/ | grep -E ^julia-[0-9]+\.[0-9]+\.[0-9]$ | wc -l) -eq 0  ]]; then
        installed_versions=""
    else
        readarray -t installed_versions < <(ls /opt/ | grep -E ^julia-[0-9]+\.[0-9]+\.[0-9]$)
    fi
}


# display all installed versions, if argument "num" is provided, the entries are prefixed with numbers
# to be selected by a user
show_installed_versions() {
    echo ""
    for i in $(seq ${#installed_versions[*]}); do
        if [[ $# -eq 1 && ${1} == "num" ]]; then
            echo -en "[${i}] "
        fi
        echo -en "${installed_versions[$((${i}-1))]}\n"
    done
    echo ""
}

# set arch variable for this system
set_architecture() {
    case $(lscpu | grep Architecture | tr -s " " | cut -d " " -f 2) in
        x86_64)
        arch="x86_64"
        ;;
        i686)
        arch="i686"
        ;;
        aarch64)
        arch="aarch64"
        ;;
        *)
        arch=""
        ;;
    esac
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
    local download_url=$(echo "${source}" | grep -Eo https://.+${1}.tar.gz | head -n 1)
    local name=$(echo ${1} | grep -Eo julia-[0-9]+\.[0-9]+\.[0-9])
    local input

    clear
    if [[ -d /opt/${name} ]]; then
        print_msg "${name} is already installed on this system" warn
        exit 0
    fi

    echo -e "download ${1} ...\n"
    curl -o /opt/${1}.tag.gz ${download_url}
    clear
    echo "download ${1} ... done"
    
    echo -n "extract archive ..."
    tar -C /opt/ -xf /opt/${1}.tag.gz
    echo " done"
    
    echo -n "remove archive ..."
    rm /opt/${1}.tag.gz
    echo " done"
    
    echo -n "create version specific link ..."
    name=$(echo ${1} | grep -Eo julia-[0-9]+\.[0-9]+\.[0-9])
    ln -s /opt/${name}/bin/julia /usr/bin/${name}
    echo " done"

    echo -e "\nInstallation completed successfully!"
    echo -e "Installation directory: /opt/${name}\n"
    while true; do
        read -p "Set ${name} as default julia version on this system [Y/n]: " input
        case ${input} in
            "" | y | Y | yes | Yes | YES)
            if [[ -h /usr/bin/julia ]]; then
                rm /usr/bin/julia                
            fi
            ln -s /opt/${name}/bin/julia /usr/bin/julia
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
            command=main
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
    if [[ -d /opt/${1} ]]; then
        # check for default installation
        if [[ $(readlink -f /usr/bin/julia | grep -o ${1}) == ${1} ]]; then
            rm /usr/bin/julia
        fi
        rm /usr/bin/${1}
        rm -r /opt/${1}
        if [[ ${?} ]]; then
            print_msg "${1} deleted successfully" info
            exit 0
        else
            exit 1
        fi
    else
        print_msg "Installation directory: '/opt/${1}' not found." error
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
            command=main
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
main() {
    local input
    local command

    if [[ $# -eq 0 || ${1} != "noclear" ]]; then
        clear
    fi
    
    if [[ -z ${installed_versions} ]]; then
        print_msg "no Julia installation found in directory /opt/" info
    else
        if [[ ${#installed_versions[*]} -eq 1 ]]; then
            echo -e "Julia installation found:"
        else
            echo -e "Multiple Julia installations found:"
        fi
        show_installed_versions
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

check_prerequisites
set_architecture
get_installed_versions
get_available_versions

main