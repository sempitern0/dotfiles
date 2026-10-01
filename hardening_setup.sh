#!/usr/bin/env bash
# Dotfiles System Hardening Assistant
# Balanced workstation security with explicit high-impact modules and rollback.

# No `set -e`: interactive modules may fail or be unavailable without terminating
# the control plane. nounset/pipefail still catch real programming mistakes.
set -u
set -o pipefail
IFS=$'\n\t'
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SCRIPT_VERSION="2.1.0-workstation-hardening"
DOTFILES_UI_PRODUCT="SECURITY & HARDENING CONTROL PLANE"
ORIGINAL_ARGS=("$@")
HARDENING_ROOT="/var/backups/dotfiles-hardening"
HARDENING_SNAPSHOT=""
HARDENING_MANIFEST=""
HARDENING_SERVICES=""
declare -A HARDENING_BACKED=()
declare -A HARDENING_SERVICE_RECORDED=()

usage() {
    cat <<EOF_HELP
Dotfiles System Hardening Assistant v${SCRIPT_VERSION}

Usage:
  sudo ./hardening_setup.sh                 interactive menu
  sudo ./hardening_setup.sh --audit         read-only security posture
  sudo ./hardening_setup.sh --recommended   balanced workstation baseline
  sudo ./hardening_setup.sh --all           run all modules; high-impact modules still confirm
  sudo ./hardening_setup.sh --restore       select and restore an assistant snapshot
  sudo ./hardening_setup.sh --no-color
  sudo ./hardening_setup.sh --help
EOF_HELP
}

prepare_context() {
    require_linux || return 1
    resolve_target_user || return 1
    ensure_root "${ORIGINAL_ARGS[@]}" || return 1
    detect_distribution || {
        msg_error "Unsupported Linux package family. Hardening requires Debian/Ubuntu, Arch, Fedora/RHEL-like or openSUSE/SLES."
        return 1
    }
    load_distro_module "$SCRIPT_DIR" || return 1
}

start_hardening_evidence() {
    mkdir -p /var/log/dotfiles-hardening
    chmod 0700 /var/log/dotfiles-hardening
    DOTFILES_RESULT_FILE="/var/log/dotfiles-hardening/run-$DOTFILES_RUN_ID.tsv"
    : >"$DOTFILES_RESULT_FILE"
    chmod 0600 "$DOTFILES_RESULT_FILE"
}

hardening_snapshot_init() {
    [[ -n "$HARDENING_SNAPSHOT" ]] && return 0
    HARDENING_SNAPSHOT="$HARDENING_ROOT/$DOTFILES_RUN_ID"
    HARDENING_MANIFEST="$HARDENING_SNAPSHOT/paths.tsv"
    HARDENING_SERVICES="$HARDENING_SNAPSHOT/services.tsv"
    mkdir -p "$HARDENING_SNAPSHOT/rootfs" "$HARDENING_SNAPSHOT/evidence"
    chmod 0700 "$HARDENING_SNAPSHOT" "$HARDENING_SNAPSHOT/rootfs" "$HARDENING_SNAPSHOT/evidence"
    : >"$HARDENING_MANIFEST"
    : >"$HARDENING_SERVICES"
    {
        printf 'created=%s\n' "$(date -Is)"
        printf 'host=%s\n' "$(hostname -f 2>/dev/null || hostname)"
        printf 'os=%s\n' "${OS_PRETTY:-unknown}"
        printf 'target_user=%s\n' "$TARGET_USER"
        printf 'version=%s\n' "$SCRIPT_VERSION"
    } >"$HARDENING_SNAPSHOT/metadata.txt"
    msg_info "Recovery snapshot: $HARDENING_SNAPSHOT"
}

hardening_backup_path() {
    local path="$1" key="$1" rel="${1#/}" dst=""
    hardening_snapshot_init || return 1
    [[ -z "${HARDENING_BACKED[$key]:-}" ]] || return 0
    HARDENING_BACKED[$key]=1

    if [[ -e "$path" || -L "$path" ]]; then
        dst="$HARDENING_SNAPSHOT/rootfs/$rel"
        mkdir -p "$(dirname "$dst")"
        cp -a -- "$path" "$dst" || return 1
        printf 'PRESENT\t%s\n' "$path" >>"$HARDENING_MANIFEST"
    else
        printf 'ABSENT\t%s\n' "$path" >>"$HARDENING_MANIFEST"
    fi
}

