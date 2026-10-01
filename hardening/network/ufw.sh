# shellcheck shell=bash
# Sourced module: defines apply_ufw_rules; performs no action on import.

apply_ufw_rules() {
    command_exists ufw || { msg_error "ufw is not installed."; return 1; }
    hardening_backup_path /etc/ufw || return 1
    hardening_record_service ufw.service

    local ssh_port=""
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        ssh_port="$(awk '{print $4}' <<<"$SSH_CONNECTION")"
        [[ "$ssh_port" =~ ^[0-9]+$ ]] || ssh_port=""
    fi

    msg_info "UFW keeps existing explicit rules; no reset is performed."
    run_as_root ufw default deny incoming || return 1
    run_as_root ufw default allow outgoing || return 1

    if [[ -n "$ssh_port" ]]; then
        msg_warn "Remote SSH session detected; preserving TCP/$ssh_port before enabling UFW."
        run_as_root ufw limit "${ssh_port}/tcp" comment 'Dotfiles: preserve active SSH management' || return 1
    fi

    run_as_root ufw logging low || true
    run_as_root ufw --force enable || return 1
    run_as_root ufw status verbose || true
}
