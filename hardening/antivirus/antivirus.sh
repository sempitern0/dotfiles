#!/usr/bin/env bash
set -euo pipefail

# Helper variables
CLAMAV_DB_DIR="/var/lib/clamav"
CLAMAV_MIRROR_URL="https://database.clamav.net"

setup_clamav_db_fallback() {
    msg_warn "Freshclam failed to update virus database automatically. Executing direct download fallback..."

    mkdir -p "$CLAMAV_DB_DIR"

    local dbs=("main.cvd" "daily.cvd" "bytecode.cvd")
    
    for db in "${dbs[@]}"; do
        if [[ ! -f "${CLAMAV_DB_DIR}/${db}" ]]; then
            msg_info "Downloading fallback database file: ${db}..."
            curl -sSL --connect-timeout 10 --retry 3 \
                "${CLAMAV_MIRROR_URL}/${db}" -o "${CLAMAV_DB_DIR}/${db}" || \
                msg_error "Failed to download ${db} from fallback mirror."
        fi
    done

    # Fix directory permissions for clamav user
    if id "clamav" &>/dev/null; then
        chown -R clamav:clamav "$CLAMAV_DB_DIR"
        chmod 755 "$CLAMAV_DB_DIR"
    fi
}

setup_clamav_cli() {
    local package_manager="$1"

    msg_info "Installing and configuring ClamAV Antivirus Daemon & Freshclam..."

    # Install required packages based on detected package manager
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

    # Temporarily stop freshclam daemon to release lockfile
    msg_info "Stopping freshclam service for initial database signature update..."
    systemctl stop clamav-freshclam &>/dev/null || systemctl stop freshclam &>/dev/null || true

    # Attempt freshclam update with retry mechanism
    msg_info "Updating virus signature database with freshclam..."
    local freshclam_success=false
    for attempt in {1..3}; do
        if freshclam; then
            freshclam_success=true
            break
        fi
        msg_warn "Freshclam attempt $attempt failed. Retrying in 3 seconds..."
        sleep 3
    done

    # Execute direct download fallback if freshclam failed and DB is missing
    if [[ "$freshclam_success" == "false" ]]; then
        setup_clamav_db_fallback
    fi

    # Enable and start background services
    msg_info "Enabling and starting ClamAV daemon and update services..."
    if [[ "$package_manager" == "apt" ]]; then
        systemctl enable --now clamav-freshclam &>/dev/null || true
        systemctl enable --now clamav-daemon &>/dev/null || true
    elif [[ "$package_manager" == "pacman" ]]; then
        systemctl enable --now freshclam &>/dev/null || true
        systemctl enable --now clamd &>/dev/null || true
    fi

    # Verify daemon status
    local daemon_svc="clamav-daemon"
    [[ "$package_manager" == "pacman" ]] && daemon_svc="clamd"

    if systemctl is-active --quiet "$daemon_svc"; then
        msg_success "ClamAV daemon ($daemon_svc) is active and running."
    else
        msg_warn "ClamAV daemon ($daemon_svc) failed to activate. Check logs using: journalctl -u $daemon_svc"
    fi

    # Configure daily automated ClamAV scan cron job
    msg_info "Configuring daily automated ClamAV background scan..."
    mkdir -p /etc/cron.daily

    cat << 'EOF' > /etc/cron.daily/clamav-scan
#!/usr/bin/env bash
# Daily ClamAV multithreaded system scan targeting sensitive paths
LOG_FILE="/var/log/clamav/daily_scan.log"
mkdir -p /var/log/clamav

if command -v clamdscan &>/dev/null; then
    clamdscan --multiscan --fdpass /home /tmp /var/tmp /dev/shm > "$LOG_FILE" 2>&1
elif command -v clamscan &>/dev/null; then
    clamscan -r --infected --exclude-dir="^/sys" --exclude-dir="^/proc" --exclude-dir="^/dev" /home /tmp > "$LOG_FILE" 2>&1
fi
EOF
    chmod 700 /etc/cron.daily/clamav-scan
    msg_success "Daily ClamAV scan script deployed to /etc/cron.daily/clamav-scan."
}

