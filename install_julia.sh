#! /usr/bin/env bash

# Purpose of this script is to install / remove Julia on Linux and FreeBSD systems.

# THE SOFTWARE IS PROVIDED ‘AS IS’, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT.


## options

set -o noclobber
set -o errexit
set -o pipefail
set -o nounset


## consts

DEBUG=false  # set to true to print function trace function calls, for debugging

HELP="Usage: install_julia.sh [command] [argument]\n\n

Run without any parameters to enter interactive mode. Following commands and\n
arguments are supportet for non-interactive usage:\n\n

install [latest|lts|<version>]\t install the latest stable release (default), the current LTS version or a specific version, e.g. \"1.11.0-alpha2\"\n
list\t\t\t\t list all installed versions\n
remove <version>\t\t remove a specific julia version\n
help\t\t\t\t show this help text\n\n

Version:\n
 a specific version can be specified as \"julia-x.y.z[-abc]\" or "x.y.z[-abc]"\n\n

Examples:\n
 install_julia.sh install 1.11.0-alpha2\t\t # install julia-1.11.0-alpha2\n
 install_julia.sh remove 1.10.0\t # remove julia-1.10.0
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
    if ! which jq > /dev/null; then
        print_msg "Missing dependency \"jq\""
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
            remove | uninstall)
            if [[ $# -eq 2 ]]; then
                get_installed_versions
                remove_version $2
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
        bin_dir="/usr/bin/"
    elif [[ $(uname) = "FreeBSD" ]]; then
        install_dir="/usr/local/"
        bin_dir="/usr/bin/"
    else
        print_msg "Unsupportet operating system: \"$(uname)\", only Linux and FreeBSD are supportet by this installation script."
    fi
}

# fetch available versions from Julia versions API
get_available_versions() {
    [ $DEBUG == true ] && echo "DEBUG: available versions"
    source=$(curl -s https://julialang-s3.julialang.org/bin/versions.json)
    latest=$(echo "${source}" | jq -r '[to_entries[] | select(.value.stable == true and (.key | test("-") | not)) | .key] | sort_by(split(".") | map(tonumber)) | last')
    lts=$(curl -s https://raw.githubusercontent.com/JuliaLang/juliaup/main/versiondb/versiondb-x86_64-unknown-linux-gnu.json | jq -r '.AvailableChannels.lts.Version | split("+")[0]')
    prerelease=$(echo "${source}" | jq -r --arg latest "$latest" '
            def version_key:
                capture("^(?<major>[0-9]+)\\.(?<minor>[0-9]+)\\.(?<patch>[0-9]+)(?:-(?<stage>alpha|beta|rc)(?<stage_num>[0-9]+))?$")
                | [(.major | tonumber), (.minor | tonumber), (.patch | tonumber),
                     (if .stage == "alpha" then 0 elif .stage == "beta" then 1 elif .stage == "rc" then 2 else 3 end),
                     ((.stage_num // "0") | tonumber)];
            def base_version_key:
                split("-")[0]
                | capture("^(?<major>[0-9]+)\\.(?<minor>[0-9]+)\\.(?<patch>[0-9]+)$")
                | [(.major | tonumber), (.minor | tonumber), (.patch | tonumber)];
            [to_entries[]
             | select(.value.stable == false and (.key | test("-(alpha|beta|rc)[0-9]+$")))
             | select((.key | base_version_key) > ($latest | base_version_key))
             | .key]
            | sort_by(version_key)
            | last // empty')
    #[ $DEBUG == true ] && echo "DEBUG: latest: ${latest}\nDEBUG: lts: ${lts}" I have no idea why this line makes everything fail
}

# check for installed julia versions
get_installed_versions() {
    [ $DEBUG == true ] && echo "DEBUG: installed versions"
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

# extract a version string from an installed Julia directory or download target name
get_version_string() {
    local version

    version="$1"
    version="${version#julia-}"
    version=$(echo "${version}" | sed -E 's/-(linux|freebsd|musl)-.+$//')

    echo "${version}"
}

# return a sortable key for Julia versions including prerelease stages
get_version_sort_key() {
    local version
    local stage_rank=3
    local stage_number=0

    version=$(get_version_string "$1")

    if [[ ${version} =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-(alpha|beta|rc)([0-9]+))?$ ]]; then
        case ${BASH_REMATCH[5]:-stable} in
            alpha)
            stage_rank=0
            ;;
            beta)
            stage_rank=1
            ;;
            rc)
            stage_rank=2
            ;;
            *)
            stage_rank=3
            ;;
        esac

        stage_number=${BASH_REMATCH[6]:-0}
        printf "%05d.%05d.%05d.%05d.%05d\n" \
            "${BASH_REMATCH[1]}" \
            "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[3]}" \
            "${stage_rank}" \
            "${stage_number}"
    fi
}

# test whether the first version is older than the second one
version_is_older() {
    local current_key
    local target_key

    current_key=$(get_version_sort_key "$1")
    target_key=$(get_version_sort_key "$2")

    [[ -n ${current_key} && -n ${target_key} && ${current_key} < ${target_key} ]]
}

# return the major.minor part of a Julia version string
get_major_minor_version() {
    local version

    version=$(get_version_string "$1")

    if [[ ${version} =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-.+)?$ ]]; then
        echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    fi
}

# return the branch name for an installed Julia version
get_installed_version_branch() {
    local version
    local version_major_minor
    local lts_major_minor

    version=$(get_version_string "$1")

    if [[ ${version} =~ -(alpha|beta|rc)[0-9]+$ ]]; then
        echo "prerelease"
        return 0
    fi

    version_major_minor=$(get_major_minor_version "${version}")
    lts_major_minor=$(get_major_minor_version "${lts}")

    if [[ -n ${lts_major_minor} && ${version_major_minor} == ${lts_major_minor} ]]; then
        echo "lts"
    else
        echo "stable"
    fi
}

# return the current target version for a Julia branch
get_branch_target_version() {
    case $1 in
        stable)
        echo "${latest}"
        ;;
        lts)
        echo "${lts}"
        ;;
        prerelease)
        echo "${prerelease:-}"
        ;;
    esac
}

