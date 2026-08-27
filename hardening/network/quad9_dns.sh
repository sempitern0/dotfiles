#!/usr/bin/env bash
set -euo pipefail

msg_info()    { echo -e "\e[34m[INFO]\e[0m $*"; }
msg_success() { echo -e "\e[32m[OK]\e[0m $*"; }
msg_warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }
msg_error()   { echo -e "\e[31m[ERROR]\e[0m $*"; }

prevent_networkmanager_dns_override() {
    if ! command -v NetworkManager &>/dev/null && ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
        return 0
    fi

    msg_info "NetworkManager detected. Configuring it to ignore DNS overrides..."

    local nm_conf_dir="/etc/NetworkManager/conf.d"
    local nm_conf_file="${nm_conf_dir}/99-ignore-dns.conf"

    mkdir -p "$nm_conf_dir"

    cat << 'EOF' > "$nm_conf_file"
# Configured by Hardening Script
# Prevent NetworkManager from managing DNS or pushing DHCP DNS servers
[main]
dns=none
rc-manager=unmanaged
EOF

    chmod 644 "$nm_conf_file"

    if systemctl is-active --quiet NetworkManager; then
        systemctl reload NetworkManager &>/dev/null || systemctl restart NetworkManager &>/dev/null || true
        msg_success "NetworkManager configured: DNS overrides disabled."
    fi
}

prevent_dhcpcd_dns_override() {
    if ! command -v dhcpcd &>/dev/null && ! systemctl is-active --quiet dhcpcd 2>/dev/null; then
        return 0
    fi

    msg_info "dhcpcd detected. Configuring it to disable DNS updates..."

    local dhcpcd_conf="/etc/dhcpcd.conf"
    
    if [[ -f "$dhcpcd_conf" ]]; then
        if ! grep -qE "^\s*nohook\s+resolv\.conf" "$dhcpcd_conf"; then
            echo "" >> "$dhcpcd_conf"
            echo "# Configured by Hardening Script - Prevent DNS override" >> "$dhcpcd_conf"
            echo "nohook resolv.conf" >> "$dhcpcd_conf"
        fi
    else
        mkdir -p "$(dirname "$dhcpcd_conf")"
        echo "nohook resolv.conf" > "$dhcpcd_conf"
    fi

    if systemctl is-active --quiet dhcpcd; then
        systemctl restart dhcpcd &>/dev/null || true
    fi

    msg_success "dhcpcd configured: 'nohook resolv.conf' applied."
}

prevent_systemd_networkd_dns_override() {
    if ! systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        return 0
    fi

    msg_info "systemd-networkd detected. Configuring network profiles to ignore DHCP DNS..."

    local net_dir="/etc/systemd/network"

    if [[ -d "$net_dir" ]]; then
        # Apply drop-in overrides to all existing .network files
        for netfile in "$net_dir"/*.network; do
            if [[ -f "$netfile" ]]; then
                local dropin_dir="${netfile}.d"
                mkdir -p "$dropin_dir"
                cat << 'EOF' > "${dropin_dir}/disable-dns.conf"
# Configured by Hardening Script
[DHCPv4]
UseDNS=false

[DHCPv6]
UseDNS=false
EOF
            fi
        done
    fi

    if systemctl is-active --quiet systemd-networkd; then
        systemctl reload-or-restart systemd-networkd &>/dev/null || true
    fi

    msg_success "systemd-networkd configured: DHCP DNS disabled on network profiles."
}

prevent_dhclient_dns_override() {
    local dhclient_conf="/etc/dhcp/dhclient.conf"

    if [[ -f "$dhclient_conf" ]]; then
        msg_info "dhclient configuration found. Setting DNS override rules..."
        if ! grep -q "supersede domain-name-servers" "$dhclient_conf"; then
            echo "" >> "$dhclient_conf"
            echo "# Configured by Hardening Script - Force Quad9 DNS" >> "$dhclient_conf"
            echo "supersede domain-name-servers 9.9.9.9, 149.112.112.112, 2620:fe::fe;" >> "$dhclient_conf"
            msg_success "dhclient configured: DNS superseded."
        fi
    fi
}

prevent_all_dns_overrides() {
    prevent_networkmanager_dns_override
    prevent_dhcpcd_dns_override
    prevent_systemd_networkd_dns_override
    prevent_dhclient_dns_override
}

verify_quad9() {
    msg_info "Verifying connection to Quad9..."
    sleep 2 # Allow time for systemd-resolved to apply changes

    local proto
    proto=$(dig +short +time=2 +tries=1 txt proto.on.quad9.net 2>/dev/null | tr -d '"')

    if [[ "$proto" == "dot" ]]; then
        msg_success "Quad9 successfully configured with DNS-over-TLS (DoT)."
    elif [[ "$proto" == "do53-udp" || "$proto" == "do53-tcp" ]]; then
        msg_warn "Connected to Quad9, but WITHOUT encryption (Protocol: $proto)."
    else
        msg_error "Could not confirm Quad9 usage. Check your network configuration or firewall (port 853 TCP)."
    fi
}

configure_quad9_dns() {
    msg_info "Configuring Quad9 DNS (Malware blocking, DNSSEC, DoT)..."

    # Step 1: Prevent all active network daemons from overwriting DNS
    prevent_all_dns_overrides

    local resolved_dir="/etc/systemd/resolved.conf.d"
    local resolved_conf="${resolved_dir}/quad9.conf"

    # Step 2: Primary configuration via systemd-resolved
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        mkdir -p "$resolved_dir"
        
        cat << 'EOF' > "$resolved_conf"
[Resolve]
# Quad9 DNS with SNI validation for DoT
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net
FallbackDNS=9.9.9.10#dns.quad9.net 149.112.112.10#dns.quad9.net 2620:fe::10#dns.quad9.net
DNSOverTLS=yes
# allow-downgrade prevents browsing failures if local DNSSEC validation issues occur
DNSSEC=allow-downgrade
# Force Quad9 as the default route for all queries across all interfaces
Domains=~.
EOF
        chmod 644 "$resolved_conf"
        
        msg_info "Restarting systemd-resolved to apply changes..."
        if systemctl restart systemd-resolved; then
            msg_success "Quad9 DNS configured via systemd-resolved."
            verify_quad9
            return 0
        else
            msg_warn "Failed to restart systemd-resolved. Removing partial configuration..."
            rm -f "$resolved_conf"
        fi
    fi

    # Step 3: Fallback - Direct modification of /etc/resolv.conf
    msg_warn "systemd-resolved is not active. Applying Quad9 directly to /etc/resolv.conf..."

    # Remove previous immutable attribute if present and break symlinks
    chattr -i /etc/resolv.conf 2>/dev/null || true
    
    if [[ -L /etc/resolv.conf ]]; then
        msg_info "Removing symlink /etc/resolv.conf to create a static file..."
        rm -f /etc/resolv.conf
    elif [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%F_%T)"
    fi

    # Maximum 3 nameservers supported by glibc resolver
    cat << 'EOF' > /etc/resolv.conf
# Manually configured - Quad9 DNS
nameserver 9.9.9.9
nameserver 149.112.112.112
nameserver 2620:fe::fe
EOF

    chattr +i /etc/resolv.conf 2>/dev/null || true
    msg_success "Quad9 DNS applied directly to /etc/resolv.conf (Immutable)."
    verify_quad9
}

configure_quad9_dns