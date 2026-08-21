#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR=$(dirname -- "$(readlink -f -- "$0")")

source "${CURRENT_DIR}/lib/common.sh"

SYSCTL_DIR="/etc/sysctl.d"
UFW_BEFORE_RULES="/etc/ufw/before.rules"

UFW_RULES="$CURRENT_DIR/hardening/network/ufw_rules.sh"
HARDWARE_HARDENING_RULES="$CURRENT_DIR/hardening/hardware/memory_hardening.sh"
ANTIVIRUS_SETUP="$CURRENT_DIR/hardening/antivirus/antivirus.sh"
KERNEL_NETWORK_HARDENING_CONF="$CURRENT_DIR/hardening/network/99-hardening.conf"
FAIL2BAN_CONF_DIR="${CURRENT_DIR}/hardening/fail2ban"
APT_CONF_DIR="/etc/apt/apt.conf.d"
BACKUP_DIR="/var/backups/hardening_suite"
BACKUP_ARCHIVE="${BACKUP_DIR}/system_hardening_initial_state.tar.gz"


print_banner() {
    echo -e "${cyanColour}"
    cat << "EOF"
 ██████╗ ███████╗██████╗ ███████╗██████╗ ██╗███╗   ██╗██████╗ 
██╔════╝ ██╔════╝██╔══██╗██╔════╝██╔══██╗██║████╗  ██║██╔════╝ 
██║  ███╗█████╗  ██████╔╝███████╗██████╔╝██║██╔██╗ ██║██║  ███╗
██║   ██║██╔══╝  ██╔══██╗╚════██║██╔═══╝ ██║██║╚██╗██║██║   ██║
╚██████╔╝███████╗██║  ██║███████║██║     ██║██║ ╚████║╚██████╔╝
 ╚═════╝ ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝ 
EOF
    echo -e "${endColour}"
    echo -e "${purpleColour}=== System Hardening & Setup Suite ===${endColour}"
    echo -e "${grayColour}OS Family: ${endColour}${cyanColour}${1:-Unknown}${endColour} | ${grayColour}Package Manager: ${endColour}${cyanColour}${2:-Unknown}${endColour}"
    print_separator
}