hardening_restore_path_from_current_snapshot() {
    local path="$1" rel="${1#/}" source="" state=""
    source="$HARDENING_SNAPSHOT/rootfs/$rel"
    [[ -n "$HARDENING_SNAPSHOT" && -f "$HARDENING_MANIFEST" ]] || return 1
    state="$(awk -F '\t' -v p="$path" '$2==p{print $1; exit}' "$HARDENING_MANIFEST")"
    case "$state" in
        PRESENT)
            rm -rf -- "$path"
            mkdir -p "$(dirname "$path")"
            cp -a -- "$source" "$path"
            ;;
        ABSENT) rm -rf -- "$path" ;;
        *) return 1 ;;
    esac
}

hardening_finalize_snapshot() {
    [[ -n "${HARDENING_SNAPSHOT:-}" && -d "$HARDENING_SNAPSHOT" ]] || return 0
    (
        cd "$HARDENING_SNAPSHOT" || exit 1
        if command_exists sha256sum; then
            find rootfs -type f -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum >SHA256SUMS
            [[ -f networkmanager-dns.env ]] && sha256sum networkmanager-dns.env >>SHA256SUMS
        fi
    ) || true
    printf 'finalized=%s\n' "$(date -Is)" >>"$HARDENING_SNAPSHOT/metadata.txt"
    chmod 0600 "$HARDENING_SNAPSHOT/metadata.txt" "$HARDENING_SNAPSHOT/paths.tsv" "$HARDENING_SNAPSHOT/services.tsv" 2>/dev/null || true
}

hardening_record_service() {
    local unit="$1" enabled="not-found" active="not-found"
    hardening_snapshot_init || return 1
    [[ -z "${HARDENING_SERVICE_RECORDED[$unit]:-}" ]] || return 0
    HARDENING_SERVICE_RECORDED[$unit]=1

    if service_exists "$unit"; then
        enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
        active="$(systemctl is-active "$unit" 2>/dev/null || true)"
        [[ -n "$enabled" ]] || enabled="disabled"
        [[ -n "$active" ]] || active="inactive"
    fi
    printf '%s\t%s\t%s\n' "$unit" "$enabled" "$active" >>"$HARDENING_SERVICES"
}

restore_snapshot_dir() {
    local snap="$1" manifest="" services="" state path rel src unit enabled active
    manifest="$snap/paths.tsv"
    services="$snap/services.tsv"
    [[ -d "$snap" && -f "$manifest" ]] || { msg_error "Invalid snapshot: $snap"; return 1; }
    confirm_literal "Restore assistant-managed paths and recorded service states from $(basename "$snap")?" "RESTORE" || return 0

    while IFS=$'\t' read -r state path; do
        [[ -n "$path" ]] || continue
        rel="${path#/}"
        src="$snap/rootfs/$rel"
        case "$state" in
            PRESENT)
                [[ -e "$src" || -L "$src" ]] || { msg_warn "Backup payload missing: $path"; continue; }
                rm -rf -- "$path"
                mkdir -p "$(dirname "$path")"
                cp -a -- "$src" "$path" || msg_warn "Failed restoring $path"
                ;;
            ABSENT) rm -rf -- "$path" 2>/dev/null || true ;;
        esac
    done <"$manifest"

    if [[ -f "$snap/networkmanager-dns.env" ]] && command_exists nmcli; then
        # Root-owned file generated with printf %q by this assistant.
        # shellcheck disable=SC1090
        source "$snap/networkmanager-dns.env"
        if [[ -n "${NM_UUID:-}" ]]; then
            msg_warn "Restoring NetworkManager DNS for connection ${NM_UUID}. This can briefly interrupt connectivity."
            nmcli connection modify "$NM_UUID" \
                ipv4.ignore-auto-dns "${NM_V4_IGNORE:-no}" ipv4.dns "${NM_V4_DNS:-}" \
                ipv6.ignore-auto-dns "${NM_V6_IGNORE:-no}" ipv6.dns "${NM_V6_DNS:-}" || true
            nmcli connection up "$NM_UUID" >/dev/null 2>&1 || true
        fi
    fi

    if [[ -f "$services" ]]; then
        while IFS=$'\t' read -r unit enabled active; do
            service_exists "$unit" || continue
            case "$enabled" in
                enabled|enabled-runtime|linked|linked-runtime) systemctl enable "$unit" >/dev/null 2>&1 || true ;;
                disabled|not-found) systemctl disable "$unit" >/dev/null 2>&1 || true ;;
            esac
            case "$active" in
                active|activating) systemctl start "$unit" >/dev/null 2>&1 || true ;;
                inactive|failed|deactivating|not-found) systemctl stop "$unit" >/dev/null 2>&1 || true ;;
            esac
        done <"$services"
    fi

    systemctl daemon-reload >/dev/null 2>&1 || true
    sysctl --system >/dev/null 2>&1 || true
    for unit in ssh.service sshd.service fail2ban.service firewalld.service nftables.service systemd-resolved.service; do
        systemctl try-reload-or-restart "$unit" >/dev/null 2>&1 || true
    done
    msg_success "Snapshot restoration completed. Review networking and authentication before closing the recovery session."
}

