# shellcheck shell=bash
# Sourced module: defines apply_nftables_rules; performs no action on import.

apply_nftables_rules() {
    command_exists nft || { msg_error "nftables is not installed."; return 1; }
    local existing="" ssh_port="" tmp=""
    existing="$(nft list ruleset 2>/dev/null || true)"

    if [[ -n "${existing//[[:space:]]/}" ]]; then
        msg_warn "An existing nftables ruleset is present. The assistant will not flush or replace it."
        msg_info "Use the existing firewall policy or review it manually."
        return 1
    fi

    if [[ -s /etc/nftables.conf ]] && grep -Evq '^[[:space:]]*(#|$)' /etc/nftables.conf; then
        msg_warn "/etc/nftables.conf already contains active configuration while the runtime ruleset is empty."
        msg_warn "Refusing to replace a dormant/custom firewall configuration automatically."
        return 1
    fi

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        ssh_port="$(awk '{print $4}' <<<"$SSH_CONNECTION")"
        [[ "$ssh_port" =~ ^[0-9]+$ ]] || ssh_port=""
    fi

    hardening_backup_path /etc/nftables.conf || return 1
    hardening_record_service nftables.service
    tmp="$(mktemp)" || return 1
    cat >"$tmp" <<EOF_RULES
#!/usr/sbin/nft -f
# Managed by Dotfiles System Hardening Assistant.

table inet dotfiles_filter {
    chain input {
        type filter hook input priority 0; policy drop;
        iifname "lo" accept
        ct state established,related accept
        ct state invalid drop
        # DHCP client renewals/offers may arrive before conntrack considers a flow established.
        udp sport 67 udp dport 68 accept
        udp sport 547 udp dport 546 accept
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
EOF_RULES
    if [[ -n "$ssh_port" ]]; then
        printf '        tcp dport %s ct state new accept comment "preserve active SSH management"\n' "$ssh_port" >>"$tmp"
    fi
    cat >>"$tmp" <<'EOF_RULES'
    }
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF_RULES

    nft -c -f "$tmp" || { rm -f "$tmp"; msg_error "Generated nftables policy failed syntax validation."; return 1; }
    mkdir -p /etc
    cp "$tmp" /etc/nftables.conf
    chmod 0644 /etc/nftables.conf
    rm -f "$tmp"
    nft -f /etc/nftables.conf || return 1
    if service_exists nftables.service; then
        systemctl enable --now nftables.service >/dev/null 2>&1 || { msg_warn "nftables.service could not be enabled; runtime rules are still loaded."; }
    fi
    nft list ruleset
}
