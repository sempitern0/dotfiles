# shellcheck shell=bash
# Optional DNS privacy/security module. No immutable resolv.conf and no network
# manager is disabled. The function performs no action until explicitly called.

verify_quad9() {
    command_exists dig || { msg_warn "dig unavailable; checking resolver reachability only."; return 0; }
    local answer=""
    answer="$(dig +short +time=3 +tries=1 txt proto.on.quad9.net 2>/dev/null | tr -d '"' || true)"
    [[ -n "$answer" ]] && msg_info "Quad9 protocol probe: $answer" || msg_warn "Quad9 protocol probe did not return data."
}

configure_quad9_dns() {
    msg_warn "Changing DNS can break split-DNS, VPN and Active Directory environments."
    confirm_literal "Apply Quad9 as the host-wide resolver? Existing resolver configuration will be backed up." "APPLY-DNS" || return 0

    if systemctl is-active --quiet systemd-resolved.service 2>/dev/null; then
        hardening_backup_path /etc/systemd/resolved.conf.d/90-dotfiles-quad9.conf || return 1
        hardening_backup_path /etc/resolv.conf || return 1
        mkdir -p /etc/systemd/resolved.conf.d
        cat >/etc/systemd/resolved.conf.d/90-dotfiles-quad9.conf <<'EOF_RESOLVED'
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
EOF_RESOLVED
        systemctl restart systemd-resolved.service || return 1
        verify_quad9
        return 0
    fi

    if command_exists nmcli && systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
        local conn="" uuid="" dev="" state_file="" v4_ignore="" v4_dns="" v6_ignore="" v6_dns=""
        conn="$(nmcli -t -f NAME connection show --active 2>/dev/null | head -n1)"
        [[ -n "$conn" ]] || { msg_error "No active NetworkManager connection found."; return 1; }
        uuid="$(nmcli -g connection.uuid connection show "$conn" 2>/dev/null | head -n1)"
        dev="$(nmcli -g GENERAL.DEVICES connection show "$conn" 2>/dev/null | head -n1)"
        [[ -n "$uuid" ]] || { msg_error "Unable to resolve NetworkManager connection UUID."; return 1; }

        hardening_snapshot_init || return 1
        state_file="$HARDENING_SNAPSHOT/networkmanager-dns.env"
        v4_ignore="$(nmcli -g ipv4.ignore-auto-dns connection show "$uuid" 2>/dev/null || true)"
        v4_dns="$(nmcli -g ipv4.dns connection show "$uuid" 2>/dev/null || true)"
        v6_ignore="$(nmcli -g ipv6.ignore-auto-dns connection show "$uuid" 2>/dev/null || true)"
        v6_dns="$(nmcli -g ipv6.dns connection show "$uuid" 2>/dev/null || true)"
        {
            printf 'NM_UUID=%q\n' "$uuid"
            printf 'NM_DEVICE=%q\n' "$dev"
            printf 'NM_V4_IGNORE=%q\n' "$v4_ignore"
            printf 'NM_V4_DNS=%q\n' "$v4_dns"
            printf 'NM_V6_IGNORE=%q\n' "$v6_ignore"
            printf 'NM_V6_DNS=%q\n' "$v6_dns"
        } >"$state_file"
        chmod 0600 "$state_file"
        nmcli connection show "$uuid" >"$HARDENING_SNAPSHOT/evidence/networkmanager-before.txt" 2>&1 || true

        msg_warn "NetworkManager connection '$conn' will be changed; its previous DNS settings are rollback-capable."
        nmcli connection modify "$uuid"             ipv4.ignore-auto-dns yes ipv4.dns "9.9.9.9 149.112.112.112"             ipv6.ignore-auto-dns yes ipv6.dns "2620:fe::fe 2620:fe::9" || return 1
        nmcli connection up "$uuid" || return 1
        verify_quad9
        return 0
    fi

    msg_warn "Neither systemd-resolved nor an active NetworkManager connection is available."
    msg_warn "Static /etc/resolv.conf is intentionally not overwritten by this assistant."
    return 1
}