restore_snapshot_menu() {
    local -a snaps=() ; local d choice
    while IFS= read -r d; do snaps+=("$d"); done < <(find "$HARDENING_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%p\n' 2>/dev/null | sort -r)
    ((${#snaps[@]})) || { msg_warn "No hardening snapshots are available."; return 0; }
    ui_has_tty || { msg_error "Snapshot selection requires /dev/tty."; return 1; }

    printf '\nAvailable snapshots:\n'
    local i
    for i in "${!snaps[@]}"; do
        printf '  [%d] %s\n' "$((i+1))" "$(basename "${snaps[$i]}")"
    done
    choice="$(ask 'Snapshot number' '1')" || return 1
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#snaps[@]} )) || { msg_warn "Invalid snapshot selection."; return 1; }
    restore_snapshot_dir "${snaps[$((choice-1))]}"
}

security_audit() {
    ui_header "SECURITY POSTURE" "Read-only workstation assessment" "$DOTFILES_UI_PRODUCT"
    printf '  %-27s %s\n' "Kernel" "$(uname -r)"
    printf '  %-27s %s\n' "Distribution" "$OS_PRETTY"
    printf '  %-27s %s\n' "Package manager" "$DISTRO_PACKAGE_MANAGER"
    printf '  %-27s %s\n' "Secure Boot" "$(command_exists mokutil && mokutil --sb-state 2>/dev/null | head -n1 || printf unknown)"
    printf '  %-27s %s\n' "SELinux" "$(command_exists getenforce && getenforce 2>/dev/null || printf unavailable)"
    printf '  %-27s %s\n' "AppArmor" "$(command_exists aa-status && aa-status --enabled >/dev/null 2>&1 && printf enabled || printf unavailable/not-enabled)"
    printf '\nFirewall frontends:\n'
    firewall_status_summary
    printf '  %-27s %s\n' "Fail2Ban" "$(systemctl is-active fail2ban.service 2>/dev/null || printf inactive/unavailable)"
    printf '  %-27s %s\n' "SSH server" "$(command_exists sshd && printf installed || printf absent)"
    printf '\nKernel controls:\n'
    printf '  %-27s %s\n' "kptr_restrict" "$(sysctl -n kernel.kptr_restrict 2>/dev/null || printf unavailable)"
    printf '  %-27s %s\n' "dmesg_restrict" "$(sysctl -n kernel.dmesg_restrict 2>/dev/null || printf unavailable)"
    printf '  %-27s %s\n' "ptrace_scope" "$(sysctl -n kernel.yama.ptrace_scope 2>/dev/null || printf unavailable)"
    printf '  %-27s %s\n' "unprivileged_bpf" "$(sysctl -n kernel.unprivileged_bpf_disabled 2>/dev/null || printf unavailable)"
    printf '\nListening sockets:\n'
    ss -lntup 2>/dev/null || ss -lntu 2>/dev/null || true
    printf '\nFailed systemd units:\n'
    systemctl --failed --no-pager 2>/dev/null || true
}

hardening_install_sysctl_template() {
    local src="$1" dst="$2" tmp="" line="" key="" proc=""
    [[ -f "$src" ]] || { msg_error "Sysctl template not found: $src"; return 1; }
    hardening_backup_path "$dst" || return 1
    tmp="$(mktemp)" || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*# || -z "${line//[[:space:]]/}" || "$line" != *"="* ]]; then
            printf '%s\n' "$line" >>"$tmp"
            continue
        fi
        key="${line%%=*}"
        key="${key#${key%%[![:space:]]*}}"
        key="${key%${key##*[![:space:]]}}"
        proc="/proc/sys/${key//./\/}"
        if [[ -e "$proc" ]]; then
            printf '%s\n' "$line" >>"$tmp"
        else
            msg_skip "Kernel does not expose sysctl '$key'; omitted from persistent policy."
        fi
    done <"$src"

    mkdir -p "$(dirname "$dst")"
    cp "$tmp" "$dst"
    rm -f "$tmp"
    chmod 0644 "$dst"
    sysctl -p "$dst"
}

apply_network_kernel_baseline() {
    local src="$SCRIPT_DIR/hardening/network/99-hardening.conf" dst="/etc/sysctl.d/90-dotfiles-network-hardening.conf"
    [[ -f "$src" ]] || { msg_error "Missing network sysctl template."; return 1; }
    hardening_install_sysctl_template "$src" "$dst"
}

select_firewall_engine() {
    # Preserve an already-active frontend before selecting a family default.
    service_active firewalld.service && command_exists firewall-cmd && { printf firewalld; return; }
    command_exists ufw && ufw status 2>/dev/null | grep -q '^Status: active' && { printf ufw; return; }
    service_active nftables.service && command_exists nft && { printf nftables; return; }

    # If installed but inactive, preserve the administrator's existing choice.
    command_exists firewall-cmd && { printf firewalld; return; }
    command_exists ufw && { printf ufw; return; }
    command_exists nft && { printf nftables; return; }

    # Distro-family defaults use only official repositories.
    case "$OS_FAMILY" in
        debian) printf ufw ;;
        fedora|opensuse) printf firewalld ;;
        arch) printf nftables ;;
        *) printf nftables ;;
    esac
}

