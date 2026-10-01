# shellcheck shell=bash
# Sourced module: defines apply_firewalld_rules; performs no action on import.

apply_firewalld_rules() {
    command_exists firewall-cmd || { msg_error "firewalld is not installed."; return 1; }
    hardening_backup_path /etc/firewalld || return 1
    hardening_record_service firewalld.service
    run_as_root systemctl enable --now firewalld.service || return 1

    local zone="" iface="" ssh_port=""
    iface="$(ip route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [[ -n "$iface" ]] && zone="$(firewall-cmd --get-zone-of-interface="$iface" 2>/dev/null || true)"
    [[ -n "$zone" ]] || zone="$(firewall-cmd --get-default-zone 2>/dev/null || true)"
    [[ -n "$zone" ]] || { msg_error "Unable to determine firewalld zone."; return 1; }

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        ssh_port="$(awk '{print $4}' <<<"$SSH_CONNECTION")"
        [[ "$ssh_port" =~ ^[0-9]+$ ]] || ssh_port=""
    fi

    msg_info "Hardening active/default firewalld zone '$zone' without deleting existing services/ports."
    run_as_root firewall-cmd --permanent --zone="$zone" --set-target=DROP || return 1
    if [[ -n "$ssh_port" ]]; then
        msg_warn "Remote SSH session detected; preserving TCP/$ssh_port."
        run_as_root firewall-cmd --permanent --zone="$zone" --add-port="${ssh_port}/tcp" || return 1
    fi
    run_as_root firewall-cmd --reload || return 1
    run_as_root firewall-cmd --zone="$zone" --list-all || true
}
