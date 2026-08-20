#!/usr/bin/env bash
set -euo pipefail


SSH_PORT="${SSH_PORT:-22}"
ALLOWED_SERVICES=("80/tcp" "443/tcp")


if [[ $EUID -ne 0 ]]; then
    msg_error "This script requires root privileges (run with sudo)."
    exit 1
fi

if ! command -v ufw &>/dev/null; then
    msg_error "UFW is not installed on this system."
    exit 1
fi

msg_info "Starting network hardening with UFW..."

ufw --force reset &>/dev/null

ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

ufw allow in on lo comment 'Allow incoming loopback'
ufw allow out on lo comment 'Allow outgoing loopback'
ufw deny in from 127.0.0.0/8 comment 'Prevent loopback IP spoofing'
ufw deny in from ::1 comment 'Prevent IPv6 loopback IP spoofing'

msg_info "Configuring SSH anti brute-force protection on port ${SSH_PORT}..."
ufw limit "${SSH_PORT}/tcp" comment 'SSH anti brute-force protection'

for service in "${ALLOWED_SERVICES[@]}"; do
    msg_info "Allowing traffic on port ${service}..."
    ufw allow "${service}" comment 'Public web service'
done

ufw deny 5353/udp comment 'Block mDNS'
ufw deny 137,138/udp comment 'Block NetBIOS'
ufw deny 139,445/tcp comment 'Block SMB share'

ufw allow from 192.168.1.0/24 to any port 631 proto tcp comment 'CUPS local printer'

ufw logging low
ufw --force enable

echo -e "\n========================================"
echo -e " UFW FIREWALL CURRENT STATUS"
echo -e "========================================"
ufw status verbose numbered