# return the display label for a Julia branch
get_branch_label() {
    case $1 in
        stable)
        echo "Stable"
        ;;
        lts)
        echo "LTS"
        ;;
        prerelease)
        if [[ -n ${prerelease:-} ]]; then
            get_version_branch_label "$(get_full_version_string "${prerelease}")"
        else
            echo "Prerelease"
        fi
        ;;
    esac
}

# return the currently configured default Julia installation name, if available
get_default_installed_version() {
    local default_path

    if [[ -e ${bin_dir}julia ]]; then
        default_path=$(readlink -f "${bin_dir}julia" 2> /dev/null || true)
        if [[ ${default_path} =~ /(julia-[0-9]+\.[0-9]+\.[0-9]+(-.+)?)/bin/julia$ ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    fi
}

# point the default julia executable to a specific installed version
set_default_version() {
    rm -f "${bin_dir}julia"
    ln -s "${install_dir}${1}/bin/julia" "${bin_dir}julia"
}

# test whether a branch has at least one installed version with an available update
branch_has_updates() {
    local branch
    local target_version
    local version

    if [[ -z ${installed_versions:-} ]]; then
        return 1
    fi

    branch="$1"
    target_version=$(get_branch_target_version "${branch}")

    if [[ -z ${target_version} ]]; then
        return 1
    fi

    for version in "${installed_versions[@]}"; do
        if [[ -n ${version} && $(get_installed_version_branch "${version}") == ${branch} ]] && version_is_older "${version}" "${target_version}"; then
            return 0
        fi
    done

    return 1
}

# populate the list of installed branches with available updates
get_update_branches() {
    update_branches=()

    for branch in stable lts prerelease; do
        if branch_has_updates "${branch}"; then
            update_branches+=("${branch}")
        fi
    done
}

# return the branch label for a listed Julia install option
get_version_branch_label() {
    local version

    version=$(echo "$1" | sed -E 's/^julia-([0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)[0-9]+)?)-(linux|freebsd|musl)-.+$/\1/')

    if [[ ${version} == ${latest} ]]; then
        echo "Stable"
    elif [[ ${version} == ${lts} ]]; then
        echo "LTS"
    elif [[ -n ${prerelease:-} && ${version} == ${prerelease} ]]; then
        case ${version} in
            *-alpha*)
            echo "Alpha"
            ;;
            *-beta*)
            echo "Beta"
            ;;
            *-rc*)
            echo "Release Candidate"
            ;;
        esac
    fi
}

