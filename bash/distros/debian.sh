#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

export DEBIAN_FRONTEND=noninteractive
PACKAGE_MANAGER="apt"

PPA_REPOS=(
    "ppa:zhangsongcui3371/fastfetch"
)

PACKAGES=(
    coreutils man-db man-pages curl wget ca-certificates tree vim git sudo
    build-essential software-properties-common lsb-release
    htop iftop bat fastfetch jq fzf ripgrep fd-find ncdu duf micro
    inetutils-traceroute net-tools nmap lynis chkrootkit whatweb ufw
    bluez bluez-tools ntpsec zram-tools
)

GUI_PACKAGES=(
    xclip feh chafa kitty
)

SYSTEM_SERVICES=(
    "fstrim.timer"     
    "zramswap.service"  
    "bluetooth.service" 
    "ufw.service"
)

USER_SERVICES=()

# Comandos de APT
INSTALL_CMD=("${PACKAGE_MANAGER}" "install" "-y" "-q")
UPDATE_CMD=("${PACKAGE_MANAGER}" "update" "-q")
UPGRADE_CMD=("${PACKAGE_MANAGER}" "-y" "-o" "Dpkg::Options::=--force-confdef" "-o" "Dpkg::Options::=--force-confold" "upgrade")
CLEANUP_CMD=("${PACKAGE_MANAGER}" "autoremove" "-y" "--purge")
REPO_CMD=("add-apt-repository" "-y")

msg_info "Preparing DEBIAN environment for user: ${TARGET_USER} (${TARGET_HOME})..."

install_system_packages() {
    if [ ${#UPDATE_CMD[@]} -gt 0 ]; then
        msg_info "Updating package lists..."
        "${UPDATE_CMD[@]}" || return 1
    fi

    # Instalar prerrequisitos para la gestión de repositorios externos
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

    # Merge de paquetes GUI si se detecta un entorno gráfico
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

enable_systemd_services() {
    msg_info "Enabling system-level services..."

    for service in "${SYSTEM_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null || systemctl is-enabled --quiet "$service" 2>/dev/null; then
            msg_info "Service '${service}' is already active/enabled."
        else
            if systemctl enable --now "$service" &>/dev/null; then
                msg_success "Enabled system service: ${service}"
            else
                msg_error "Failed to enable system service: ${service}"
            fi
        fi
    done

    if [ ${#USER_SERVICES[@]} -gt 0 ]; then
        msg_info "Enabling user-level services for ${TARGET_USER}..."
        local target_uid
        target_uid=$(id -u "$TARGET_USER")

        for user_service in "${USER_SERVICES[@]}"; do
            if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/${target_uid}" systemctl --user enable "$user_service" &>/dev/null; then
                msg_success "Enabled user service: ${user_service}"
            else
                msg_error "Failed to enable user service: ${user_service}"
            fi
        done
    fi
}

install_system_packages
enable_systemd_services