create_initial_backup() {
    if [[ -s "$BACKUP_ARCHIVE" ]]; then
        return 0
    fi

    ## Remove the file if it is corrupted with 0 bytes size.
    [[ -f "$BACKUP_ARCHIVE" ]] && rm -f "$BACKUP_ARCHIVE"
   
    msg_info "First execution detected. Creating initial system backup..."
    mkdir -p "$BACKUP_DIR"

    local paths_to_backup=(
        "/etc/ssh"
        "/etc/fstab"
        "/etc/login.defs"
        "/etc/sysctl.conf"
        "/etc/sysctl.d"
        "/etc/default/grub"
        "/etc/fail2ban"
        "/etc/usbguard"
        "/etc/apt/apt.conf.d"
    )

    local existing_paths=()

    for path in "${paths_to_backup[@]}"; do
        if [[ -e "$path" ]]; then
            existing_paths+=("$path")
        fi
    done

    if [[ ${#existing_paths[@]} -gt 0 ]]; then
        tar -czf "$BACKUP_ARCHIVE" "${existing_paths[@]}" 2>/dev/null || true
        msg_success "Initial pre-hardening backup saved to: $BACKUP_ARCHIVE"
    else
        msg_warn "No standard configuration paths found to back up."
    fi

    print_separator
    read -rp "Press [ENTER] to continue to menu..."
}

restore_backup() {
    if [[ ! -f "$BACKUP_ARCHIVE" ]]; then
        msg_error "No initial backup found at $BACKUP_ARCHIVE."
        return 1
    fi

    print_separator
    msg_warn "RESTORE INITIAL CONFIGURATION"
    msg_warn "This will overwrite current SSH, Firewall, Umask, Sysctl, and system settings"
    msg_warn "with the initial state saved on the first execution."
    print_separator

    read -rp "Are you SURE you want to restore initial configurations? [y/N]: " confirm_restore
    
    if [[ ! "$confirm_restore" =~ ^[Yy]$ ]]; then
        msg_info "Restore operation cancelled by user."
        return 0
    fi

    msg_info "1/6 Restoring configuration files from initial backup archive..."
    tar -xzf "$BACKUP_ARCHIVE" -C / 2>/dev/null || true

    msg_info "2/6 Stopping and disabling services enabled during hardening..."
   
    local services_to_disable=(
        "usbguard"
        "fail2ban"
        "chrony"
        "chronyd"
        "unattended-upgrades"
    )

    for svc in "${services_to_disable[@]}"; do
        if systemctl list-unit-files "$svc.service" 2>/dev/null | grep -q "^$svc\.service"; then
            systemctl disable --now "$svc" &>/dev/null || true
            msg_info "Stopped and disabled service: $svc"
        fi
    done

    if command -v ufw &>/dev/null; then
        msg_info "Disabling UFW firewall..."
        ufw disable &>/dev/null || true
    fi

    msg_info "3/6 Re-enabling standard background services..."
   
    local services_to_enable=(
        "bluetooth.service"
        "cups.service"
        "cups-browsed.service"
        "avahi-daemon.service"
        "ModemManager.service"
        "apport.service"
        "whoopsie.service"
        "speech-dispatcher.service"
        "geoclue.service"
        "rpcbind.service"
        "rpcbind.socket"
    )

    for svc in "${services_to_enable[@]}"; do
        if systemctl list-unit-files "$svc" 2>/dev/null | grep -q "^$svc"; then
            systemctl enable "$svc" &>/dev/null || true
            msg_info "Re-enabled unit: $svc"
        fi
    done

    msg_info "4/6 Removing custom drop-in profiles and configuration files..."
    rm -f /etc/profile.d/umask.sh 2>/dev/null || true
    rm -f /etc/ssh/sshd_config.d/99-hardening.conf 2>/dev/null || true
    rm -f /etc/fail2ban/jail.local /etc/fail2ban/jail.d/ssh.local 2>/dev/null || true
    rm -f /etc/usbguard/rules.conf 2>/dev/null || true

    if [[ -n "${SYSCTL_DIR:-}" && -n "${KERNEL_NETWORK_HARDENING_CONF:-}" ]]; then
        local conf_filename="${KERNEL_NETWORK_HARDENING_CONF##*/}"
        rm -f "${SYSCTL_DIR}/${conf_filename}" 2>/dev/null || true
    fi

    # 5. Restablecer /dev/shm a las opciones por defecto
    msg_info "5/6 Resetting mount permissions for /dev/shm..."
    if mountpoint -q /dev/shm; then
        mount -o remount,defaults /dev/shm 2>/dev/null || true
    fi

    msg_info "6/6 Reloading sysctl parameters and bootloader..."
    sysctl --system &>/dev/null || true

    if [[ -f /etc/default/grub ]]; then
        if command -v update-grub &>/dev/null; then
            update-grub &>/dev/null || true
        elif command -v grub-mkconfig &>/dev/null; then
            grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null || true
        fi
    fi

    local ssh_service="sshd"
    if systemctl list-unit-files | grep -q "^ssh\.service"; then
        ssh_service="ssh"
    fi

    msg_info "Reloading SSH daemon..."
    systemctl reload "$ssh_service" 2>/dev/null || systemctl restart "$ssh_service" 2>/dev/null || true

    msg_success "Initial system configurations and service states restored successfully."
    msg_warn "A system reboot is strongly recommended to apply all reverted parameters."
}

update_system() {
    local package_manager="$1"

    msg_info "Starting system maintenance using $package_manager..."

    case "$package_manager" in
        apt)
            msg_info "Updating repository lists and upgrading packages..."
            print_separator
            apt update && apt upgrade -y

            msg_info "Removing unnecessary packages and clearing cache..."
            print_separator
            apt autoremove --purge -y && apt autoclean
            ;;
        pacman)
            msg_info "Synchronizing repositories and upgrading system..."
            print_separator
            pacman -Syu --noconfirm

            msg_info "Cleaning up orphaned packages..."
            print_separator

            if pacman -Qtdq &>/dev/null; then
                pacman -Rns $(pacman -Qtdq) --noconfirm
            else
                msg_info "No orphaned packages found to remove."
            fi

            msg_info "Clearing package cache..."
            pacman -Sc --noconfirm
            ;;
    esac

    msg_success "System update and cleanup completed successfully."
}

install_essentials() {
    local package_manager="$1"

    msg_info "Installing expanded essential CLI & diagnostics suite..."

    case "$package_manager" in
        apt)
            apt update -qq
            apt install -y \
                curl wget git unzip zip tar psmisc \
                htop iotop btop \
                net-tools dnsutils iproute2 ufw \
                tmux screen tree jq ripgrep eza \
                build-essential software-properties-common ca-certificates \
                rsync rclone gnupg
            ;;
        pacman)
            pacman -S --needed --noconfirm \
                curl wget git unzip zip tar psmisc \
                htop iotop btop \
                net-tools bind iproute2 ufw \
                tmux screen tree jq ripgrep eza \
                base-devel ca-certificates \
                rsync rclone gnupg
            ;;
        *)
            msg_error "Unsupported package manager for essential tools."
            return 1
            ;;
    esac

    msg_success "Essential utilities installed successfully."
}

