#!/usr/bin/env bash
set -euo pipefail

PACKAGE_MANAGER="pacman"
AUR_HELPER=""

INSTALL_CMD=("${PACKAGE_MANAGER}" "-S" "--noconfirm" "--needed")
UPDATE_CMD=("${PACKAGE_MANAGER}" "-Sy")
UPGRADE_CMD=("${PACKAGE_MANAGER}" "-Syu" "--noconfirm")
CLEANUP_CMD=(
    "bash" "-c"
    "pacman -Sc --noconfirm && (orphans=\$(pacman -Qtdq 2>/dev/null); [ -n \"\$orphans\" ] && pacman -Rns --noconfirm \$orphans || true)"
)

# Essential CLI tools for all environments
PACKAGES=(
    coreutils man-db ntp curl wget inetutils traceroute net-tools 
    vim git ca-certificates tree htop iftop bat lynis 
    chkrootkit fastfetch nmap fzf ripgrep jq
)

# Graphical tools (Only installed on desktops)
GUI_PACKAGES=(
    xclip feh chafa kitty
)

AUR_PACKAGES=()

msg_info "Preparing ARCH environment..."

ensure_aur_helper() {
    if command -v paru &>/dev/null; then
        AUR_HELPER="paru"
        return 0
    elif command -v yay &>/dev/null; then
        AUR_HELPER="yay"
        return 0
    fi

    msg_info "No AUR helper found. Installing 'yay-bin'..."

    # Ensure base-devel and git are installed before trying to build
    pacman -S --needed --noconfirm base-devel git sudo &>/dev/null

    local target_user="${SUDO_USER:-$USER}"

    if [[ "$target_user" == "root" ]]; then
        msg_error "makepkg cannot be executed as root. Please run the script using sudo from a standard user."
        return 1
    fi

    local build_dir="/tmp/yay-bin"
    rm -rf "$build_dir"

    msg_info "Cloning yay-bin repository for user $target_user..."
    sudo -u "$target_user" git clone -q https://aur.archlinux.org/yay-bin.git "$build_dir"

    (
        cd "$build_dir" || exit 1
        msg_info "Compiling and installing yay-bin..."
        sudo -u "$target_user" makepkg -si --noconfirm &>/dev/null
    )

    rm -rf "$build_dir"

    if command -v yay &>/dev/null; then
        AUR_HELPER="yay"
        msg_success "AUR helper 'yay' installed."
    else
        msg_error "An error happened installing AUR helper."
        return 1
    fi
}

install_aur_packages() {
    if [ ${#AUR_PACKAGES[@]} -eq 0 ]; then
        return 0
    fi

    msg_info "Detected ${#AUR_PACKAGES[@]} AUR packages to install."
    ensure_aur_helper || return 1

    local target_user="${SUDO_USER:-$USER}"

    msg_info "Installing AUR packages through ${AUR_HELPER}..."

    if [[ $EUID -eq 0 ]]; then
        sudo -u "$target_user" "$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"
    else
        "$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"
    fi

    msg_success "AUR packages installed successfully."
}

install_system_packages() {
    if [ ${#UPDATE_CMD[@]} -gt 0 ]; then
        msg_info "Updating package lists..."
        "${UPDATE_CMD[@]}" &>/dev/null || return 1
    fi

    if [ ${#UPGRADE_CMD[@]} -gt 0 ]; then
        msg_info "Updating system packages..."
        "${UPGRADE_CMD[@]}" &>/dev/null
    fi
    
    # Merge GUI packages if a desktop environment is detected
    if ! is_server_environment; then
        msg_info "Desktop environment detected. Adding GUI packages..."
        PACKAGES+=("${GUI_PACKAGES[@]}")
    fi

    if [ ${#PACKAGES[@]} -gt 0 ]; then
        msg_info "Installing ${#PACKAGES[@]} packages..."
        if "${INSTALL_CMD[@]}" "${PACKAGES[@]}"; then
            msg_success "All packages installed successfully!"
        else
            msg_error "An error happened installing one or more packages."
            return 1
        fi
    fi

    if [ ${#CLEANUP_CMD[@]} -gt 0 ]; then
        msg_info "Cleaning orphan packages..."
        "${CLEANUP_CMD[@]}" &> /dev/null || true
    fi
}

install_system_packages
install_aur_packages