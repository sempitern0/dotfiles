#!/usr/bin/env bash
set -euo pipefail

# Contexto global
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

PACKAGE_MANAGER="pacman"
AUR_HELPER=""

INSTALL_CMD=("${PACKAGE_MANAGER}" "-S" "--noconfirm" "--needed")
UPDATE_CMD=("${PACKAGE_MANAGER}" "-Sy")
UPGRADE_CMD=("${PACKAGE_MANAGER}" "-Syu" "--noconfirm")
CLEANUP_CMD=(
    "bash" "-c"
    "pacman -Sc --noconfirm && (orphans=\$(pacman -Qtdq 2>/dev/null); [ -n \"\$orphans\" ] && pacman -Rns --noconfirm \$orphans || true)"
)

# Essential CLI tools
PACKAGES=(
    coreutils man-db man-pages curl wget ca-certificates tree vim git
    htop iftop bat fastfetch jq fzf ripgrep inetutils 
    traceroute net-tools nmap lynis bluez bluez-utils bluez-deprecated-tools 
    ntp reflector
)

# Graphical tools
GUI_PACKAGES=(
    xclip feh chafa kitty
)

AUR_PACKAGES=(
    profile-sync-daemon
    auto-cpufreq
    downgrade
    pacseek-bin   
    librewolf-bin   
    czkawka-cli-bin
    chkrootkit 
    whatweb
)

# Systemd services (System level)
SYSTEM_SERVICES=(
    "fstrim.timer"          # SSD HEALTH TRIM
    "paccache.timer"        # Auto pacman cache cleaner
    "auto-cpufreq.service"  # Battery optimizer
    "bluetooth.service"     # Bluetooth manager
)

# Systemd services (User level)
USER_SERVICES=(
    "psd.service"           # Profile Sync Daemon (browser cache on RAM)
)

setup_user_and_sudo() {
    # 1. Asegurar la presencia de sudo
    if ! command -v sudo &>/dev/null; then
        msg_info "Installing 'sudo'..."
        pacman -S --needed --noconfirm sudo
    fi

    # 2. Configurar el grupo wheel en /etc/sudoers.d/
    if [ ! -f /etc/sudoers.d/10-wheel ]; then
        msg_info "Configuring sudoers access for group 'wheel'..."
        echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
        chmod 0440 /etc/sudoers.d/10-wheel
    fi

    # 3. Gestionar la creación/asignación del usuario estándar
    if [[ "$TARGET_USER" == "root" ]]; then
        echo ""
        read -r -p "Enter username for the standard user: " NEW_USER
        if [[ -z "$NEW_USER" ]]; then
            msg_error "Username cannot be empty."
            return 1
        fi

        if id "$NEW_USER" &>/dev/null; then
            msg_info "User '$NEW_USER' already exists. Adding to 'wheel' and 'users' groups..."
            usermod -aG wheel,users,storage,power "$NEW_USER"
        else
            msg_info "Creating user '$NEW_USER'..."
            useradd -m -g users -G wheel,storage,power -s /bin/bash "$NEW_USER"
            
            msg_info "Set password for $NEW_USER:"
            passwd "$NEW_USER"
            msg_success "User '$NEW_USER' created and assigned to 'wheel' & 'users'."
        fi

        # Actualizar variables de contexto global para el resto de funciones
        TARGET_USER="$NEW_USER"
        TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    else
        msg_info "Ensuring '$TARGET_USER' belongs to 'wheel' and 'users' groups..."
        usermod -aG wheel,users "$TARGET_USER" 2>/dev/null || true
    fi

    msg_info "Preparing ARCH environment for user: ${TARGET_USER} (${TARGET_HOME})..."
}

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

    if [[ "$TARGET_USER" == "root" ]]; then
        msg_error "makepkg cannot be executed as root."
        return 1
    fi

    local build_dir="/tmp/yay-bin"
    rm -rf "$build_dir"

    msg_info "Cloning yay-bin repository for user $TARGET_USER..."
    sudo -u "$TARGET_USER" git clone -q https://aur.archlinux.org/yay-bin.git "$build_dir"

    (
        cd "$build_dir" || exit 1
        msg_info "Compiling and installing yay-bin..."
        sudo -u "$TARGET_USER" makepkg -si --noconfirm &>/dev/null
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

    msg_info "Installing AUR packages through ${AUR_HELPER}..."

    if [[ $EUID -eq 0 ]]; then
        sudo -u "$TARGET_USER" "$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"
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

# Flujo principal de ejecución
setup_user_and_sudo
install_system_packages
install_aur_packages
enable_systemd_services