apply_before_ufw_rules() {
    msg_info "Configuring ufw advanced rules in ${UFW_BEFORE_RULES}..."

    if [[ ! -f "$UFW_BEFORE_RULES" ]]; then
        msg_error "File ${UFW_BEFORE_RULES} not found."
        return 1
    fi

    # Backup original before.rules if not already backed up
    if [[ ! -f "${UFW_BEFORE_RULES}.bak" ]]; then
        cp "$UFW_BEFORE_RULES" "${UFW_BEFORE_RULES}.bak"
        msg_info "Backup created at ${UFW_BEFORE_RULES}.bak"
    fi

    # Check if custom rules are already injected
    if grep -q "ctstate INVALID" "$UFW_BEFORE_RULES"; then
        msg_warn "Custom INVALID/ICMP rate-limiting rules already present. Skipping modification."
        return 0
    fi

    # Comment out default unrestricted echo-request rule if present
    sed -i 's/^-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/# &-disabled_by_script/' "$BEFORE_RULES"

    # Inject custom rules before the final COMMIT statement of the *filter block
    local snippet="
# --- CUSTOM HARDENING RULES ---
# Drop INVALID state packets (malformed packets / port scans)
-A ufw-before-input -m conntrack --ctstate INVALID -j DROP

# Rate-limit ICMP Pings (max 3/s with burst of 5)
-A ufw-before-input -p icmp --icmp-type echo-request -m limit --limit 3/s --limit-burst 5 -j ACCEPT
-A ufw-before-input -p icmp --icmp-type echo-request -j DROP
"

    # Insert snippet right before the COMMIT line
    sed -i "/^COMMIT/i $snippet" "$UFW_BEFORE_RULES"

    msg_info "Successfully injected INVALID packet drop and ICMP rate-limiting rules."
}

apply_ufw_rules() {
    if [[ -f "${UFW_RULES:-}" ]]; then
        apply_before_ufw_rules

        msg_info "Applying UFW firewall rules..."
        source "$UFW_RULES"

        if [[ ! -f "${KERNEL_NETWORK_HARDENING_CONF:-}" ]]; then
            msg_warn "Kernel network hardening configuration file not found at: ${KERNEL_NETWORK_HARDENING_CONF:-}"
            return 0
        fi

        msg_info "Applying kernel network hardening configuration..."
        mkdir -p "$SYSCTL_DIR"

        local conf_filename="${KERNEL_NETWORK_HARDENING_CONF##*/}"

        cp "$KERNEL_NETWORK_HARDENING_CONF" "$SYSCTL_DIR"
        chmod 644 "$SYSCTL_DIR/$conf_filename"

        msg_success "Copied $conf_filename to $SYSCTL_DIR (644)."
        print_separator
        msg_info "Reloading sysctl network parameters..."

        if sysctl --system &>/dev/null; then
            msg_success "Sysctl kernel settings reloaded successfully."
        else
            msg_warn "Sysctl reloaded with non-fatal warnings."
        fi
    else
        msg_warn "File UFW_RULES not found at path: ${UFW_RULES:-}"
    fi
}

setup_unattended_upgrades() {
    local os_distro="$1"
    local auto_upgrades_configuration_file="$CURRENT_DIR/debian/20auto-upgrades"

    if [[ "$os_distro" != "debian" ]]; then
        msg_warn "Unattended-upgrades is only supported on Debian/Ubuntu based systems. Skipping..."
        return 0
    fi

    if [[ ! -d "${APT_CONF_DIR:-}" ]]; then
        msg_error "APT configuration directory not found: ${APT_CONF_DIR:-}"
        return 1
    fi

    msg_info "Setting up automatic unattended security upgrades..."

    apt update -qq && apt install -y unattended-upgrades apt-listchanges

    if [[ -f "$auto_upgrades_configuration_file" ]]; then
        local filename="${auto_upgrades_configuration_file##*/}"
        cp "$auto_upgrades_configuration_file" "$APT_CONF_DIR"
        chmod 644 "$APT_CONF_DIR/$filename"
        msg_success "Applied unattended upgrades configuration file ($filename)."
    fi

    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive unattended-upgrades
    systemctl enable --now unattended-upgrades

    msg_success "Unattended upgrades configured and service enabled successfully."
}

