#!/usr/bin/env bash
set -euo pipefail

local SSH_PORT="${SSH_PORT:-22}"
local ALLOWED_SERVICES=("80/tcp" "443/tcp")

msg_info "Starting network hardening with UFW..."

if ! command -v ufw &>/dev/null; then
    msg_error "UFW is not installed. Please install it first."
    return 1
fi

# Security check: Ensure we don't drop existing SSH connections blindly
if [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]; then
    msg_warn "SSH session detected. Ensuring port $SSH_PORT is authorized before resetting."
fi

ufw --force reset &>/dev/null

# Default policies
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

# Loopback protections
ufw allow in on lo comment 'Allow incoming loopback'
ufw allow out on lo comment 'Allow outgoing loopback'
ufw deny in from 127.0.0.0/8 comment 'Prevent loopback IP spoofing'
ufw deny in from ::1 comment 'Prevent IPv6 loopback IP spoofing'

local before_rules="/etc/ufw/before.rules"
if [[ -f "$before_rules" ]]; then
    if ! grep -q "Drop INVALID packets" "$before_rules"; then
        msg_info "Injecting CTSTATE INVALID drop rules into before.rules..."
        sed -i '/# End required lines/a \
\n# Drop INVALID packets (Hardening)\n-A ufw-before-input -m conntrack --ctstate INVALID -j DROP\n' "$before_rules"
    fi
fi

# SSH Rate Limiting
msg_info "Configuring SSH anti brute-force protection on port ${SSH_PORT}..."
ufw limit "${SSH_PORT}/tcp" comment 'SSH anti brute-force protection'

# Public Services
for service in "${ALLOWED_SERVICES[@]}"; do
    msg_info "Allowing traffic on port ${service}..."
    ufw allow "${service}" comment 'Public web service'
done

# Block common noisy/vulnerable local protocols
ufw deny 5353/udp comment 'Block mDNS'
ufw deny 137,138/udp comment 'Block NetBIOS'
ufw deny 139,445/tcp comment 'Block SMB share'

# Specific internal rules
ufw allow from 192.168.1.0/24 to any port 631 proto tcp comment 'CUPS local printer'

# Enable and log
ufw logging low
ufw --force enable &>/dev/null

msg_success "UFW configured and enabled successfully."

print_separator
echo -e "${cyanColour}=== UFW FIREWALL CURRENT STATUS ===${endColour}"
ufw status verbose numbered
print_separator
