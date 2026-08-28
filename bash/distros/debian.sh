#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

export DEBIAN_FRONTEND=noninteractive
PACKAGE_MANAGER="apt"

msg_info()    { echo -e "\e[34m[INFO]\e[0m $*"; }
msg_success() { echo -e "\e[32m[OK]\e[0m $*"; }
msg_warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }
msg_error()   { echo -e "\e[31m[ERROR]\e[0m $*"; }

PPA_REPOS=()

PACKAGES=(
    coreutils man-db man-pages curl wget ca-certificates tree vim git sudo
    build-essential software-properties-common lsb-release jq fzf
    htop iftop btop bat ripgrep fd-find ncdu duf micro
    inetutils-traceroute net-tools mtr dnsutils psmisc lsof
    nmap whois lynis chkrootkit whatweb ufw tcpdump tshark
    bluez bluez-tools ntpsec zram-tools 
)

GUI_PACKAGES=(
    xclip feh chafa kitty tilix
)

SYSTEM_SERVICES=(
    "fstrim.timer"     
    "zramswap.service"  
    "bluetooth.service" 
)

USER_SERVICES=()

# APT commands
INSTALL_CMD=("${PACKAGE_MANAGER}" "install" "-y" "-q")
UPDATE_CMD=("${PACKAGE_MANAGER}" "update" "-q")
UPGRADE_CMD=("${PACKAGE_MANAGER}" "-y" "-o" "Dpkg::Options::=--force-confdef" "-o" "Dpkg::Options::=--force-confold" "upgrade")
CLEANUP_CMD=("${PACKAGE_MANAGER}" "autoremove" "-y" "--purge")
REPO_CMD=("add-apt-repository" "-y")

# Return valid packages via stdout while routing warnings to stderr
get_valid_packages() {
    local valid=()
    for pkg in "$@"; do
        if apt-cache show "$pkg" &>/dev/null; then
            valid+=("$pkg")
        else
            msg_warn "Package '$pkg' was not found in repositories. Skipping..." >&2
        fi
    done
    echo "${valid[@]}"
}

install_system_packages() {
    if [ ${#UPDATE_CMD[@]} -gt 0 ]; then
        msg_info "Updating package lists..."
        "${UPDATE_CMD[@]}" || return 1
    fi

    # Install prerequisites for external repositories
    if [ -n "${PPA_REPOS+x}" ] && [ ${#PPA_REPOS[@]} -gt 0 ]; then
        msg_info "Installing prerequisites for external repositories..."
        "${INSTALL_CMD[@]}" software-properties-common &>/dev/null || true
        
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
        msg_info "Filtering available packages..."
        
        # Populate array with validated package output
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
    
    install_fastfetch

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

install_fastfetch() {
    if command -v fastfetch &>/dev/null; then
        msg_info "Fastfetch ya está instalado."
        return 0
    fi

    msg_info "Instalando Fastfetch..."
    
    # Intentar via APT (si existe en Debian Trixie/Testing/Sid o Backports)
    if apt-cache show fastfetch &>/dev/null; then
        "${INSTALL_CMD[@]}" fastfetch &>/dev/null && msg_success "Fastfetch instalado desde repositorios APT." && return 0
    fi

    # Fallback: Descargar el último paquete .deb oficial desde GitHub (Debian 12 Bookworm)
    msg_info "Fastfetch no está en APT. Obteniendo última versión de GitHub Releases..."
    local deb_url
    deb_url=$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | jq -r '.assets[] | select(.name | test("linux-amd64\\.deb$")) | .browser_download_url' 2>/dev/null || true)

    if [[ -n "$deb_url" && "$deb_url" != "null" ]]; then
        local temp_deb="/tmp/fastfetch_latest.deb"
        wget -q "$deb_url" -O "$temp_deb"
        dpkg -i "$temp_deb" &>/dev/null || "${PACKAGE_MANAGER}" install -f -y -q &>/dev/null
        rm -f "$temp_deb"
        msg_success "Fastfetch instalado correctamente desde GitHub."
    else
        msg_warn "No se pudo obtener el ejecutable de Fastfetch desde GitHub. Omitiendo..."
    fi
}

msg_info "Preparing DEBIAN environment for user: ${TARGET_USER} (${TARGET_HOME})..."
install_system_packages
enable_systemd_services