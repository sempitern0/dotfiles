#!/usr/bin/env bash

PACKAGE_MANAGER="pacman"
AUR_HELPER=""


INSTALL_CMD=("${PACKAGE_MANAGER}" "-S" "--noconfirm" "--needed")
UPDATE_CMD=("${PACKAGE_MANAGER}" "-Sy")
UPGRADE_CMD=("${PACKAGE_MANAGER}" "-Syu" "--noconfirm")
REPO_CMD=()
CLEANUP_CMD=(
    "bash" "-c"
    "pacman -Sc --noconfirm && (orphans=\$(pacman -Qtdq 2>/dev/null); [ -n \"\$orphans\" ] && pacman -Rns --noconfirm \$orphans || true)"
)

PPA_REPOS=()
AUR_PACKAGES=()

PACKAGES=(
    coreutils
    ntp
    curl
    wget
    inetutils
    traceroute
    net-tools
    vim
    git
    ca-certificates
    tree
    xclip
    htop
    iftop
source "${CURRENT_DIR}/lib/common.sh"
    feh
    chafa
    bat
    kitty
    lynis
    chkrootkit
    fastfetch
    nmap
    fzf
    ripgrep
    jq
)

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

    pacman -S --needed --noconfirm base-devel git

    local target_user="${SUDO_USER:-$USER}"

    if [[ "$target_user" == "root" ]]; then
        msg_error "makepkg cannot be executed as root."
        return 1
    fi

    local build_dir="/tmp/yay-bin"
    rm -rf "$build_dir"

    msg_info "Cloning  yay-bin repository for user $target_user..."
    sudo -u "$target_user" git clone https://aur.archlinux.org/yay-bin.git "$build_dir"

    (
        cd "$build_dir" || exit 1
        msg_info "Compilando e instalando yay-bin..."
        sudo -u "$target_user" makepkg -si --noconfirm
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
    if [ -z "${AUR_PACKAGES+x}" ] || [ ${#AUR_PACKAGES[@]} -eq 0 ]; then
        return 0
    fi

    msg_info "Detected ${#AUR_PACKAGES[@]} AUR packages to install."

    ensure_aur_helper || return 1

    local target_user="${SUDO_USER:-$USER}"

    msg_info "Installing AUR packages through ${AUR_HELPER}: ${AUR_PACKAGES[*]}"

    if [[ $EUID -eq 0 ]]; then
        sudo -u "$target_user" "$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"
    else
        "$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"
    fi

    msg_success "AUR packages installed with success."
}

install_system_packages() {
   if [ -n "${PPA_REPOS+x}" ] && [ ${#PPA_REPOS[@]} -gt 0 ]; then
        if [ ${#REPO_CMD[@]} -gt 0 ] && command -v "${REPO_CMD[1]}" &>/dev/null; then
            msg_info "Adding external repositories..."
            for repo in "${PPA_REPOS[@]}"; do
                msg_info "Adding repository: ${repo}"
                "${REPO_CMD[@]}" "${repo}"
            done
        else
            msg_warn "Skipping PPAs: '${REPO_CMD[0]:-add-apt-repository}' is not available on this system."
        fi
    fi

    if [ ${#UPDATE_CMD[@]} -gt 0 ]; then
        msg_info "Updating package lists..."
        if ! "${UPDATE_CMD[@]}"; then
            msg_error "The package lists update failed"
            return 1
        fi
    fi

    if [ ${#UPGRADE_CMD[@]} -gt 0 ]; then
        msg_info "Updating system packages..."
        "${UPGRADE_CMD[@]}"
    fi
    
    if [ -n "${PACKAGES+x}" ] && [ ${#PACKAGES[@]} -gt 0 ]; then
        msg_info "Installing selected (${#PACKAGES[@]} packages)..."
        if "${INSTALL_CMD[@]}" "${PACKAGES[@]}"; then
            msg_success "All packages installed succesfully!"
        else
            msg_error "An error happened installing one or more packages"
            return 1
        fi
    else
        msg_warn "There is no packages to install"
    fi

    if [ ${#CLEANUP_CMD[@]} -gt 0 ]; then
        msg_info "Cleaning orphan packages..."
        "${CLEANUP_CMD[@]}" &> /dev/null || msg_warn "Cleanup finished with warnings"
    fi
}

install_system_packages
install_aur_packages