firewall_status_summary() {
    printf '  %-18s %s
' "UFW" "$(command_exists ufw && ufw status 2>/dev/null | head -n1 || printf not-installed)"
    printf '  %-18s %s
' "firewalld" "$(service_active firewalld.service && printf active || { command_exists firewall-cmd && printf installed-inactive || printf not-installed; })"
    printf '  %-18s %s
' "nftables" "$(service_active nftables.service && printf active || { command_exists nft && printf installed/runtime-unknown || printf not-installed; })"
    if command_exists nft; then
        local rules=""
        rules="$(nft list ruleset 2>/dev/null || true)"
        printf '  %-18s %s
' "nft rules" "$( [[ -n "${rules//[[:space:]]/}" ]] && printf present || printf empty )"
    fi
}

configure_firewall() {
    local engine="${1:-}" module="" config_path="" unit="" binary=""
    [[ -n "$engine" && "$engine" != "auto" ]] || engine="$(select_firewall_engine)"
    msg_info "Selected firewall frontend: $engine (OS family: $OS_FAMILY)"

    case "$engine" in
        ufw)
            unit="ufw.service"; binary="ufw"; config_path="/etc/ufw"
            ;;
        firewalld)
            unit="firewalld.service"; binary="firewall-cmd"; config_path="/etc/firewalld"
            ;;
        nftables)
            unit="nftables.service"; binary="nft"; config_path="/etc/nftables.conf"
            ;;
        *) msg_error "Unsupported firewall engine: $engine"; return 1 ;;
    esac

    # Snapshot the pre-package state. Installing a package may create configuration
    # directories and even units before the module gets a chance to back them up.
    hardening_backup_path "$config_path" || return 1
    hardening_record_service "$unit"

    if ! command_exists "$binary"; then
        msg_info "Installing $engine from configured official repositories..."
        install_packages "$engine" || return 1
        hash -r 2>/dev/null || true
    fi
    command_exists "$binary" || { msg_error "$engine package completed but '$binary' is still unavailable in PATH."; return 1; }

    module="$SCRIPT_DIR/hardening/network/${engine}.sh"
    [[ -r "$module" ]] || { msg_error "Firewall module missing: $module"; return 1; }
    # shellcheck disable=SC1090
    source "$module" || return 1
    "apply_${engine}_rules" || return 1

    printf '
Firewall verification:
'
    firewall_status_summary

    case "$engine" in
        ufw) ufw status 2>/dev/null | grep -q '^Status: active' || { msg_error "UFW policy was not active after apply."; return 1; } ;;
        firewalld) service_active firewalld.service || { msg_error "firewalld is not active after apply."; return 1; } ;;
        nftables)
            nft list ruleset 2>/dev/null | grep -q 'table inet dotfiles_filter' || { msg_error "Expected nftables table was not loaded."; return 1; }
            ;;
    esac
    msg_success "Firewall baseline active via $engine."
}