# display currently loaded install options with their branch labels
show_install_options() {
    local branch

    for i in $(seq ${#install_options[@]}); do
        branch=$(get_version_branch_label "${install_options[$((${i}-1))]}")
        if [[ -n ${branch} ]]; then
            echo "[${i}] ${install_options[$((${i}-1))]} (${branch})"
        else
            echo "[${i}] ${install_options[$((${i}-1))]}"
        fi
    done
}


# return all available installtion options from Julia versions API
show_all_install_options() {
    readarray -t install_options < <(echo "${source}" | jq -r --arg latest "$latest" --arg lts "$lts" --arg prerelease "$prerelease" '
            . as $versions |
            [$latest, $lts, $prerelease] |
            map(select(length > 0)) |
            map($versions[.].files[]) |
            reduce .[] as $file ([]; if any(.[]; .url == $file.url) then . else . + [$file] end) |
            .[] |
            select(.extension == "tar.gz" and (.os == "linux" or .os == "freebsd")) |
            .url | split("/") | last | rtrimstr(".tar.gz")')

    show_install_options
}

# return the suggested installation options for this machine
show_suggested_install_options() {
    if [[ -z ${arch} ]]; then
        readarray -t install_options < <(echo "${source}" | jq -r --arg latest "$latest" --arg lts "$lts" '
            . as $versions |
            [$latest, $lts] |
            map(select(length > 0)) |
            map($versions[.].files[]) |
            reduce .[] as $file ([]; if any(.[]; .url == $file.url) then . else . + [$file] end) |
            .[] |
            select(.extension == "tar.gz" and (.os == "linux" or .os == "freebsd")) |
            .url | split("/") | last | rtrimstr(".tar.gz")')

        show_install_options
    else
        if [[ $(uname) == "Linux" ]]; then
            readarray -t install_options < <(echo "${source}" | jq -r --arg latest "$latest" --arg lts "$lts" --arg arch "$arch" '
                            . as $versions |
                            [$latest, $lts] |
                            map(select(length > 0)) |
                            map($versions[.].files[]) |
                            reduce .[] as $file ([]; if any(.[]; .url == $file.url) then . else . + [$file] end) |
                            .[] |
                            select(.extension == "tar.gz" and .os == "linux" and .arch == $arch) |
                            .url | split("/") | last | rtrimstr(".tar.gz")')
        else
            readarray -t install_options < <(echo "${source}" | jq -r --arg latest "$latest" --arg lts "$lts" --arg arch "$arch" '
                            . as $versions |
                            [$latest, $lts] |
                            map(select(length > 0)) |
                            map($versions[.].files[]) |
                            reduce .[] as $file ([]; if any(.[]; .url == $file.url) then . else . + [$file] end) |
                            .[] |
                            select(.extension == "tar.gz" and .os == "freebsd" and .arch == $arch) |
                            .url | split("/") | last | rtrimstr(".tar.gz")')
        fi
        show_install_options
    fi
}

# install a specific version of julia without exiting the script
install_version() {
    local name
    local version
    local download_url
    local input
    local set_default_mode="${2:-prompt}"
    local clear_screen="${3:-true}"

    name=$(echo "$1" | sed -r s/-\(linux\|musl\|freebsd\)-${arch}//g)
    version="${name#julia-}"
    download_url=$(echo "${source}" | jq -r --arg v "$version" --arg fname "${1}.tar.gz" '.[$v].files[] | select(.url | endswith("/" + $fname)) | .url')

    if [[ ${clear_screen} == true ]]; then
        clear
    fi

    if [[ -d ${install_dir}${name} ]]; then
        print_msg "${name} is already installed on this system" warn
        return 0
    fi

    echo -e "download $1 ...\n"
    curl -o ${install_dir}$1.tag.gz ${download_url}

    if [[ ${clear_screen} == true ]]; then
        clear
    fi

    echo "download $1 ... done"

    echo -n "extract archive ..."
    tar -C ${install_dir} -xf ${install_dir}$1.tag.gz
    echo " done"

    echo -n "remove archive ..."
    rm ${install_dir}$1.tag.gz
    echo " done"

    echo -n "create version specific link ..."
    ln -s ${install_dir}${name}/bin/julia ${bin_dir}${name}
    echo " done"

    echo -e "\nInstallation completed successfully!"
    echo -e "Installation directory: ${install_dir}${name}\n"

    case ${set_default_mode} in
        prompt)
        while true; do
            read -p "Set ${name} as default julia version on this system [Y/n]: " input
            case ${input} in
                "" | y | Y | yes | Yes | YES)
                set_default_version "${name}"
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
        ;;
        yes)
        set_default_version "${name}"
        ;;
    esac
}

# install a specific version of julia
install() {
    check_permissions
    install_version "$1"
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


# remove a specific julia version without exiting the script
remove_installed_version() {
    local version

    # prepend 'julia-' to version string if required
    if [[ ${1:0:6} != "julia-" ]]; then
        version="julia-${1}"
    else
        version=${1}
    fi

    if [[ -d ${install_dir}${version} ]]; then
        # check for default installation
        if readlink -f ${bin_dir}julia 2> /dev/null | grep -q ${version}; then
            rm -f ${bin_dir}julia
        fi
        rm -f ${bin_dir}${version}
        rm -r ${install_dir}${version}
        if [[ ${?} ]]; then
            print_msg "${version} deleted successfully" info
            return 0
        else
            return 1
        fi
    else
        print_msg "Installation directory: '${install_dir}${1}' not found." error
        return 1
    fi
}


# remove a specific julia version
remove_version() {
    check_permissions
    local version

    if [[ ${1:0:6} != "julia-" ]]; then
        version="julia-${1}"
    else
        version=${1}
    fi

    # validate version string with installed versions
    if ! printf '%s\n' "${installed_versions[@]}" | grep -qx "${version}"; then
        print_msg "Invalid Julia version: ${version}" error
        exit 1
    fi

    remove_installed_version "${version}"
    exit 0
}


# install the latest version for each installed branch with available updates
apply_updates() {
    local default_version
    local default_branch
    local branch
    local target_version
    local target_full_name
    local version

    get_update_branches

    if [[ ${#update_branches[@]} -eq 0 ]]; then
        print_msg "No updates available." info
        return 0
    fi

    default_version=$(get_default_installed_version)
    if [[ -n ${default_version} ]]; then
        default_branch=$(get_installed_version_branch "${default_version}")
    else
        default_branch=""
    fi

    clear
    echo -e "Update Julia\n"

    for branch in "${update_branches[@]}"; do
        target_version=$(get_branch_target_version "${branch}")
        target_full_name=$(get_full_version_string "${target_version}")

        echo "$(get_branch_label "${branch}"): julia-${target_version}"

        if [[ -d ${install_dir}julia-${target_version} ]]; then
            print_msg "julia-${target_version} is already installed, skipping download" info
        else
            install_version "${target_full_name}" "no" "false"
        fi
    done

    for branch in "${update_branches[@]}"; do
        target_version=$(get_branch_target_version "${branch}")
        for version in "${installed_versions[@]}"; do
            if [[ -n ${version} && $(get_installed_version_branch "${version}") == ${branch} && ${version} != julia-${target_version} ]]; then
                remove_installed_version "${version}"
            fi
        done
    done

    if [[ -n ${default_branch} ]]; then
        target_version=$(get_branch_target_version "${default_branch}")
        if [[ -n ${target_version} && -d ${install_dir}julia-${target_version} ]]; then
            set_default_version "julia-${target_version}"
        fi
    fi

    echo -e "\nUpdate completed successfully!"
}


# update installed Julia branches
update_installed_versions() {
    check_permissions
    apply_updates
    exit 0
}


# remove menu, if argument noclear is set, the console will not be cleared
remove_menu() {
    local input
    local command
    clear
    echo -e "Remove Julia"
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
            command="remove_version ${installed_versions[0]}"
            break
            ;;
            *)
            if [[ ${input} =~ [0-9]+ && ${input} -ge 1 && ${input} -le ${#installed_versions[*]} ]]; then
                command="remove_version ${installed_versions[$((${input} - 1))]}"
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
    echo "main menu"
    local input
    local command
    local update_available=false
    local default_selection="i"

    if [[ $# -eq 0 || ${1} != "noclear" ]]; then
        clear
    fi

    get_update_branches
    if [[ ${#update_branches[@]} -gt 0 ]]; then
        update_available=true
        default_selection="u"
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
    if [[ ${update_available} == true ]]; then
        echo -e "[u] Update"
    else
        echo -e "\033[90m[u] Update\033[0m"
    fi
    if [[ -n ${installed_versions} ]]; then
        echo -e "[r] Remove"
    fi
    echo -e "[q] Quit\n"

    while true; do
        read -p "Select an option [${default_selection}]: " input
        case ${input} in
            q)
            exit 0
            ;;
            i)
            command=install_menu
            break
            ;;
            u)
            if [[ ${update_available} == true ]]; then
                command=update_installed_versions
            else
                print_msg "invalid input" warn
            fi
            break
            ;;
            r)
            if [[ -n ${installed_versions} ]]; then
                command=remove_menu
            else
                print_msg "invalid input" warn
            fi
            break
            ;;
            "")
            if [[ ${update_available} == true ]]; then
                command=update_installed_versions
            else
                command=install_menu
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
