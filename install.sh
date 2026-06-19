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

CURRENT_DIR=$(dirname -- "$(readlink -f -- "$0")")

PACKAGE_MANAGER=""
declare -a INSTALL_CMD=()
declare -a UPDATE_CMD=()
declare -a UPGRADE_CMD=()
declare -a CLEANUP_CMD=()
declare -a REPO_CMD=()

### DISPLAY INFORMATION FUNCTIONS ###
msg_info() { echo -e "${cyanColour}[INFO]${endColour} $1"; }
msg_success() { echo -e "${greenColour}[OK]${endColour} $1"; }
msg_warn() { echo -e "${yellowColour}[WARN]${endColour} $1"; }
msg_error() { echo -e "${redColour}[ERROR]${endColour} $1" >&2; }
print_separator() { echo -e "${grayColour}--------------------------------------------------${endColour}"; }

detect_package_manager() {
    msg_info "Detecting package manager..."

    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGER="apt"
        INSTALL_CMD=(apt-get install -y)
        UPDATE_CMD=(apt-get update)
        UPGRADE_CMD=(apt-get upgrade -y)
        REPO_CMD=(add-apt-repository -y)
        CLEANUP_CMD=(apt-get autoremove -y --purge)
    elif command -v pacman &> /dev/null; then
        PACKAGE_MANAGER="pacman"
        INSTALL_CMD=(pacman -S --noconfirm)
        UPDATE_CMD=(pacman -Sy)
        UPGRADE_CMD=(pacman -Su --noconfirm)
        CLEANUP_CMD=(pacman -Sc --noconfirm)
    elif command -v dnf &> /dev/null; then
        PACKAGE_MANAGER="dnf"
        INSTALL_CMD=(dnf install -y)
        UPDATE_CMD=(dnf makecache)
        UPGRADE_CMD=(dnf upgrade -y)
        REPO_CMD=(dnf copr enable -y)
        CLEANUP_CMD=(dnf autoremove -y)
    elif command -v zypper &> /dev/null; then
        PACKAGE_MANAGER="zypper"
        INSTALL_CMD=(zypper install -y)
        UPDATE_CMD=(zypper refresh)
        UPGRADE_CMD=(zypper update -y)
        CLEANUP_CMD=(zypper clean -a)
    elif command -v nix &> /dev/null; then
        PACKAGE_MANAGER="nix"
        INSTALL_CMD=(nix-env -iA)
        UPDATE_CMD=(nix-channel --update)
        UPGRADE_CMD=(nix-env -u)
        CLEANUP_CMD=(nix-collect-garbage -d)
    else
        msg_error "Could not find a supported package manager (APT, Pacman, DNF, Zypper, NIX)."
        exit 1
    fi

    msg_success "Package manager detected: ${cyanColour}$PACKAGE_MANAGER${endColour}"
}