firewall_menu() {
    ui_has_tty || { configure_firewall auto; return; }
    while true; do
        ui_header "FIREWALL POLICY" "Existing active frontends are preserved. Auto uses the distribution-family default." "$DOTFILES_UI_PRODUCT"
        firewall_status_summary
        ui_section "Frontend"
        ui_menu_item "1" "Automatic" "Debian/Kali=UFW, Fedora/openSUSE=firewalld, Arch=nftables" "$C_GREEN" "DEFAULT"
        ui_menu_item "2" "UFW" "Simple host firewall; preserve existing rules"
        ui_menu_item "3" "nftables" "Native ruleset; refuses to overwrite an existing custom ruleset"
        ui_menu_item "4" "firewalld" "Zone-based frontend; preserve existing services/ports"
        ui_menu_item "0" "Back" "Return to hardening menu" "$C_RED"
        local choice
        choice="$(ask 'Firewall choice' '1')" || return 1
        case "$choice" in
            1) run_task "Automatic firewall baseline" configure_firewall auto; return 0 ;;
            2) run_task "UFW firewall baseline" configure_firewall ufw; return 0 ;;
            3) run_task "nftables firewall baseline" configure_firewall nftables; return 0 ;;
            4) run_task "firewalld firewall baseline" configure_firewall firewalld; return 0 ;;
            0|q|Q) return 0 ;;
            *) msg_warn "Invalid firewall selection." ;;
        esac
    done
}

ssh_service_name() {
    service_exists ssh.service && { printf ssh.service; return; }
    service_exists sshd.service && { printf sshd.service; return; }
    return 1
}

ssh_runtime_active() {
    service_active ssh.service && return 0
    service_active sshd.service && return 0
    service_active ssh.socket && return 0
    service_active sshd.socket && return 0
    ss -lntp 2>/dev/null | grep -Eq 'sshd|:22[[:space:]]' && return 0
    return 1
}

setup_active_ssh_hardening() {
    command_exists sshd || { msg_skip "OpenSSH server is not installed."; return 0; }
    ssh_runtime_active || { msg_skip "OpenSSH server is installed but not active/listening; recommended profile leaves it untouched."; return 0; }
    setup_ssh_hardening
}

