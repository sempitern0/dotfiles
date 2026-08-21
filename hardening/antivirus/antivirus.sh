#!/usr/bin/env bash
set -euo pipefail

setup_clamav_cli() {
    local package_manager="$1"

    msg_info "Installing and configuring ClamAV Antivirus Daemon & Freshclam..."

    # Install required packages based on the detected package manager
    case "$package_manager" in
        apt)
            apt update -qq
            apt install -y clamav clamav-freshclam clamav-daemon
            ;;
        pacman)
            pacman -S --needed --noconfirm clamav
            ;;
        *)
            msg_error "Unsupported package manager '$package_manager' for ClamAV."
            return 1
            ;;
    esac

    # Temporarily stop the freshclam daemon to release the database lock file
    msg_info "Stopping freshclam service for initial database signature update..."
    systemctl stop clamav-freshclam &>/dev/null || systemctl stop freshclam &>/dev/null || true

    # Download initial virus signature database
    msg_info "Updating virus signature database with freshclam..."
    freshclam || msg_warn "Freshclam finished with warnings (database may already be up to date)."

    # Enable and start background services depending on OS family
    msg_info "Enabling and starting ClamAV daemon and update services..."
    
    if [[ "$package_manager" == "apt" ]]; then
        systemctl enable --now clamav-freshclam &>/dev/null || true
        systemctl enable --now clamav-daemon &>/dev/null || true
    elif [[ "$package_manager" == "pacman" ]]; then
        systemctl enable --now freshclam &>/dev/null || true
        systemctl enable --now clamd &>/dev/null || true
    fi

    # Verify daemon execution status
    local daemon_svc="clamav-daemon"

    [[ "$package_manager" == "pacman" ]] && daemon_svc="clamd"

    if systemctl is-active --quiet "$daemon_svc"; then
        msg_success "ClamAV daemon ($daemon_svc) is active and running."
    else
        msg_warn "ClamAV daemon ($daemon_svc) was enabled but failed to confirm active status."
    fi
}

setup_clamui() {
    local package_manager="$1"
    local github_repo="linx-systems/clamui" 
    local temp_dir="/tmp/clamui_installer"

    msg_info "Setting up ClamUI graphical interface from GitHub Releases..."

    mkdir -p "$temp_dir"

    case "$package_manager" in
        apt)
            msg_info "Fetching latest ClamUI .deb release URL from GitHub API..."
            local deb_url
            deb_url=$(curl -s "https://api.github.com/repos/${github_repo}/releases/latest" | \
                      jq -r '.assets[] | select(.name | endswith(".deb")) | .browser_download_url' | head -n 1)

            if [[ -z "$deb_url" || "$deb_url" == "null" ]]; then
                msg_error "Failed to retrieve .deb release URL from GitHub API."
                rm -rf "$temp_dir"
                return 1
            fi

            msg_info "Downloading ClamUI package from: $deb_url"
            curl -sSL "$deb_url" -o "${temp_dir}/clamui_latest.deb"

            msg_info "Installing ClamUI via APT..."
            apt install -y "${temp_dir}/clamui_latest.deb"
            ;;

        pacman)
            msg_info "Checking installation methods for Arch Linux..."
            
            # Arch Linux does not natively install .deb files. 
            # Option 1: Install from AUR if an AUR helper (yay/paru) is present.
            if command -v yay &>/dev/null; then
                msg_info "Installing clamui via yay (AUR)..."
                sudo -u "${SUDO_USER:-$USER}" yay -S --noconfirm clamui-git || true
            elif command -v paru &>/dev/null; then
                msg_info "Installing clamui via paru (AUR)..."
                sudo -u "${SUDO_USER:-$USER}" paru -S --noconfirm clamui-git || true
            else
                # Option 2: Fallback to debtap or manual extraction if no AUR helper is installed
                msg_warn "No AUR helper (yay/paru) found on Arch Linux."
                msg_info "To install on Arch manually, build from AUR (clamui) or install yay/paru."
            fi
            ;;

        *)
            msg_error "Unsupported package manager '$package_manager' for ClamUI."
            rm -rf "$temp_dir"
            return 1
            ;;
    esac

    rm -rf "$temp_dir"
    msg_success "ClamUI setup procedure finished."
}

setup_clamav() {
    local package_manager="$1"

    setup_clamav_cli "$package_manager"

    if ! is_server_environment; then
        setup_clamui "$package_manager"
    else
        msg_info "Headless server environment detected. Skipping ClamUI (GUI) installation."
    fi
}

setup_lynis() {
    local package_manager="$1"

    msg_info "Installing Lynis system auditing & security tool..."

    case "$package_manager" in
        apt)
            apt update -qq
            apt install -y lynis
            ;;
        pacman)
            pacman -S --needed --noconfirm lynis
            ;;
        *)
            msg_error "Unsupported package manager '$package_manager' for Lynis."
            return 1
            ;;
    esac

    # Configure daily automated audit cron job for continuous security monitoring
    msg_info "Configuring daily automated Lynis security audits..."
    mkdir -p /etc/cron.daily

    cat << 'EOF' > /etc/cron.daily/lynis-audit
#!/usr/bin/env bash
/usr/bin/lynis audit system --quick --cronjob > /var/log/lynis-cron.log 2>&1
EOF
    chmod 700 /etc/cron.daily/lynis-audit

    msg_success "Lynis installed and daily audit cron job (/etc/cron.daily/lynis-audit)."
}

setup_chkrootkit() {
    local package_manager="$1"

    msg_info "Installing Chkrootkit rootkit detection tool..."

    case "$package_manager" in
        apt)
            apt update -qq
            apt install -y chkrootkit

            # Harden Debian/Ubuntu configuration file for max security daily scans
            if [[ -f /etc/chkrootkit.conf ]]; then
                sed -i 's/^RUN_DAILY=".*"/RUN_DAILY="true"/' /etc/chkrootkit.conf
                sed -i 's/^RUN_DAILY_OPTS=".*"/RUN_DAILY_OPTS="-q"/' /etc/chkrootkit.conf
                sed -i 's/^DIFF_MODE=".*"/DIFF_MODE="true"/' /etc/chkrootkit.conf
                msg_info "Hardened /etc/chkrootkit.conf for daily automated diff scanning."
            fi
            ;;
        pacman)
            pacman -S --needed --noconfirm chkrootkit || msg_warn "chkrootkit installation via pacman skipped or missing in main repositories."
            
            # Configure manual daily cron execution on Arch Linux
            mkdir -p /etc/cron.daily
            cat << 'EOF' > /etc/cron.daily/chkrootkit
#!/usr/bin/env bash
/usr/bin/chkrootkit -q > /var/log/chkrootkit.log 2>&1
EOF
            chmod 700 /etc/cron.daily/chkrootkit
            ;;
        *)
            msg_error "Unsupported package manager '$package_manager' for Chkrootkit."
            return 1
            ;;
    esac

    msg_success "Chkrootkit successfully configured for daily rootkit detection."
}

setup_threat_protection() {
    local package_manager="$1"

    msg_info "Starting full Antivirus & Rootkit Security Suite installation..."

    setup_clamav_cli "$package_manager"
    print_separator

    if ! is_server_environment; then
        setup_clamui "$package_manager"
    else
        msg_info "Headless server environment detected. Skipping ClamUI (GUI) installation."
    fi

    setup_lynis "$package_manager"
    print_separator

    setup_chkrootkit "$package_manager"
    print_separator
}