update_system() {
    # Definir prefijo de privilegios (Nix no usa sudo por defecto en entornos de usuario)
    local -a prefix=(sudo)
    [[ "$PACKAGE_MANAGER" == "nix" ]] && prefix=()

    # Gestión dinámica y segura de repositorios externos
    if [ ${#REPO_CMD[@]} -gt 0 ]; then
        msg_info "Adding required repositories for $PACKAGE_MANAGER..."
        if [ "$PACKAGE_MANAGER" = "apt" ]; then
            # PPA oficial para fastfetch en Ubuntu/Debian
            "${prefix[@]}" "${REPO_CMD[@]}" "ppa:zhangsongcui3371/fastfetch"
        elif [ "$PACKAGE_MANAGER" = "dnf" ]; then
            # Copr oficial para fastfetch en Fedora/RHEL
            "${prefix[@]}" "${REPO_CMD[@]}" "svart/fastfetch"
        fi
    fi

    msg_info "Updating package lists..."
    # Guardamos logs de error pero permitimos salida estándar en caso de congelamientos
    if ! "${prefix[@]}" "${UPDATE_CMD[@]}" > /tmp/pkg_update.log 2>&1; then
        msg_error "Failed to update. Check /tmp/pkg_update.log for details."
        return 1
    fi

    msg_info "Upgrading system packages (this might take a while)..."
    if ! "${prefix[@]}" "${UPGRADE_CMD[@]}" &> /dev/null; then
        msg_error "System upgrade failed."
        return 1
    fi

    if [ ${#CLEANUP_CMD[@]} -gt 0 ]; then
        msg_info "Cleaning up unused packages and caches..."
        if ! "${prefix[@]}" "${CLEANUP_CMD[@]}" &> /dev/null; then
            msg_warn "System cleanup completed with some warnings."
        fi
    fi

    msg_success "System successfully updated and cleaned!"
}

install_packages() {
    if [ $# -eq 0 ]; then
        msg_warn "No packages to install"
        return 0
    fi

    local packages=("$@")
    local -a prefix=(sudo)
    [[ "$PACKAGE_MANAGER" == "nix" ]] && prefix=()

    msg_info "Installing selected packages: ${purpleColour}${packages[*]}${endColour}..."

    # Ejecución directa expandiendo los arrays de forma segura sin pasar por eval
    if "${prefix[@]}" "${INSTALL_CMD[@]}" "${packages[@]}" &> /dev/null; then
        msg_success "Packages installed successfully!"
    else
        msg_error "Installation failed for one or more packages: ${packages[*]}"
        return 1
    fi
}

configure_bash_files() {
    msg_info "Configuring Bash dotfiles..."

    local target_user="${SUDO_USER:-$USER}"
    local target_home
    target_home=$(getent passwd "$target_user" | cut -d: -f6)

    local source_dir="$CURRENT_DIR/bash"

    if [ ! -d "$source_dir" ]; then
        msg_error "Source directory '$source_dir' not found in the repository."
        return 1
    fi

    local files=(".bashrc" ".bash.aliases")

    for file in "${files[@]}"; do
        local src="$source_dir/$file"
        local dest="$target_home/$file"

        if [ -f "$src" ]; then
            if [ -f "$dest" ]; then
                msg_info "Backing up existing $file to $file.bak"
                cp "$dest" "$dest.bak"
            fi

            msg_info "Copying $file to $target_home..."
            cp "$src" "$dest"

            chown "$target_user:$target_user" "$dest"
            [ -f "$dest.bak" ] && chown "$target_user:$target_user" "$dest.bak"
        else
            msg_warn "File '$file' not found in '$source_dir', skipping."
        fi
    done

    msg_success "Bash dotfiles successfully configured for user $target_user!"
}

configure_vim() {
    local target_user="${SUDO_USER:-$USER}"
    local target_home
    target_home=$(getent passwd "$target_user" | cut -d: -f6)

    if [ -d "$target_home/.vim_runtime" ]; then
        msg_warn "Vim configuration (.vim_runtime) already exists for $target_user. Skipping installation."
        return 0
    fi

    msg_info "Configuring Vim with amix/vimrc for user $target_user..."

    if ! sudo -u "$target_user" git clone --depth=1 https://github.com/amix/vimrc.git "$target_home/.vim_runtime" &> /dev/null; then
        msg_error "Failed to clone amix/vimrc repository."
        return 1
    fi

    if ! sudo -u "$target_user" sh "$target_home/.vim_runtime/install_basic_vimrc.sh" &> /dev/null; then
        msg_error "Failed to run amix/vimrc installer script."
        return 1
    fi

    msg_success "Vim successfully configured for $target_user!"
}

main() {
    if [[ $(uname -s) != "Linux" ]]; then
        msg_error "This script is only compatible with Linux distributions."
        exit 1
    fi

    clear
    print_separator
    echo -e "${cyanColour}Preparing the environment...${endColour}"
    print_separator

    local real_user="${SUDO_USER:-$USER}"
    local real_home
    real_home=$(getent passwd "$real_user" | cut -d: -f6)

    detect_package_manager
    update_system
    print_separator

    install_packages coreutils ntp curl wget inetutils-traceroute vim git software-properties-common ca-certificates tree xclip htop iftop feh bat kitty lynis chkrootkit fastfetch nmap whatweb fzf ripgrep
    print_separator

    configure_bash_files
    print_separator
    configure_vim

    if command -v batcat &> /dev/null; then
        if [ ! -f "$real_home/.local/bin/bat" ]; then
            msg_info "Creating symlink for 'bat' command..."
            mkdir -p "$real_home/.local/bin"
            ln -s /usr/bin/batcat "$real_home/.local/bin/bat"
            chown -R "$real_user:$real_user" "$real_home/.local/bin"
       fi
    fi


    msg_success "The environment is ready to use, enjoy!"
}

main "$@"
