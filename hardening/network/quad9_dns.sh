#!/usr/bin/env bash
set -euo pipefail

configure_quad9_dns() {
    msg_info "Configuring Quad9 DNS (Malware blocking, DNSSEC, DoT)..."

    local resolved_dir="/etc/systemd/resolved.conf.d"
    local resolved_conf="${resolved_dir}/quad9.conf"

    # 1. Si systemd-resolved está activo, se configura a través del demonio
    if systemctl is-active --quiet systemd-resolved 2>/dev/null || systemctl is-enabled --quiet systemd-resolved 2>/dev/null; then
        mkdir -p "$resolved_dir"
        
        cat << 'EOF' > "$resolved_conf"
[Resolve]
DNS=9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9
FallbackDNS=9.9.9.10 149.112.112.10 2620:fe::10 2620:fe::fe:10
DNSOverTLS=yes
DNSSEC=yes
EOF
        chmod 644 "$resolved_conf"
        
        msg_info "Restarting systemd-resolved to apply Quad9..."
        if systemctl restart systemd-resolved &>/dev/null; then
            msg_success "Quad9 DNS successfully configured via systemd-resolved."
            return 0
        fi
    fi

    # 2. Fallback: Edición directa de /etc/resolv.conf si systemd-resolved no está activo
    msg_warn "systemd-resolved not active. Applying Quad9 directly to /etc/resolv.conf..."

    if [[ -f /etc/resolv.conf ]]; then
        # Desproteger si tenía el atributo inmutable de una ejecución previa
        chattr -i /etc/resolv.conf 2>/dev/null || true
        
        cp /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%F_%T)"
        
        cat << 'EOF' > /etc/resolv.conf
# Configured by Hardening Script - Quad9 DNS
nameserver 9.9.9.9
nameserver 149.112.112.112
nameserver 2620:fe::fe
nameserver 2620:fe::9
EOF

        # Proteger contra modificación externa
        chattr +i /etc/resolv.conf 2>/dev/null || true
        msg_success "Quad9 DNS applied directly to /etc/resolv.conf (Immutable)."
    else
        msg_error "Could not configure DNS: /etc/resolv.conf not found."
        return 1
    fi
}

configure_quad9_dns