setup_ssh_hardening() {
    command_exists sshd || { msg_skip "OpenSSH server is not installed; no server is added by hardening."; return 0; }
    local service="" main="/etc/ssh/sshd_config" dir="/etc/ssh/sshd_config.d" drop=""
    drop="$dir/90-dotfiles-hardening.conf"
    service="$(ssh_service_name 2>/dev/null || true)"
    [[ -f "$main" ]] || { msg_warn "sshd binary exists but $main is absent."; return 1; }

    hardening_backup_path "$main" || return 1
    hardening_backup_path "$drop" || return 1
    [[ -n "$service" ]] && hardening_record_service "$service"
    mkdir -p "$dir" /run/sshd
    chmod 0755 /run/sshd 2>/dev/null || true

    if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$main"; then
        local tmp="${main}.dotfiles.$$"
        { printf 'Include /etc/ssh/sshd_config.d/*.conf
'; cat "$main"; } >"$tmp"
        chmod --reference="$main" "$tmp" 2>/dev/null || chmod 0600 "$tmp"
        chown --reference="$main" "$tmp" 2>/dev/null || true
        mv -f "$tmp" "$main"
    fi

    cat >"$drop" <<'EOF_SSH'
# Balanced SSH server hardening: avoids remote lockout and preserves forwarding use cases.
PermitRootLogin prohibit-password
MaxAuthTries 4
LoginGraceTime 45
ClientAliveInterval 300
ClientAliveCountMax 2
EOF_SSH
    chmod 0600 "$drop"

    if ! sshd -t; then
        msg_error "sshd validation failed; restoring the pre-change SSH configuration."
        hardening_restore_path_from_current_snapshot "$main" || true
        hardening_restore_path_from_current_snapshot "$drop" || true
        return 1
    fi

    if ssh_runtime_active; then
        if [[ -n "$service" ]] && service_active "$service"; then
            systemctl reload "$service" >/dev/null 2>&1 || {
                msg_warn "$service is active but does not support reload; configuration is valid and will apply on next restart."
            }
        else
            msg_info "SSH is socket-activated/listening without an active reloadable service; validated config will apply to new sshd processes."
        fi
    else
        msg_info "SSH service is inactive; configuration was validated but the assistant did not start it."
    fi
}

setup_ssh_key_only() {
    command_exists sshd || { msg_skip "OpenSSH server not installed."; return 0; }
    local auth="$TARGET_HOME/.ssh/authorized_keys" drop="/etc/ssh/sshd_config.d/91-dotfiles-key-only.conf" service=""
    [[ -s "$auth" ]] || {
        msg_error "Refusing key-only SSH: $auth is missing or empty for target user '$TARGET_USER'."
        return 1
    }
    confirm_literal "Disable SSH password and keyboard-interactive authentication? Keep this recovery session open until a second key login succeeds." "KEY-ONLY" || return 0
    hardening_backup_path "$drop" || return 1
    cat >"$drop" <<'EOF_KEYONLY'
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
EOF_KEYONLY
    chmod 0600 "$drop"
    if ! sshd -t; then
        hardening_restore_path_from_current_snapshot "$drop" || true
        return 1
    fi
    service="$(ssh_service_name 2>/dev/null || true)"
    if [[ -n "$service" ]]; then
        hardening_record_service "$service"
        service_active "$service" && systemctl reload "$service" >/dev/null 2>&1 || true
    fi
    msg_warn "Validate a new SSH login before closing the current session."
}

setup_fail2ban() {
    command_exists sshd || { msg_skip "No SSH server detected; SSH Fail2Ban jail is unnecessary."; return 0; }
    ssh_runtime_active || { msg_skip "SSH server is not active/listening; Fail2Ban SSH jail is unnecessary."; return 0; }
    hardening_record_service fail2ban.service
    install_packages fail2ban || return 1
    hardening_backup_path /etc/fail2ban/jail.local || return 1
    hardening_backup_path /etc/fail2ban/jail.d/90-dotfiles-sshd.local || return 1
    hardening_record_service fail2ban.service
    mkdir -p /etc/fail2ban/jail.d
    cp "$SCRIPT_DIR/hardening/fail2ban/jail.local" /etc/fail2ban/jail.local
    cp "$SCRIPT_DIR/hardening/fail2ban/ssh.local" /etc/fail2ban/jail.d/90-dotfiles-sshd.local
    chmod 0644 /etc/fail2ban/jail.local /etc/fail2ban/jail.d/90-dotfiles-sshd.local
    fail2ban-client -t || return 1
    systemctl enable --now fail2ban.service || return 1
    fail2ban-client status sshd 2>/dev/null || true
}

setup_automatic_security_updates() {
    case "$OS_FAMILY" in
        debian)
            hardening_record_service apt-daily.timer
            hardening_record_service apt-daily-upgrade.timer
            install_packages unattended-upgrades || return 1
            local dst="/etc/apt/apt.conf.d/20auto-upgrades"
            hardening_backup_path "$dst" || return 1
            cp "$SCRIPT_DIR/hardening/debian/20auto-upgrades" "$dst"
            chmod 0644 "$dst"
            service_exists apt-daily.timer && systemctl enable --now apt-daily.timer >/dev/null 2>&1 || true
            service_exists apt-daily-upgrade.timer && systemctl enable --now apt-daily-upgrade.timer >/dev/null 2>&1 || true
            ;;
        fedora)
            local pkg="" timer="" cfg="/etc/dnf/automatic.conf"
            hardening_record_service dnf5-automatic.timer
            hardening_record_service dnf-automatic.timer
            pkg_refresh_once || true
            if pkg_available dnf5-plugins; then pkg="dnf5-plugins"; else pkg="dnf-automatic"; fi
            install_packages "$pkg" || return 1
            if service_exists dnf5-automatic.timer; then timer="dnf5-automatic.timer"; else timer="dnf-automatic.timer"; fi
            service_exists "$timer" || { msg_warn "No DNF automatic timer found after package installation."; return 1; }
            hardening_backup_path "$cfg" || return 1
            hardening_record_service "$timer"
            mkdir -p /etc/dnf
            cat >"$cfg" <<'EOF_DNF'
[commands]
upgrade_type = security
download_updates = yes
apply_updates = yes
random_sleep = 900
reboot = never

[emitters]
emit_via = stdio
EOF_DNF
            systemctl enable --now "$timer"
            ;;
        opensuse)
            msg_warn "Automatic patch policy differs between Leap and Tumbleweed; no generic unattended policy is imposed."
            msg_info "Use the distribution's YaST Online Update policy on Leap; keep Tumbleweed snapshot upgrades deliberate."
            return 0
            ;;
        arch)
            msg_warn "Automatic unattended upgrades are intentionally not enabled on rolling-release Arch systems."
            return 0
            ;;
    esac
}

setup_dns_security() {
    # shellcheck source=hardening/network/quad9_dns.sh
    source "$SCRIPT_DIR/hardening/network/quad9_dns.sh" || return 1
    configure_quad9_dns
}

apply_kernel_memory_baseline() {
    # shellcheck source=hardening/hardware/memory_hardening.sh
    source "$SCRIPT_DIR/hardening/hardware/memory_hardening.sh" || return 1
    apply_process_memory_hardening
}

strict_shared_memory_wrapper() {
    source "$SCRIPT_DIR/hardening/hardware/memory_hardening.sh" || return 1
    strict_shared_memory
}

