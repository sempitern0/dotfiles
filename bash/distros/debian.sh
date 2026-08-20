#!/usr/bin/env bash
set -euo pipefail

PACKAGE_MANAGER="apt"

PPA_REPOS=(
    "ppa:zhangsongcui3371/fastfetch"
)

PACKAGES=(
    coreutils
    ntpsec
    curl
    wget
    inetutils-traceroute
    net-tools
    apt-transport-https
    vim
    git
    software-properties-common
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
    whatweb
    fzf
    ripgrep
    jq
)

INSTALL_CMD=("${PACKAGE_MANAGER}" "install" "-y")
UPDATE_CMD=("${PACKAGE_MANAGER}" "update")
UPGRADE_CMD=("${PACKAGE_MANAGER}" "upgrade" "-y")
CLEANUP_CMD=("${PACKAGE_MANAGER}" "autoremove" "-y" "--purge")
REPO_CMD=("add-apt-repository" "-y")

msg_info "Preparing DEBIAN environment..."


install_system_packages() {
    if [ -n "${PPA_REPOS+x}" ] && [ ${#PPA_REPOS[@]} -gt 0 ]; then
        if [ ${#REPO_CMD[@]} -gt 0 ] && command -v "${REPO_CMD[1]}" &>/dev/null; then
            msg_info "Adding external repositories..."
            for repo in "${PPA_REPOS[@]}"; do
                msg_info "Adding repository: ${repo}"
                "${REPO_CMD[@]}" "${repo}"
            done
        else
            msg_warn "Skipping PPAs: '${REPO_CMD[1]:-add-apt-repository}' is not available on this system."
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