setup_clamui() {
    local package_manager="$1"
    local github_repo="linx-systems/clamui" 
    local temp_dir
    temp_dir=$(mktemp -d -t clamui_XXXXXX)

    # Cleanup temp directory on exit
    trap 'rm -rf "$temp_dir"' EXIT

    msg_info "Setting up ClamUI graphical interface..."

    case "$package_manager" in
        apt)
            msg_info "Fetching latest ClamUI release from GitHub..."
            local deb_url
            deb_url=$(curl -s "https://api.github.com/repos/${github_repo}/releases/latest" | \
                      jq -r '.assets[]? | select(.name | endswith(".deb")) | .browser_download_url' | head -n 1)

            if [[ -z "$deb_url" || "$deb_url" == "null" ]]; then
                msg_warn "Could not fetch ClamUI release via GitHub API. Skipping GUI setup."
                return 0
            fi

            msg_info "Downloading ClamUI package..."
            curl -sSL "$deb_url" -o "${temp_dir}/clamui_latest.deb"

            msg_info "Installing ClamUI via APT..."
            apt install -y "${temp_dir}/clamui_latest.deb" || msg_warn "ClamUI installation finished with warnings."
            ;;

        pacman)
            msg_info "Checking AUR installation methods for Arch Linux..."
            local target_user="${SUDO_USER:-$USER}"

            if [[ "$target_user" != "root" ]] && command -v yay &>/dev/null; then
                msg_info "Installing ClamUI via yay (AUR)..."
                sudo -u "$target_user" yay -S --noconfirm clamui-git || true
            elif [[ "$target_user" != "root" ]] && command -v paru &>/dev/null; then
                msg_info "Installing ClamUI via paru (AUR)..."
                sudo -u "$target_user" paru -S --noconfirm clamui-git || true
            else
                msg_warn "No non-root AUR helper found. Skipping ClamUI installation on Arch Linux."
            fi
            ;;

        *)
            msg_error "Unsupported package manager '$package_manager' for ClamUI."
            return 1
            ;;
    esac

    msg_success "ClamUI setup procedure completed."
}

setup_lynis() {
    local package_manager="$1"

    msg_info "Installing Lynis system auditing tool..."

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

    # Configure daily automated audit job
    msg_info "Configuring daily automated Lynis security audits..."
    mkdir -p /etc/cron.daily

    cat << 'EOF' > /etc/cron.daily/lynis-audit
#!/usr/bin/env bash
/usr/bin/lynis audit system --quick --cronjob > /var/log/lynis-cron.log 2>&1
EOF
    chmod 700 /etc/cron.daily/lynis-audit

    msg_success "Lynis installed and daily audit cron job (/etc/cron.daily/lynis-audit) configured."
}

setup_chkrootkit() {
    local package_manager="$1"

    msg_info "Installing Chkrootkit & Rkhunter rootkit detection tools..."

    case "$package_manager" in
        apt)
            apt update -qq
            apt install -y chkrootkit rkhunter

            if [[ -f /etc/chkrootkit.conf ]]; then
                sed -i 's/^RUN_DAILY=".*"/RUN_DAILY="true"/' /etc/chkrootkit.conf
                sed -i 's/^RUN_DAILY_OPTS=".*"/RUN_DAILY_OPTS="-q"/' /etc/chkrootkit.conf
                sed -i 's/^DIFF_MODE=".*"/DIFF_MODE="true"/' /etc/chkrootkit.conf
                msg_info "Hardened /etc/chkrootkit.conf for daily automated diff scanning."
            fi
            ;;
        pacman)
            pacman -S --needed --noconfirm rkhunter || true
            pacman -S --needed --noconfirm chkrootkit || msg_warn "chkrootkit skipped or unavailable in Arch main repos."
            
            mkdir -p /etc/cron.daily
            cat << 'EOF' > /etc/cron.daily/rootkit-scan
#!/usr/bin/env bash
[[ -x /usr/bin/chkrootkit ]] && /usr/bin/chkrootkit -q > /var/log/chkrootkit.log 2>&1
[[ -x /usr/bin/rkhunter ]] && /usr/bin/rkhunter --cronjob --update --sk > /var/log/rkhunter.log 2>&1
EOF
            chmod 700 /etc/cron.daily/rootkit-scan
            ;;
        *)
            msg_error "Unsupported package manager '$package_manager' for Rootkit detection tools."
            return 1
            ;;
    esac

    msg_success "Rootkit detection tools successfully configured."
}

setup_threat_protection() {
    local package_manager="$1"

    msg_info "Starting full Antivirus & Rootkit Security Suite installation..."

    setup_clamav_cli "$package_manager"
    print_separator

    if declare -f is_server_environment &>/dev/null && ! is_server_environment; then
        setup_clamui "$package_manager"
        print_separator
    else
        msg_info "Headless server environment detected or condition met. Skipping ClamUI (GUI)."
    fi

    setup_lynis "$package_manager"
    print_separator

    setup_chkrootkit "$package_manager"
    print_separator
}