strict_module_blacklist_wrapper() {
    source "$SCRIPT_DIR/hardening/hardware/memory_hardening.sh" || return 1
    strict_module_blacklist
}

mac_time_service_audit() {
    printf 'SELinux      : %s\n' "$(command_exists getenforce && getenforce 2>/dev/null || printf unavailable)"
    printf 'AppArmor     : %s\n' "$(command_exists aa-status && aa-status --enabled >/dev/null 2>&1 && printf enabled || printf unavailable/not-enabled)"
    printf 'Time sync    : %s\n' "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || printf unknown)"
    printf 'Time service : %s\n' "$(timedatectl show -p NTP --value 2>/dev/null || printf unknown)"
    printf '\nEnabled network-facing services (best effort):\n'
    systemctl list-unit-files --state=enabled --type=service --no-pager 2>/dev/null |
        grep -Ei 'ssh|http|apache|nginx|samba|smb|nfs|rpc|avahi|cups|docker|podman|libvirt|vnc|rdp' || true
    msg_info "No MAC profile or desktop service is forcibly disabled by this audit."
}

install_threat_tools() {
    source "$SCRIPT_DIR/hardening/antivirus/antivirus.sh" || return 1
    setup_threat_protection
}

setup_usbguard() {
    msg_warn "USBGuard can block new keyboards, storage devices and phones until explicitly authorized."
    confirm_literal "Install USBGuard and whitelist devices currently connected?" "ENABLE-USBGUARD" || return 0
    hardening_record_service usbguard.service
    install_packages usbguard || return 1
    command_exists usbguard || return 1
    hardening_backup_path /etc/usbguard/rules.conf || return 1
    hardening_record_service usbguard.service
    mkdir -p /etc/usbguard
    usbguard generate-policy > /etc/usbguard/rules.conf || return 1
    chmod 0600 /etc/usbguard/rules.conf
    systemctl enable --now usbguard.service || return 1
}

profile_recommended() {
    run_task "Security posture audit" security_audit
    run_task "Balanced network sysctl" apply_network_kernel_baseline
    run_task "Balanced kernel memory baseline" apply_kernel_memory_baseline
    run_task "Host firewall baseline" configure_firewall
    run_task "Active SSH server baseline" setup_active_ssh_hardening
    run_task "Automatic security updates" setup_automatic_security_updates
    run_task "SSH brute-force protection" setup_fail2ban
    run_task "MAC, time and service exposure audit" mac_time_service_audit
}

profile_all() {
    profile_recommended
    run_task "Key-only SSH policy" setup_ssh_key_only
    run_task "Quad9 DNS policy" setup_dns_security
    run_task "Threat protection tools" install_threat_tools
    run_task "USBGuard" setup_usbguard
    run_task "Strict /dev/shm policy" strict_shared_memory_wrapper
    run_task "Strict kernel module blacklist" strict_module_blacklist_wrapper
}

execute_option() {
    case "${1,,}" in
        1|audit) security_audit ;;
        2|recommended|baseline) profile_recommended ;;
        3|network|sysctl) run_task "Balanced network sysctl" apply_network_kernel_baseline ;;
        4|kernel|memory) run_task "Balanced kernel memory baseline" apply_kernel_memory_baseline ;;
        5|firewall) firewall_menu ;;
        6|updates) run_task "Automatic security updates" setup_automatic_security_updates ;;
        7|ssh) run_task "Existing/active SSH baseline" setup_ssh_hardening ;;
        8|fail2ban) run_task "SSH brute-force protection" setup_fail2ban ;;
        9|exposure|mac) run_task "MAC, time and service exposure audit" mac_time_service_audit ;;
        10|dns|quad9) run_task "Quad9 DNS policy" setup_dns_security ;;
        11|threat|antivirus) run_task "Threat protection tools" install_threat_tools ;;
        12|key-only|keyonly) run_task "Key-only SSH policy" setup_ssh_key_only ;;
        13|usb|usbguard) run_task "USBGuard" setup_usbguard ;;
        14|shm) run_task "Strict /dev/shm policy" strict_shared_memory_wrapper ;;
        15|blacklist) run_task "Strict kernel module blacklist" strict_module_blacklist_wrapper ;;
        16|restore) restore_snapshot_menu ;;
        17|all|full) profile_all ;;
        0|q|quit|exit) return 20 ;;
        *) msg_warn "Unknown hardening selection: $1" ;;
    esac
    return 0
}

