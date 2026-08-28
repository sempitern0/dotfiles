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
    traceroute net-tools bind whois nmap lynis bluez bluez-utils bluez-deprecated-tools 
    ntp reflector intel-ucode amd-ucode linux-firmware sof-firmware
    alsa-firmware mesa vulkan-intel vulkan-radeon vulkan-mesa-layers
    xf86-video-amdgpu xf86-video-ati xf86-video-nouveau xf86-video-intel
    dosfstools ntfs-3g exfatprogs mtools udisks2 wireless-regdb
    usb_modeswitch mobile-broadband-provider-info usbmuxd
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
    "reflector.timer"       # Auto mirrorlist update
)

# Systemd services (User level)
USER_SERVICES=(
    "psd.service"           # Profile Sync Daemon (browser cache on RAM)
)


# Filter official packages using pacman -Si
get_valid_pacman_packages() {
    local valid=()
    for pkg in "$@"; do
        if pacman -Si "$pkg" &>/dev/null; then
            valid+=("$pkg")
        else
            msg_warn "Official package '$pkg' was not found in repositories. Skipping..." >&2
        fi
    done
    echo "${valid[@]}"
}

# Filter AUR packages using yay/paru -Si
get_valid_aur_packages() {
    local helper="$1"
    shift
    local valid=()

    for pkg in "$@"; do
        if [[ $EUID -eq 0 ]]; then
            if sudo -u "$TARGET_USER" "$helper" -Si "$pkg" &>/dev/null; then
                valid+=("$pkg")
            else
                msg_warn "AUR package '$pkg' was not found. Skipping..." >&2
            fi
        else
            if "$helper" -Si "$pkg" &>/dev/null; then
                valid+=("$pkg")
            else
                msg_warn "AUR package '$pkg' was not found. Skipping..." >&2
            fi
        fi
    done
    echo "${valid[@]}"
}

setup_user_and_sudo() {
    # 1. Ensure presence of sudo
    if ! command -v sudo &>/dev/null; then
        msg_info "Installing 'sudo'..."
        pacman -S --needed --noconfirm sudo
    fi

    # 2. Configure wheel group in /etc/sudoers.d/
    if [ ! -f /etc/sudoers.d/10-wheel ]; then
        msg_info "Configuring sudoers access for group 'wheel'..."
        echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
        chmod 0440 /etc/sudoers.d/10-wheel
    fi

    # 3. Manage standard user creation/assignment
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

    msg_info "Detected ${#AUR_PACKAGES[@]} AUR packages to process."
    ensure_aur_helper || return 1

    msg_info "Filtering available AUR packages via ${AUR_HELPER}..."
    read -r -a VALID_AUR_PACKAGES <<< "$(get_valid_aur_packages "$AUR_HELPER" "${AUR_PACKAGES[@]}")"

    if [ ${#VALID_AUR_PACKAGES[@]} -gt 0 ] && [ -n "${VALID_AUR_PACKAGES[0]:-}" ]; then
        msg_info "Installing ${#VALID_AUR_PACKAGES[@]} valid AUR packages..."

        if [[ $EUID -eq 0 ]]; then
            sudo -u "$TARGET_USER" "$AUR_HELPER" -S --needed --noconfirm "${VALID_AUR_PACKAGES[@]}"
        else
            "$AUR_HELPER" -S --needed --noconfirm "${VALID_AUR_PACKAGES[@]}"
        fi

        msg_success "AUR packages installed successfully."
    else
        msg_warn "No valid AUR packages available to install."
    fi
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
        msg_info "Filtering available official packages..."
        read -r -a VALID_PACKAGES <<< "$(get_valid_pacman_packages "${PACKAGES[@]}")"

        if [ ${#VALID_PACKAGES[@]} -gt 0 ] && [ -n "${VALID_PACKAGES[0]:-}" ]; then
            msg_info "Installing ${#VALID_PACKAGES[@]} valid official packages..."
            if "${INSTALL_CMD[@]}" "${VALID_PACKAGES[@]}"; then
                msg_success "All official packages installed successfully!"
            else
                msg_error "An error happened installing one or more packages."
                return 1
            fi
        else
            msg_warn "No valid official packages available to install."
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

configure_reflector() {
    if ! command -v reflector &>/dev/null; then
        msg_info "Reflector is not installed. Skipping mirror setup."
        return 0
    fi

    msg_info "Configuring optimal pacman mirrors with Reflector..."

    local country=""

    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || true)

    if [[ -n "$current_tz" && -f /usr/share/zoneinfo/zone1970.tab ]]; then
        country=$(awk -v tz="$current_tz" '$0 !~ /^#/ && $3 == tz {print $1}' /usr/share/zoneinfo/zone1970.tab 2>/dev/null | cut -d',' -f1 || true)
    fi

    if [[ -z "$country" ]]; then
        country=$(curl -s --max-time 3 https://ipapi.co/country/ 2>/dev/null || true)
    fi

    if [[ -z "$country" ]]; then
        country=$(curl -s --max-time 3 "http://ip-api.com/line/?fields=countryCode" 2>/dev/null || true)
    fi

    country=$(echo "$country" | tr -d '[:space:]')

    if [[ -n "$country" ]]; then
        msg_info "Updating mirrors using country code: $country..."
        if ! reflector --country "$country" --protocol https --latest 15 --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null; then
            msg_warn "Filtering by country '$country' failed. Testing global mirrors..."
            reflector --protocol https --latest 20 --download-timeout 5 --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null || msg_warn "Network unavailable or Reflector failed. Keeping default mirrorlist."
        else
            msg_success "Mirrors updated successfully for country code '$country'."
        fi
    else
        msg_info "Country code unavailable. Fetching fastest global mirrors..."
        reflector --protocol https --latest 20 --download-timeout 5 --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null || msg_warn "Network unavailable or Reflector failed. Keeping default mirrorlist."
    fi

    if [[ -f /etc/reflector.conf ]]; then
        cat <<EOF > /etc/reflector.conf
--save /etc/pacman.d/mirrorlist
--protocol https
--latest 15
--sort rate
EOF
        if [[ -n "$country" ]]; then
            echo "--country '$country'" >> /etc/reflector.conf
        fi
    fi

    return 0
}

configure_portable_initramfs() {
    msg_info "Configuring initramfs for universal hardware support..."

    if [ -f /etc/mkinitcpio.conf ]; then
        msg_info "Detected mkinitcpio. Disabling host autodetect..."
        
        cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak

        sed -i -E 's/\bautodetect\b//g' /etc/mkinitcpio.conf
        sed -i 's/  */ /g' /etc/mkinitcpio.conf

        msg_info "Rebuilding initramfs images with mkinitcpio..."
        if mkinitcpio -P &>/dev/null; then
            msg_success "mkinitcpio configured successfully for portable booting."
        else
            msg_error "Failed to regenerate mkinitcpio images."
        fi
    fi

    if [ -d /etc/dracut.conf.d ]; then
        msg_info "Detected Dracut. Disabling host-only mode..."

        cat <<EOF > /etc/dracut.conf.d/portable.conf
hostonly="no"
EOF

        msg_info "Rebuilding initramfs images with Dracut..."
        if dracut --regenerate-all --force &>/dev/null; then
            msg_success "Dracut configured successfully for portable booting."
        else
            msg_error "Failed to regenerate Dracut images."
        fi
    fi
}

# Main execution flow
setup_user_and_sudo
install_system_packages
configure_reflector
install_aur_packages
enable_systemd_services
configure_portable_initramfs