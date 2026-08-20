#!/usr/bin/env bash
set -euo pipefail

# ANSI ESCAPE CODE COLOURS
greenColour='\033[0;32m'
redColour='\033[0;31m'
blueColour='\033[0;34m'
yellowColour='\033[1;33m'
purpleColour='\033[0;35m'
cyanColour='\033[0;36m'
grayColour='\033[0;37m'
endColour='\033[0m'

### DISPLAY INFORMATION FUNCTIONS ###
msg_info() { echo -e "${cyanColour}[INFO]${endColour} $1" >&2; }
msg_success() { echo -e "${greenColour}[OK]${endColour} $1" >&2; }
msg_warn() { echo -e "${yellowColour}[WARN]${endColour} $1" >&2; }
msg_error() { echo -e "${redColour}[ERROR]${endColour} $1" >&2; }
print_separator() { echo -e "${grayColour}--------------------------------------------------${endColour}"; }


detect_package_manager() {
    if command -v apt &>/dev/null; then
        echo "apt"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    else
        msg_error "No compatible package manager detected, aborting..."
        return 1
    fi
}

detect_distribution() {
    if [[ ! -f /etc/os-release ]]; then
        msg_error "Distribution could not be identified (/etc/os-release does not exist)."
        exit 1
    fi

    source /etc/os-release

    local os_id="${ID:-}"
    local os_like="${ID_LIKE:-}"
    local target_module=""

    case "${os_id}" in
        debian|ubuntu|pop|mint|kali|raspbian) target_module="debian" ;;
        arch|manjaro|endeavouros|garuda)       target_module="arch" ;;
        fedora|rhel|centos)                    target_module="fedora" ;;
    esac

    if [[ -z "${target_module}" && -n "${os_like}" ]]; then
        for family in ${os_like}; do
            case "${family}" in
                debian|ubuntu) target_module="debian"; break ;;
                arch)          target_module="arch"; break ;;
                fedora|rhel)   target_module="fedora"; break ;;
            esac
        done
    fi

    if [[ -z "${target_module}" ]]; then
        msg_error "Unsupported distribution: ID='${os_id}'"
        exit 1
    fi

    echo $target_module
}

is_server_environment() {
    local default_target
    default_target=$(systemctl get-default 2>/dev/null || echo "")
 
    if [[ "$default_target" == "graphical.target" ]]; then
        return 1 # Desktop environment
    fi

    if pgrep -x "Xorg" &>/dev/null || pgrep -x "wayland" &>/dev/null || \
       systemctl is-active --quiet gdm 2>/dev/null || \
       systemctl is-active --quiet gdm3 2>/dev/null || \
       systemctl is-active --quiet lightdm 2>/dev/null || \
       systemctl is-active --quiet sddm 2>/dev/null; then
        return 1 # Desktop environment
    fi

    return 0 # Server environment
}