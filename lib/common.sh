# shellcheck disable=SC2034,SC2329

# ==========================================
# Color variables on ANSI
# ==========================================
redColour=$'\033[0;31m'
greenColour=$'\033[0;32m'
yellowColour=$'\033[0;33m'
blueColour=$'\033[0;34m'
purpleColour=$'\033[0;35m'
cyanColour=$'\033[0;36m'
grayColour=$'\033[0;90m'

boldRed=$'\033[1;31m'
boldGreen=$'\033[1;32m'
boldYellow=$'\033[1;33m'
boldBlue=$'\033[1;34m'
boldPurple=$'\033[1;35m'
boldCyan=$'\033[1;36m'
boldWhite=$'\033[1;37m'

endColour=$'\033[0m'

msg_info()     { echo -e "${cyanColour}[INFO]${endColour} $*" >&2; }
msg_success()  { echo -e "${greenColour}[OK]${endColour} $*" >&2; }
msg_warn()     { echo -e "${yellowColour}[WARN]${endColour} $*" >&2; }
msg_error()    { echo -e "${redColour}[ERROR]${endColour} $*" >&2; }

msg_search()   { echo -e "${purpleColour}[SEARCH]${endColour} $*" >&2; }
msg_exec()     { echo -e "${blueColour}[EXEC]${endColour} $*" >&2; }
msg_download() { echo -e "${boldBlue}[FETCH]${endColour} $*" >&2; }
msg_build()    { echo -e "${boldCyan}[BUILD]${endColour} $*" >&2; }
msg_skip()     { echo -e "${grayColour}[SKIP]${endColour} $*" >&2; }
msg_debug()    { echo -e "${grayColour}[DEBUG]${endColour} $*" >&2; }

print_separator() { echo -e "${grayColour}--------------------------------------------------${endColour}"; }

# Example: if command_exists "docker"; then docker compose up -d; fi
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Example: die "Critical config missing in /etc/app.conf"
die() {
    msg_error "$*"
    exit 1
}

detect_package_manager() {
    if command_exists apt; then
        echo "apt"
    elif command_exists pacman; then
        echo "pacman"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists zypper; then
        echo "zypper"
    elif command_exists apk; then
        echo "apk"
    elif command_exists brew; then
        echo "brew"
    elif command_exists yum; then
        echo "yum"
    else
        msg_error "No compatible package manager detected, aborting..."
        return 1
    fi
}

detect_distribution() {
    local os_id=""
    local os_like=""

    if [ -f /etc/os-release ]; then
        os_id=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
        os_like=$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
    elif command_exists lsb_release; then
        os_id=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/debian_version ]; then
        os_id="debian"
    elif [ -f /etc/arch-release ]; then
        os_id="arch"
    elif [ -f /etc/redhat-release ]; then
        os_id="fedora"
    elif [ -f /etc/SuSE-release ]; then
        os_id="opensuse"
    fi

    case "$os_id" in
        debian|ubuntu|mint|pop|kali|elementary|raspbian|neon)
            echo "debian"
            return 0
            ;;
        arch|manjaro|endeavouros|garuda|artix|cachyos)
            echo "arch"
            return 0
            ;;
        fedora|rhel|rocky|almalinux|centos|nobara|ol)
            echo "fedora"
            return 0
            ;;
        opensuse*|suse|sles)
            echo "opensuse"
            return 0
            ;;
        alpine)
            echo "alpine"
            return 0
            ;;
    esac

    for like in $os_like; do
        case "$like" in
            *debian*|*ubuntu*)
                echo "debian"
                return 0
                ;;
            *arch*)
                echo "arch"
                return 0
                ;;
            *fedora*|*rhel*|*centos*)
                echo "fedora"
                return 0
                ;;
            *suse*)
                echo "opensuse"
                return 0
                ;;
        esac
    done

    if command_exists apt-get; then
        echo "debian"
    elif command_exists pacman; then
        echo "arch"
    elif command_exists dnf || command_exists yum; then
        echo "fedora"
    elif command_exists zypper; then
        echo "opensuse"
    elif command_exists apk; then
        echo "alpine"
    else
        echo "unknown"
        return 1
    fi
}


