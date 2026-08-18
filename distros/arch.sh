#!/usr/bin/env bash

PACKAGE_MANAGER="pacman"

INSTALL_CMD=("sudo" "${PACKAGE_MANAGER}" "-S" "--noconfirm" "--needed")
UPDATE_CMD=("sudo" "${PACKAGE_MANAGER}" "-Sy")
UPGRADE_CMD=("sudo" "${PACKAGE_MANAGER}" "-Syu" "--noconfirm")
REPO_CMD=()
CLEANUP_CMD=(
    "bash" "-c"
    "sudo pacman -Sc --noconfirm && (orphans=\$(pacman -Qtdq 2>/dev/null); [ -n \"\$orphans\" ] && sudo pacman -Rns --noconfirm \$orphans || true)"
)

PPA_REPOS=()

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