setup_fail2ban() {
    local package_manager="$1"
    local fail2ban_target_dir="/etc/fail2ban"

    case "$package_manager" in
        apt)
            msg_info "Installing Fail2ban via APT..."
            apt update -qq && apt install -y fail2ban
            ;;
        pacman)
            msg_info "Installing Fail2ban via Pacman..."
            pacman -S --needed --noconfirm fail2ban
            ;;
        *)
            msg_error "Could not install Fail2ban: unsupported package manager '$package_manager'."
            return 1
            ;;
    esac

    msg_info "Deploying custom Fail2ban jail configurations..."
    mkdir -p "${fail2ban_target_dir}/jail.d"

    if [[ -f "${FAIL2BAN_CONF_DIR}/jail.local" ]]; then
        cp "${FAIL2BAN_CONF_DIR}/jail.local" "${fail2ban_target_dir}/jail.local"
        chmod 644 "${fail2ban_target_dir}/jail.local"
        msg_success "Deployed jail.local to ${fail2ban_target_dir}/jail.local (644)."
    else
        msg_warn "Source file ${FAIL2BAN_CONF_DIR}/jail.local not found."
    fi

    if [[ -f "${FAIL2BAN_CONF_DIR}/ssh.local" ]]; then
        cp "${FAIL2BAN_CONF_DIR}/ssh.local" "${fail2ban_target_dir}/jail.d/ssh.local"
        chmod 644 "${fail2ban_target_dir}/jail.d/ssh.local"
        msg_success "Deployed ssh.local to ${fail2ban_target_dir}/jail.d/ssh.local (644)."
    else
        msg_warn "Source file ${FAIL2BAN_CONF_DIR}/ssh.local not found."
    fi

    msg_info "Enabling and starting Fail2ban service..."
    systemctl enable --now fail2ban
    systemctl restart fail2ban

    msg_success "Fail2ban setup completed successfully."
}

apply_hardware_hardening() {
    local package_manager="$1"

    if [[ -f "${HARDWARE_HARDENING_RULES:-}" ]]; then
        msg_info "Applying process limits, memory protection, and kernel hardening..."
        source "$HARDWARE_HARDENING_RULES"
        apply_process_memory_hardening "$package_manager"
    else
        msg_warn "Hardware hardening script not found at: ${HARDWARE_HARDENING_RULES:-}"
    fi
}

select_timezone() {
    msg_info "Configuring system timezone..."

    if ! command -v timedatectl &>/dev/null; then
        msg_warn "timedatectl is not available. Skipping timezone configuration."
        return 0
    fi

    echo ""
    echo "=========================================="
    echo "           TIMEZONE SELECTION             "
    echo "=========================================="

    local regions=("Africa" "America" "Asia" "Atlantic" "Australia" "Europe" "Indian" "Pacific" "UTC" "Skip")
    local selected_region=""

    PS3="Select a region [1-${#regions[@]}]: "
    select reg in "${regions[@]}"; do
        if [[ -n "${reg:-}" ]]; then
            if [[ "$reg" == "Skip" ]]; then
                msg_info "Timezone selection skipped by user."
                return 0
            fi
            if [[ "$reg" == "UTC" ]]; then
                selected_region="UTC"
                break
            fi
            selected_region="$reg"
            break
        else
            msg_warn "Invalid option. Please select a valid number."
        fi
    done

    local selected_tz=""
    if [[ "$selected_region" == "UTC" ]]; then
        selected_tz="UTC"
    else
        echo ""
        msg_info "Loading timezones for region: $selected_region..."

        mapfile -t tzs < <(timedatectl list-timezones | grep "^${selected_region}/")
        tzs+=("Cancel")

        PS3="Select a timezone [1-${#tzs[@]}]: "
        select tz in "${tzs[@]}"; do
            if [[ -n "${tz:-}" ]]; then
                if [[ "$tz" == "Cancel" ]]; then
                    msg_info "Timezone selection cancelled."
                    return 0
                fi
                selected_tz="$tz"
                break
            else
                msg_warn "Invalid option. Please select a valid number."
            fi
        done
    fi

    if [[ -n "$selected_tz" ]]; then
        timedatectl set-timezone "$selected_tz"
        msg_success "System timezone updated to: $selected_tz"
    fi
}

setup_chrony() {
    local package_manager="$1"
    local service_name=""

    msg_info "Setting up Chrony time synchronization daemon..."

    case "$package_manager" in
        apt)
            apt update -qq && apt install -y chrony
            service_name="chrony"
            ;;
        pacman)
            pacman -S --needed --noconfirm chrony
            service_name="chronyd"
            ;;
        *)
            msg_error "Could not install Chrony: unsupported package manager '$package_manager'."
            return 1
            ;;
    esac

    select_timezone

    msg_info "Enabling and starting Chrony service ($service_name)..."
    systemctl enable --now "$service_name"
    timedatectl set-ntp true 2>/dev/null || true

    msg_success "Chrony time synchronization configured successfully."
}

