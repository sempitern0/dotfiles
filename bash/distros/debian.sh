#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
PACKAGE_MANAGER="apt"

PPA_REPOS=(
    "ppa:zhangsongcui3371/fastfetch"
)

# Essential CLI tools for all environments
PACKAGES=(
    coreutils man-db man-pages curl wget ca-certificates tree vim git
    htop iftop bat fastfetch jq fzf ripgrep
    inetutils-traceroute net-tools nmap lynis chkrootkit whatweb
    bluez bluez-utils bluez-deprecated-tools ntpsec software-properties-common
)

# Graphical tools (Only installed on desktops)
GUI_PACKAGES=(
    xclip feh chafa kitty
)

# Using force-confdef to avoid interactive prompts during upgrades
INSTALL_CMD=("${PACKAGE_MANAGER}" "install" "-y" "-q")
UPDATE_CMD=("${PACKAGE_MANAGER}" "update" "-q")
UPGRADE_CMD=("${PACKAGE_MANAGER}" "-y" "-o" "Dpkg::Options::=--force-confdef" "-o" "Dpkg::Options::=--force-confold" "upgrade")
CLEANUP_CMD=("${PACKAGE_MANAGER}" "autoremove" "-y" "--purge")
REPO_CMD=("add-apt-repository" "-y")

msg_info "Preparing DEBIAN environment..."

install_system_packages() {
    if [ ${#UPDATE_CMD[@]} -gt 0 ]; then
        msg_info "Updating package lists..."
        "${UPDATE_CMD[@]}" || return 1
    fi

    # Ensure software-properties-common is installed BEFORE adding PPAs
    if [ -n "${PPA_REPOS+x}" ] && [ ${#PPA_REPOS[@]} -gt 0 ]; then
        msg_info "Installing prerequisites for external repositories..."
        "${INSTALL_CMD[@]}" software-properties-common &>/dev/null
        
        for repo in "${PPA_REPOS[@]}"; do
            msg_info "Adding repository: ${repo}"
            "${REPO_CMD[@]}" "${repo}" &>/dev/null || msg_warn "Failed to add ${repo}"
        done
        "${UPDATE_CMD[@]}" &>/dev/null
    fi

    if [ ${#UPGRADE_CMD[@]} -gt 0 ]; then
        msg_info "Upgrading system packages..."
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