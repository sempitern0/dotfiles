#!/usr/bin/env bash
set -euo pipefail

msg_info()    { echo -e "\e[34m[INFO]\e[0m $*"; }
msg_success() { echo -e "\e[32m[OK]\e[0m $*"; }
msg_warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }
msg_error()   { echo -e "\e[31m[ERROR]\e[0m $*"; }

verify_quad9() {
    msg_info "Verifying connection to Quad9..."
    sleep 2

    if ! command -v dig &>/dev/null; then
        msg_warn "Tool 'dig' is not installed. Skipping Quad9 validation protocol check."
        return 0
    fi

    local proto
    proto=$(dig +short +time=2 +tries=1 txt proto.on.quad9.net 2>/dev/null | tr -d '"')

    if [[ "$proto" == "dot" ]]; then
        msg_success "Quad9 successfully configured with DNS-over-TLS (DoT)."
    elif [[ "$proto" == "do53-udp" || "$proto" == "do53-tcp" ]]; then
        msg_warn "Connected to Quad9 via standard DNS (Protocol: $proto)."
    else
        msg_error "Could not confirm Quad9 usage. Verify network connectivity or firewall rules."
    fi
}

configure_quad9_dns() {
    msg_info "Configuring Quad9 DNS (Malware blocking, DNSSEC)..."

    # Step 1: Prevent active network daemons from overwriting DNS
    prevent_all_dns_overrides

    # Detect WSL environment
    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        msg_info "WSL environment detected. Disabling automatic resolv.conf generation in /etc/wsl.conf..."
        if [[ -f /etc/wsl.conf ]]; then
            if ! grep -q "generateResolvConf" /etc/wsl.conf; then
                echo -e "\n[network]\ngenerateResolvConf = false" >> /etc/wsl.conf
            fi
        else
            echo -e "[network]\ngenerateResolvConf = false" > /etc/wsl.conf
        fi
    fi

    local resolved_dir="/etc/systemd/resolved.conf.d"
    local resolved_conf="${resolved_dir}/quad9.conf"

    # Step 2: Primary configuration via systemd-resolved
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        mkdir -p "$resolved_dir"
        
        cat << 'EOF' > "$resolved_conf"
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net
FallbackDNS=9.9.9.10#dns.quad9.net 149.112.112.10#dns.quad9.net 2620:fe::10#dns.quad9.net
# Changed to opportunistic to avoid complete network failure if port 853 TCP is blocked
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
Domains=~.
EOF
        chmod 644 "$resolved_conf"
        
        # Link /etc/resolv.conf to systemd-resolved stub
        chattr -i /etc/resolv.conf 2>/dev/null || true
        rm -f /etc/resolv.conf
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

        msg_info "Restarting systemd-resolved to apply changes..."
        if systemctl restart systemd-resolved; then
            msg_success "Quad9 DNS configured via systemd-resolved."
            verify_quad9
            return 0
        else
            msg_warn "Failed to restart systemd-resolved. Falling back to static /etc/resolv.conf..."
            rm -f "$resolved_conf"
        fi
    fi

    # Step 3: Fallback - Static /etc/resolv.conf
    msg_warn "Applying Quad9 directly to /etc/resolv.conf..."

    chattr -i /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf

    cat << 'EOF' > /etc/resolv.conf
# Manually configured - Quad9 DNS
nameserver 9.9.9.9
nameserver 149.112.112.112
nameserver 2620:fe::fe
EOF

    # Apply immutable flag only if not in WSL / container
    if ! grep -qi "microsoft" /proc/version 2>/dev/null; then
        chattr +i /etc/resolv.conf 2>/dev/null || true
    fi

    msg_success "Quad9 DNS applied directly to /etc/resolv.conf."
    verify_quad9
}

configure_quad9_dns