setup_apparmor() {
    local package_manager="$1"

    msg_info "Setting up and hardening AppArmor Mandatory Access Control..."

    case "$package_manager" in
        apt)
            msg_info "Installing AppArmor core, utilities, and extended profiles via APT..."
            apt update -qq
            apt install -y apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra
            ;;
        pacman)
            msg_info "Installing AppArmor via Pacman..."
            pacman -S --needed --noconfirm apparmor
            ;;
        *)
            msg_error "Could not setup AppArmor: unsupported package manager '$package_manager'."
            return 1
            ;;
    esac

    local parser_conf="/etc/apparmor/parser.conf"

    if [[ -f "$parser_conf" ]]; then
        if ! grep -qs "^write-cache" "$parser_conf"; then
            echo "write-cache" >> "$parser_conf"
            msg_info "Enabled binary profile caching in $parser_conf."
        fi
        if ! grep -qs "^optimize=compress-fast" "$parser_conf"; then
            echo "optimize=compress-fast" >> "$parser_conf"
        fi
    fi

    msg_info "Enabling and starting AppArmor systemd service..."
    systemctl enable --now apparmor

    local aa_active=false
    if [[ -f /sys/module/apparmor/parameters/enabled ]]; then
        if [[ $(cat /sys/module/apparmor/parameters/enabled) == "Y" ]]; then
            aa_active=true
        fi
    fi

    if [[ "$aa_active" == true ]]; then
        msg_success "AppArmor kernel module is active."
    else
        msg_warn "AppArmor is NOT active in the running kernel."

        if [[ -f /etc/default/grub ]]; then
            msg_info "GRUB configuration detected at /etc/default/grub. Checking boot parameters..."

            if ! grep -q "apparmor=1" /etc/default/grub; then
                msg_info "Adding AppArmor parameters to GRUB_CMDLINE_LINUX_DEFAULT..."

                cp /etc/default/grub /etc/default/grub.bak.$(date +%F_%T)

                sed -i -E 's/GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 apparmor=1 lsm=landlock,lockdown,yama,integrity,apparmor"/' /etc/default/grub

                msg_info "Updating GRUB configuration..."
                if command -v update-grub &>/dev/null; then
                    update-grub
                elif command -v grub-mkconfig &>/dev/null; then
                    grub-mkconfig -o /boot/grub/grub.cfg
                fi

                msg_warn "GRUB updated. A SYSTEM REBOOT IS REQUIRED to activate AppArmor in the kernel."
            else
                msg_info "AppArmor parameters already present in /etc/default/grub. Pending reboot."
            fi

        elif command -v bootctl &>/dev/null && bootctl status &>/dev/null; then
            msg_warn "systemd-boot detected. Please add options manually to your boot entry."
        else
            msg_warn "Manual intervention required for bootloader kernel options."
        fi
    fi

    if command -v aa-enforce &>/dev/null; then
        msg_info "Setting all profiles in /etc/apparmor.d/ to enforce mode..."
        aa-enforce /etc/apparmor.d/* 2>/dev/null || true
        msg_success "AppArmor profiles set to enforce mode."
    fi

    if command -v aa-status &>/dev/null; then
        print_separator
        msg_info "Current AppArmor Status Summary:"
        aa-status --short 2>/dev/null || aa-status 2>/dev/null | head -n 10
    fi

    msg_success "AppArmor configuration completed successfully."
}

setup_ssh_hardening() {
    local package_manager="$1"
    local main_sshd_conf="/etc/ssh/sshd_config"
    local sshd_conf_dir="/etc/ssh/sshd_config.d"
    local hardening_file="${sshd_conf_dir}/99-hardening.conf"

    msg_info "Verifying OpenSSH server installation..."

    case "$package_manager" in
        apt)
            if ! dpkg -l | grep -q "^ii  openssh-server"; then
                msg_info "Installing openssh-server via APT..."
                apt update -qq && apt install -y openssh-server
            fi
            ;;
        pacman)
            if ! pacman -Qs "^openssh$" &>/dev/null; then
                msg_info "Installing openssh via Pacman..."
                pacman -S --needed --noconfirm openssh
            fi
            ;;
        *)
            msg_error "Could not setup SSH: unsupported package manager '$package_manager'."
            return 1
            ;;
    esac

    if [[ ! -f "$main_sshd_conf" ]]; then
        msg_error "Main SSH configuration file ($main_sshd_conf) not found."
        return 1
    fi

    mkdir -p "$sshd_conf_dir"
    if ! grep -qs "^Include /etc/ssh/sshd_config.d/\*\.conf" "$main_sshd_conf"; then
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$main_sshd_conf"
    fi

    msg_info "Deploying hardened SSH profile to $hardening_file..."
    cat << 'EOF' > "$hardening_file"
# Security Hardening - Production Profile
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
X11Forwarding no
AllowAgentForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    chmod 600 "$hardening_file"

    msg_info "Validating SSH daemon configuration syntax..."
    ssh-keygen -A &>/dev/null
    mkdir -p /run/sshd

    # Disable active X11Forwarding in the main file to satisfy static security scanners
    if grep -qs -i "^[[:space:]]*X11Forwarding[[:space:]]\+yes" "$main_sshd_conf"; then
        msg_info "Commenting out legacy X11Forwarding in $main_sshd_conf to prevent static audit false positives..."
        sed -i -E 's/^([[:space:]]*X11Forwarding[[:space:]]+yes)/# \1 # Disabled by hardening suite/gi' "$main_sshd_conf"
    fi

    if sshd -t; then
        msg_success "SSH configuration syntax is valid."

        local ssh_service="sshd"
        if systemctl list-unit-files | grep -q "^ssh\.service"; then
            ssh_service="ssh"
        fi

        msg_info "Enabling and reloading $ssh_service service..."
        systemctl enable "$ssh_service" &>/dev/null
        
        if systemctl reload "$ssh_service" &>/dev/null || systemctl restart "$ssh_service" &>/dev/null; then
            msg_success "SSH daemon successfully reloaded with hardened rules."
        else
            msg_error "Failed to reload or restart $ssh_service service."
            return 1
        fi
    else
        msg_error "SSH configuration validation failed. Removing deployed rules..."
        rm -f "$hardening_file"
        return 1
    fi
}

disable_unused_services() {
    msg_info "Disabling unnecessary background services for server environments..."

    local services=(
        "bluetooth.service"
        "cups.service"
        "cups-browsed.service"
        "avahi-daemon.service"
        "ModemManager.service"
        "apport.service"
        "whoopsie.service"
        "speech-dispatcher.service"
        "geoclue.service"
    )

    local disabled_count=0

    for svc in "${services[@]}"; do
        if systemctl list-unit-files "$svc" 2>/dev/null | grep -q "^$svc"; then
            if systemctl is-enabled --quiet "$svc" 2>/dev/null || systemctl is-active --quiet "$svc" 2>/dev/null; then
                msg_info "Disabling and stopping $svc..."
                systemctl disable --now "$svc" &>/dev/null || true
                msg_success "Disabled: $svc"
                ((++disabled_count))
            else
                msg_info "Service $svc is already disabled or inactive."
            fi
        fi
    done

    if systemctl list-unit-files "rpcbind.service" 2>/dev/null | grep -q "^rpcbind.service"; then
        if ! systemctl is-active --quiet nfs-server 2>/dev/null && ! grep -qs "nfs" /proc/mounts; then
            if systemctl is-enabled --quiet rpcbind.service 2>/dev/null || systemctl is-active --quiet rpcbind.service 2>/dev/null; then
                msg_info "Disabling rpcbind.service (NFS not in use)..."
                systemctl disable --now rpcbind.service rpcbind.socket &>/dev/null || true
                msg_success "Disabled: rpcbind.service & rpcbind.socket"
                ((++disabled_count))
            fi
        fi
    fi

    if [[ $disabled_count -eq 0 ]]; then
        msg_info "No active unnecessary services needed disabling."
    else
        msg_success "Successfully disabled $disabled_count unnecessary services."
    fi
}

# --- PASO 3: Opciones de montaje seguras (nodev, nosuid, noexec) ---
setup_secure_mounts() {
    msg_info "Applying secure mount options (nodev, nosuid, noexec) to /dev/shm..."

    # Aplicar montaje en caliente si /dev/shm está montado
    if mountpoint -q /dev/shm; then
        mount -o remount,nodev,nosuid,noexec /dev/shm 2>/dev/null || true
        msg_info "Remounted /dev/shm with nodev,nosuid,noexec."
    fi

    # Asegurar persistencia en /etc/fstab
    if ! grep -qs "/dev/shm" /etc/fstab; then
        msg_info "Adding persistent /dev/shm security entry to /etc/fstab..."
        echo "tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec 0 0" >> /etc/fstab
    fi

    msg_success "Secure mount options applied successfully to /dev/shm."
}

setup_umask() {
    msg_info "Configuring default system-wide umask to 027 (restrictive read/write)..."

    if [[ -f /etc/login.defs ]]; then
        sed -i -E 's/^UMASK\s+[0-9]+/UMASK 027/' /etc/login.defs
        msg_info "Updated UMASK to 027 in /etc/login.defs."
    fi

    mkdir -p /etc/profile.d
    cat << 'EOF' > /etc/profile.d/umask.sh
# Set restrictive default umask for users (027)
umask 027
EOF
    chmod 644 /etc/profile.d/umask.sh

    msg_success "Global umask 027 applied to /etc/profile.d/umask.sh."
}

setup_usbguard() {
    local package_manager="$1"

    msg_info "Evaluating environment type for USBGuard deployment..."

    # Validación adicional: Confirmar si es un sistema tipo servidor
    if ! is_server_environment; then
        print_separator
        msg_warn "DESKTOP ENVIRONMENT DETECTED!"
        msg_warn "USBGuard enforces a strict whitelist policy."
        msg_warn "On desktops, plugging in new USB drives, keyboards, or mice WILL BE BLOCKED by default."
        print_separator
        read -e -i "N" -rp "Do you still want to proceed with USBGuard on this desktop system? [y/N]: " confirm_desktop
        
        confirm_desktop="${confirm_desktop:-N}"
        
        if [[ ! "$confirm_desktop" =~ ^[Yy]$ ]]; then
            msg_info "USBGuard installation skipped by user for desktop environment."
            return 0
        fi
    else
        msg_info "Server/headless environment verified. Proceeding with USBGuard deployment..."
    fi

    case "$package_manager" in
        apt)
            apt update -qq && apt install -y usbguard
            ;;
        pacman)
            pacman -S --needed --noconfirm usbguard
            ;;
        *)
            msg_error "Could not install USBGuard: unsupported package manager '$package_manager'."
            return 1
            ;;
    esac

    msg_info "Generating initial policy based on currently connected USB devices..."
    usbguard generate-policy > /etc/usbguard/rules.conf 2>/dev/null || true
    chmod 600 /etc/usbguard/rules.conf

    msg_info "Enabling and starting USBGuard service..."
    systemctl enable --now usbguard

    msg_success "USBGuard configured and active."
}

install_antivirus() {
    local package_manager="$1"

    if [[ -f "${ANTIVIRUS_SETUP:-}" ]]; then
        msg_info "Loading antivirus module..."
        if source "$ANTIVIRUS_SETUP"; then
            setup_threat_protection "$package_manager"
        else
            msg_error "Failed to source antivirus setup script at: $ANTIVIRUS_SETUP"
            return 1
        fi
    else
        msg_warn "Antivirus installation script not found at: ${ANTIVIRUS_SETUP:-}"
    fi
}

run_all_tasks() {
    local package_manager="$1"
    local os_distribution="$2"

    update_system "$package_manager" || msg_warn "System update finished with warnings."
    print_separator

    install_essentials "$package_manager" || msg_warn "Essential tools installation encountered issues."
    print_separator

    setup_chrony "$package_manager" || msg_warn "Chrony setup encountered issues."
    print_separator

    setup_unattended_upgrades "$os_distribution" || msg_warn "Unattended upgrades setup skipped or failed."
    print_separator

    setup_fail2ban "$package_manager" || msg_warn "Fail2ban setup encountered issues."
    print_separator

    apply_ufw_rules || msg_warn "UFW / sysctl rules application skipped or failed."
    print_separator

    apply_hardware_hardening "$package_manager" || msg_warn "Hardware hardening skipped or failed."
    print_separator

    setup_secure_mounts || msg_warn "Secure mounts configuration encountered issues."
    print_separator

    setup_umask || msg_warn "Umask adjustment encountered issues."
    print_separator

    setup_ssh_hardening "$package_manager" || msg_warn "SSH hardening failed or was reverted."
    print_separator

    disable_unused_services || msg_warn "Unused services task completed with warnings."
    print_separator

    setup_apparmor "$package_manager" || msg_warn "AppArmor setup completed with warnings."
    print_separator

    setup_usbguard "$package_manager" || msg_warn "USBGuard setup encountered issues."
    print_separator

    install_antivirus "$package_manager" || msg_warn "Antivirus installation encountered issues."   
    print_separator

    msg_success "Full deployment pipeline completed successfully."
}

show_interactive_menu() {
    local package_manager="$1"
    local os_distribution="$2"

    while true; do
        clear
        print_banner "$os_distribution" "$package_manager"

        echo -e "${yellowColour}[MODULE SELECTION MENU]${endColour}"
        echo -e " 1) ${greenColour}Full Deployment      -> Execute all configuration modules sequentially${endColour}"
        echo -e " 2) ${cyanColour}System Update${endColour}        -> Repositories synchronization, full-upgrade & cache cleanup"
        echo -e " 3) ${cyanColour}Essential Tools${endColour}      -> CLI diagnostics (btop, htop, iotop, jq, ripgrep, eza, etc.)"
        echo -e " 4) ${cyanColour}Time Sync & TZ${endColour}       -> Chrony NTP daemon setup & interactive timezone selection"
        echo -e " 5) ${cyanColour}Auto-Upgrades${endColour}        -> Unattended security updates (Debian/Ubuntu only)"
        echo -e " 6) ${cyanColour}Fail2ban Service${endColour}     -> Bruteforce protection & custom SSH jail policies"
        echo -e " 7) ${cyanColour}UFW & Sysctl Net${endColour}     -> Firewall rules application & Network kernel hardening"
        echo -e " 8) ${cyanColour}Hardware & Memory${endColour}    -> Limits, coredumps, dmesg restriction, swappiness & /dev/shm"
        echo -e " 9) ${cyanColour}Secure Mounts${endColour}        -> Apply nodev,nosuid,noexec flags to /dev/shm & fstab"
        echo -e "10) ${cyanColour}Default Umask${endColour}        -> Restrictive file creation permissions (umask 027)"
        echo -e "11) ${cyanColour}USBGuard Service${endColour}     -> BadUSB protection ${redColour}[⚠️  WARN: May block new USBs]${endColour}"        
        echo -e "12) ${cyanColour}SSH Hardening${endColour}        -> Disable root login, password auth & enforce key-based access"
        echo -e "13) ${cyanColour}Unused Services${endColour}      -> Disable Bluetooth, CUPS, Avahi-daemon & ModemManager"
        echo -e "14) ${cyanColour}AppArmor MAC${endColour}         -> Mandatory Access Control setup, caching & profile enforcement"        
        echo -e "15) ${cyanColour}Threat Surface Protection${endColour} -> Prepare ClamAV, Lynis auditor, chkrootkit & ClamUI"        
       
       if [[ -f "$BACKUP_ARCHIVE" ]]; then
            echo -e "16) ${purpleColour}Restore Backup${endColour}       -> ${greenColour}[Backup Available]${endColour} Revert system to initial state"
        else
            echo -e "16) ${purpleColour}Restore Backup${endColour}       -> ${grayColour}[No Backup Found]${endColour} Revert system to initial state"
        fi

        echo -e "17) ${redColour}Exit${endColour}                 -> Terminate execution"
        print_separator

        read -rp "Select an option [1-17]: " choice

        print_separator
        case "$choice" in
            1)
                run_all_tasks "$package_manager" "$os_distribution"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            2)
                update_system "$package_manager"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            3)
                install_essentials "$package_manager"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            4)
                setup_chrony "$package_manager"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            5)
                setup_unattended_upgrades "$os_distribution"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            6)
                setup_fail2ban "$package_manager"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            7)
                apply_ufw_rules
                read -rp "Press [ENTER] to return to menu..."
                ;;
            8)
                apply_hardware_hardening "$package_manager"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            9)
                setup_secure_mounts
                read -rp "Press [ENTER] to return to menu..."
                ;;
            10)
                setup_umask
                read -rp "Press [ENTER] to return to menu..."
                ;;
            11)
                setup_usbguard "$package_manager"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            12)
                setup_ssh_hardening "$package_manager"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            13)
                disable_unused_services
                read -rp "Press [ENTER] to return to menu..."
                ;;
            14)
                setup_apparmor "$package_manager"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            15)
                install_antivirus "$package_manager"
                read -rp "Press [ENTER] to return to menu..."
                ;;
            16)
                restore_backup
                read -rp "Press [ENTER] to return to menu..."
                ;;
            17)
                msg_info "Exiting setup suite."
                exit 0
                ;;
            *)
                msg_warn "Invalid option '$choice'. Please try again."
                sleep 1.5
                ;;
        esac
    done
}

main() {
    if [[ $(uname -s) != "Linux" ]]; then
        msg_error "This script is only compatible with Linux distributions."
        exit 1
    fi

    if [[ $EUID -ne 0 ]]; then
        msg_warn "Root privileges required. Re-running with sudo..."
        exec sudo "$0" "$@"
    fi

    local package_manager
    package_manager=$(detect_package_manager) || exit 1

    local os_distribution
    os_distribution=$(detect_distribution) || exit 1

    create_initial_backup
    show_interactive_menu "$package_manager" "$os_distribution"

}

main "$@"