detect_hypervisor() {
    local raw_virt=""

    if command_exists systemd-detect-virt; then
        raw_virt=$(systemd-detect-virt 2>/dev/null || true)
    fi

    if [[ -z "$raw_virt" || "$raw_virt" == "none" ]]; then
        local dmi_info=""

        if [[ -f /sys/class/dmi/id/sys_vendor || -f /sys/class/dmi/id/product_name ]]; then
            dmi_info="$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        fi

        case "$dmi_info" in
            *virtualbox*|*innotek*) raw_virt="virtualbox" ;;
            *vmware*)               raw_virt="vmware" ;;
            *qemu*)                 raw_virt="qemu" ;;
            *kvm*)                  raw_virt="kvm" ;;
            *microsoft*|*hyper-v*)  raw_virt="hyperv" ;;
            *xen*)                  raw_virt="xen" ;;
        esac
    fi

    local target_hypervisor=""

    case "${raw_virt}" in
        oracle|virtualbox)     target_hypervisor="virtualbox" ;;
        vmware)                target_hypervisor="vmware" ;;
        qemu|bochs)            target_hypervisor="qemu" ;;
        kvm)                   target_hypervisor="kvm" ;;
        microsoft|hyper-v)     target_hypervisor="hyperv" ;;
        xen)                   target_hypervisor="xen" ;;
        bhyve)                 target_hypervisor="bhyve" ;;
        wsl)                   target_hypervisor="wsl" ;;
        none|"")               target_hypervisor="none" ;;
        *)                     target_hypervisor="${raw_virt}" ;;
    esac

    echo "$target_hypervisor"

    if [[ "$target_hypervisor" == "none" ]]; then
        return 1
    fi
    
    return 0
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

is_ci() {
    [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${GITLAB_CI:-}" || -n "${CIRCLECI:-}" ]]
}

# Example: copy_with_backup "app.conf" "/etc/app.conf" "www-data"
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
            chown "$user:" "$backup_file"
        else
            msg_info "Backup '$backup_file' already exists. Skipping backup creation to preserve the original."
        fi
    fi

    msg_info "Copying '$(basename "$src")' -> '$dest'..."
    cp -f "$src" "$dest"
    chown "$user:" "$dest" 
}

print_section() {
    echo -e "\n${boldWhite}===> $*${endColour}" >&2
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_error "This script requires root privileges. Please run with sudo."
        exit 1
    fi
}


# Example: require_commands "git" "curl" "jq"
require_commands() {
    local missing=()

    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        msg_error "Missing required dependencies: ${missing[*]}"
        return 1
    fi
}

# Example: clean_slug=$(slugify " My Project Name #1! ") --> my-project-name-#1
slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-|-$//g'
}

# Example: trimmed_str=$(trim "   lots of whitespace   ")
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

# Example: if prompt_confirmation "Overwrite existing database?" "N"; then drop_db; fi
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

# Example: long_running_task & spinner $! "Extracting big archive..."
### A quick test to see if its working ###
#   sleep 4 &
#   spinner $! "Downloading packages..."
spinner() {
    local pid="$1"
    local delay=0.1
    local spinstr="|/-\\"
    local msg="${2:-Working...}"

    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "  ${cyanColour}[%c]${endColour} %s\r" "$spinstr" "$msg" >&2
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "    \r" >&2
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

# Example: ensure_dir "/var/log/my-app"
ensure_dir() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || die "Failed to create directory: $dir"
    fi
}

# Example: download_file "https://example.com/config.json" "/tmp/config.json"
download_file() {
    local url="$1"
    local dest="$2"

    msg_download "Downloading $url -> $dest"
    if command_exists curl; then
        curl -fsSL "$url" -o "$dest"
    elif command_exists wget; then
        wget -qO "$dest" "$url"
    else
        msg_error "Neither curl nor wget is available."
        return 1
    fi
}

# Example: show_progress_bar "$current_step" "$total_steps" 40
### Quick test to see if its working ###
#   total_items=20

#   for ((i=1; i<=total_items; i++)); do
#     sleep 0.15
#     show_progress_bar "$i" "$total_items" 30
#   done

show_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-30}"

    if [[ "$total" -eq 0 ]]; then
        return 0
    fi

    local percent=$(( current * 100 / total ))
    local filled_len=$(( current * width / total ))
    local empty_len=$(( width - filled_len ))

    local filled=""
    local empty=""

    if [[ "$filled_len" -gt 0 ]]; then
        printf -v filled "%${filled_len}s"
        filled="${filled// /█}"
    fi

    if [[ "$empty_len" -gt 0 ]]; then
        printf -v empty "%${empty_len}s"
        empty="${empty// /░}"
    fi

    printf "\r\033[K\033[1;36m[Generating...]\033[0m [%s%s] %3d%% (%d/%d)" "$filled" "$empty" "$percent" "$current" "$total"

    if [[ "$current" -eq "$total" ]]; then
        echo ""
    fi
}