interactive_menu() {
    ui_has_tty || { msg_error "Interactive mode requires /dev/tty. Use --audit/--recommended/--all."; return 1; }
    while true; do
        ui_header "SYSTEM HARDENING" "Recommended is workstation-safe. Optional/high-impact controls never run silently." "$DOTFILES_UI_PRODUCT"

        ui_section "Start here"
        ui_menu_item "1" "Security posture audit" "Read-only kernel, firewall, MAC, SSH, sockets and failed units" "$C_CYAN" "READ-ONLY"
        ui_menu_item "2" "Recommended baseline" "sysctl + firewall + active SSH + updates + conditional Fail2Ban" "$C_GREEN" "DEFAULT"

        ui_section "Baseline controls"
        ui_menu_item "3" "Network sysctl" "VPN/container-compatible protocol hardening" "$C_CYAN" "SAFE"
        ui_menu_item "4" "Kernel / memory" "Pointers, dmesg, ptrace, BPF and protected links" "$C_CYAN" "SAFE"
        ui_menu_item "5" "Firewall" "Choose/inspect UFW, nftables or firewalld" "$C_CYAN" "SAFE"
        ui_menu_item "6" "Security updates" "Native distribution update policy" "$C_CYAN" "SAFE"
        ui_menu_item "7" "SSH baseline" "Only configures an existing server; never installs/starts sshd" "$C_CYAN" "CONDITIONAL"
        ui_menu_item "8" "Fail2Ban SSH" "Only when SSH is actually active/listening" "$C_CYAN" "CONDITIONAL"
        ui_menu_item "9" "MAC / time / exposure" "Read-only SELinux/AppArmor/time/service review" "$C_CYAN" "READ-ONLY"

        ui_section "Optional policy changes"
        ui_menu_item "10" "Quad9 DNS" "Host-wide DNS; avoid on AD/split-DNS/VPN unless intended" "$C_YELLOW" "OPT-IN"
        ui_menu_item "11" "Threat tools" "ClamAV/Lynis/rootkit tooling from official repos" "$C_YELLOW" "OPT-IN"

        ui_section "High-impact controls"
        ui_menu_item "12" "SSH key-only" "Requires authorized_keys and literal confirmation" "$C_RED" "HIGH"
        ui_menu_item "13" "USBGuard" "Can block new keyboards/storage/phones" "$C_RED" "HIGH"
        ui_menu_item "14" "Strict /dev/shm" "noexec can break developer/desktop workloads" "$C_RED" "HIGH"
        ui_menu_item "15" "Module blacklist" "Blocks uncommon kernel protocols" "$C_RED" "HIGH"

        ui_section "Recovery / advanced"
        ui_menu_item "16" "Restore snapshot" "Restore assistant-managed files and service states" "$C_MAGENTA" "RECOVERY"
        ui_menu_item "17" "Advanced all" "Runs all modules; high-impact steps still ask individually" "$C_YELLOW" "CONFIRM"
        ui_menu_item "0" "Exit" "Leave hardening workspace" "$C_RED"
        ui_rule

        local input token rc=0
        local -a selections=()
        input="$(ask 'Selection(s)' '1')" || return 1
        input="${input//,/ }"
        IFS=' ' read -r -a selections <<<"$input"
        for token in "${selections[@]}"; do
            [[ -n "$token" ]] || continue
            execute_option "$token" || rc=$?
            (( rc == 20 )) && { show_run_summary; return 0; }
        done
        ui_pause
    done
}

main() {
    local mode="interactive"
    while (($#)); do
        case "$1" in
            --audit) mode="audit" ;;
            --recommended) mode="recommended" ;;
            --all|--full) mode="all" ;;
            --restore) mode="restore" ;;
            --no-color) DOTFILES_NO_COLOR=1; ui_color_init ;;
            --help|-h) usage; return 0 ;;
            *) msg_error "Unknown argument: $1"; usage >&2; return 2 ;;
        esac
        shift
    done

    prepare_context || return 1
    [[ "$mode" == "audit" ]] || start_hardening_evidence
    local rc=0
    case "$mode" in
        audit) security_audit || rc=$? ;;
        recommended) profile_recommended; show_run_summary ;;
        all) profile_all; show_run_summary ;;
        restore) restore_snapshot_menu || rc=$? ;;
        interactive) interactive_menu || rc=$? ;;
    esac
    hardening_finalize_snapshot
    return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    trap 'printf "\n" >&2; msg_warn "Hardening interrupted. Package-manager locks were not modified. Recovery snapshots remain in /var/backups/dotfiles-hardening."; exit 130' INT TERM
    main "$@"
fi
