#!/usr/bin/env bash
set -euo pipefail

# Log helpers
msg_info()    { echo -e "\e[34m[INFO]\e[0m $*"; }
msg_success() { echo -e "\e[32m[OK]\e[0m $*"; }
msg_warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }
msg_error()   { echo -e "\e[31m[ERROR]\e[0m $*"; }

# Global context
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

PACKAGE_MANAGER="dnf"

# Commands
INSTALL_CMD=("${PACKAGE_MANAGER}" "install" "-y" "-q")
UPDATE_CMD=("${PACKAGE_MANAGER}" "makecache" "-q")
UPGRADE_CMD=("${PACKAGE_MANAGER}" "upgrade" "-y" "-q")
CLEANUP_CMD=("${PACKAGE_MANAGER}" "autoremove" "-y" "-q")

# Core CLI packages
PACKAGES=(
    coreutils man-db curl wget ca-certificates tree vim git sudo
    gcc gcc-c++ make jq fzf htop iftop btop bat ripgrep fd-find ncdu duf micro
    words bind-utils net-tools traceroute mtr psmisc lsof timeshift
    nmap whois lynis chkrootkit ufw wireshark-cli
    bluez bluez-tools chrony zram-generator golang zoxide fastfetch
)

# Graphical tools
GUI_PACKAGES=(
    xclip feh chafa kitty tilix
)

# Systemd services (System level)
SYSTEM_SERVICES=(
    "fstrim.timer"
    "bluetooth.service"
    "chronyd.service"
)

# Systemd services (User level)
USER_SERVICES=()

# Filter official packages using dnf info / repoquery
get_valid_packages() {
    local valid=()
    for pkg in "$@"; do
        if dnf info "$pkg" &>/dev/null; then
            valid+=("$pkg")
        else
            msg_warn "Package '$pkg' was not found in repositories. Skipping..." >&2
        fi
    done
    echo "${valid[@]}"
}

install_system_packages() {
    if [ ${#UPDATE_CMD[@]} -gt 0 ]; then
        msg_info "Updating repository metadata..."
        "${UPDATE_CMD[@]}" || return 1
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
        msg_info "Filtering available packages..."
        read -r -a VALID_PACKAGES <<< "$(get_valid_packages "${PACKAGES[@]}")"

        if [ ${#VALID_PACKAGES[@]} -gt 0 ] && [ -n "${VALID_PACKAGES[0]:-}" ]; then
            msg_info "Installing ${#VALID_PACKAGES[@]} valid packages..."
            if "${INSTALL_CMD[@]}" "${VALID_PACKAGES[@]}"; then
                msg_success "All packages installed successfully!"
            else
                msg_error "An error happened installing one or more packages."
                return 1
            fi
        else
            msg_warn "No valid packages available to install."
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

msg_info "Preparing FEDORA environment for user: ${TARGET_USER} (${TARGET_HOME})..."
install_system_packages
enable_systemd_services