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

# Check if running under Windows Subsystem for Linux (WSL)
is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi "microsoft" /proc/version 2>/dev/null
}

copy_with_backup() {
    local src="$1"
    local dest="$2"
    local user="$3"

    if [[ ! -f "$src" ]]; then
        msg_error "Source file '$src' does not exist."
        return 1
    fi

    if [[ -f "$dest" ]]; then
        local backup_file="$dest.bak"

        if [[ ! -f "$backup_file" ]]; then
            msg_warn "Existing file found at '$dest'. Backing up to '$backup_file'..."
            cp -f "$dest" "$backup_file"
            chown "$user:$user" "$backup_file"
        else
            msg_info "Backup '$backup_file' already exists. Skipping backup creation to preserve the original."
        fi
    fi

    msg_info "Copying '$(basename "$src")' -> '$dest'..."
    cp -f "$src" "$dest"
    chown "$user:$user" "$dest"
}

print_section() {
    local title="$1"
    echo -e "\n${cyanColour}======================================================================${endColour}"
    echo -e "${cyanColour}  :: ${title}${endColour}"
    echo -e "${cyanColour}======================================================================${endColour}\n"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_error "This script requires root privileges. Please run with sudo."
        exit 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

prompt_confirmation() {
    local prompt_msg="$1"
    local default_ans="${2:-N}"
    local response
    
    read -rp "$(echo -e "${yellowColour}[?] ${prompt_msg} [y/N]: ${endColour}")" response
    response="${response:-$default_ans}"
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        msg_info "Operation cancelled by user."
        return 1
    fi
    return 0
}

ensure_sudo_installed() {
    if ! command -v sudo &>/dev/null; then
        msg_info "'sudo' is not installed."

        if [[ $EUID -ne 0 ]]; then
            msg_error "'sudo' is missing and script is not running as root. Run with 'su -c ./script.sh' or install sudo manually."
            exit 1
        fi

        msg_info "Installing 'sudo'..."
        if command -v pacman &>/dev/null; then
            pacman -S --noconfirm --needed sudo
        elif command -v apt-get &>/dev/null; then
            apt-get update -q && apt-get install -y -q sudo
        fi
    fi
}

