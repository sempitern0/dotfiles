#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
ALLOWED_SERVICES=("80/tcp" "443/tcp")

msg_info "Starting network hardening with nftables..."

if ! command_exists nft; then
    msg_error "nftables is not installed. Please install it first."
    return 1
fi

if [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]; then
    msg_warn "SSH session detected. Ensuring port $SSH_PORT is authorized before resetting."
fi

systemctl enable --now nftables &>/dev/null || true

msg_info "Flushing existing nftables ruleset..."
nft flush ruleset

# Creación de tabla y cadenas de filtrado base
nft add table inet filter
nft add chain inet filter input '{ type filter hook input priority filter; policy drop; }'
nft add chain inet filter forward '{ type filter hook forward priority filter; policy drop; }'
nft add chain inet filter output '{ type filter hook output priority filter; policy accept; }'

# Control de estado de conexiones y descartar paquetes INVALID
msg_info "Configuring connection tracking and INVALID packet drops..."
nft add rule inet filter input ct state established,related accept
nft add rule inet filter input ct state invalid drop

# Protecciones para la interfaz de loopback
msg_info "Applying loopback protections..."
nft add rule inet filter input iifname "lo" accept
nft add rule inet filter input ip saddr 127.0.0.0/8 drop
nft add rule inet filter input ip6 saddr ::1 drop

# Anti brute-force para SSH (Sintaxis moderna de nftables)
msg_info "Configuring SSH anti brute-force protection on port ${SSH_PORT}..."
nft add set inet filter ssh_meter '{ type ipv4_addr; flags dynamic, timeout; timeout 1m; }'
nft add rule inet filter input tcp dport "${SSH_PORT}" add @ssh_meter { ip saddr limit rate over 10/minute } drop
nft add rule inet filter input tcp dport "${SSH_PORT}" accept

# Puertos y servicios públicos
for service in "${ALLOWED_SERVICES[@]}"; do
    IFS="/" read -r port proto <<< "$service"
    msg_info "Allowing traffic on port ${port}/${proto}..."
    nft add rule inet filter input "${proto}" dport "${port}" accept
done

# Bloqueo de protocolos locales vulnerables o ruidosos
msg_info "Blocking mDNS, NetBIOS, and SMB..."
nft add rule inet filter input udp dport 5353 drop
nft add rule inet filter input udp dport { 137, 138 } drop
nft add rule inet filter input tcp dport { 139, 445 } drop

# Reglas internas específicas (CUPS)
msg_info "Allowing CUPS local printer traffic from 192.168.1.0/24..."
nft add rule inet filter input ip saddr 192.168.1.0/24 tcp dport 631 accept

# Guardar reglas para persistencia
if [[ -d /etc/nftables.conf.d ]]; then
    nft list ruleset > /etc/nftables.conf.d/hardening.nft
else
    nft list ruleset > /etc/nftables.conf
fi

msg_success "nftables configured and applied successfully."

print_separator
echo -e "${cyanColour}=== NFTABLES CURRENT STATUS ===${endColour}"
nft list ruleset
print_separator