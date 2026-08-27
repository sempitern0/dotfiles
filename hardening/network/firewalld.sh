#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
ALLOWED_SERVICES=("80/tcp" "443/tcp")

msg_info "Starting network hardening with firewalld..."

if ! command_exists firewall-cmd; then
    msg_error "firewalld is not installed. Please install it first."
    exit 1
fi

if [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]; then
    msg_warn "SSH session detected. Ensuring port $SSH_PORT is authorized."
fi

systemctl enable --now firewalld &>/dev/null || true

msg_info "Setting default zone to drop..."
firewall-cmd --set-default-zone=drop &>/dev/null

# Anti brute-force para SSH (Rich rule dinámica vinculada a SSH_PORT)
msg_info "Configuring SSH anti brute-force protection on port ${SSH_PORT}..."
firewall-cmd --permanent --add-rich-rule="rule port port=\"${SSH_PORT}\" protocol=\"tcp\" limit value=\"10/m\" accept" &>/dev/null

# Puertos y servicios públicos
for service in "${ALLOWED_SERVICES[@]}"; do
    msg_info "Allowing traffic on port ${service}..."
    firewall-cmd --permanent --add-port="${service}" &>/dev/null
done

# Regla interna específica (CUPS)
msg_info "Allowing CUPS printer traffic from 192.168.1.0/24..."
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="631" protocol="tcp" accept' &>/dev/null

# Aplicar cambios en memoria
firewall-cmd --reload &>/dev/null

msg_success "firewalld configured and enabled successfully."

print_separator
echo -e "${cyanColour}=== FIREWALLD CURRENT STATUS ===${endColour}"
firewall-cmd --list-all
print_separator