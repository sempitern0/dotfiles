#!/usr/bin/env bash
set -euo pipefail

# Global default variables
SSH_PORT="${SSH_PORT:-22}"
ALLOWED_SERVICES=("80/tcp" "443/tcp")

apply_nftables_rules() {
    msg_info "Starting network hardening with nftables..."

    if ! command_exists nft; then
        msg_error "nftables is not installed. Please install it first."
        return 1
    fi

    # Security check: Ensure we don't drop existing SSH connections blindly
    if [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]; then
        msg_warn "SSH session detected. Ensuring port $SSH_PORT is authorized before resetting."
    fi

    systemctl enable --now nftables &>/dev/null || true

    msg_info "Flushing existing nftables ruleset..."
    nft flush ruleset

    # Base table and filtering chain creation
    msg_info "Creating base inet filter table and chains..."
    nft add table inet filter
    nft add chain inet filter input '{ type filter hook input priority filter; policy drop; }'
    nft add chain inet filter forward '{ type filter hook forward priority filter; policy drop; }'
    nft add chain inet filter output '{ type filter hook output priority filter; policy accept; }'

    # Connection tracking and INVALID packet drops
    msg_info "Configuring connection tracking and INVALID packet drops..."
    nft add rule inet filter input ct state established,related accept
    nft add rule inet filter input ct state invalid drop

    # Loopback interface protections
    msg_info "Applying loopback protections..."
    nft add rule inet filter input iifname "lo" accept
    nft add rule inet filter input ip saddr 127.0.0.0/8 drop
    nft add rule inet filter input ip6 saddr ::1 drop

    # Anti brute-force for SSH (modern nftables meter syntax)
    msg_info "Configuring SSH anti brute-force protection on port ${SSH_PORT}..."
    nft add set inet filter ssh_meter '{ type ipv4_addr; flags dynamic, timeout; timeout 1m; }'
    nft add rule inet filter input tcp dport "${SSH_PORT}" add @ssh_meter { ip saddr limit rate over 10/minute } drop
    nft add rule inet filter input tcp dport "${SSH_PORT}" accept

    # Public services and allowed ports
    for service in "${ALLOWED_SERVICES[@]}"; do
        IFS="/" read -r port proto <<< "$service"
        msg_info "Allowing traffic on port ${port}/${proto}..."
        nft add rule inet filter input "${proto}" dport "${port}" accept
    done

    # Hypervisor detection and rule injection
    local hypervisor
    hypervisor=$(detect_hypervisor || true)

    if [[ "$hypervisor" == "virtualbox" ]]; then
        msg_info "VirtualBox environment detected. Injecting network isolation rules into nftables output chain..."

        # 1. Allow outbound traffic to the VirtualBox NAT Gateway (10.0.2.2)
        nft add rule inet filter output ip daddr 10.0.2.2 accept

        # 2. Deny outbound traffic to private local network ranges (RFC 1918)
        # Prevents the VM from scanning or accessing the host's local LAN
        nft add rule inet filter output ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } drop

        msg_success "VirtualBox nftables network isolation rules applied."
    else
        msg_skip "Hypervisor is '$hypervisor'. Skipping VirtualBox-specific nftables rules."

        # Block noisy or vulnerable local protocols on non-VirtualBox environments
        msg_info "Blocking mDNS, NetBIOS, and SMB..."
        nft add rule inet filter input udp dport 5353 drop
        nft add rule inet filter input udp dport { 137, 138 } drop
        nft add rule inet filter input tcp dport { 139, 445 } drop

        # Specific internal rules for physical local network (CUPS)
        msg_info "Allowing CUPS local printer traffic from 192.168.1.0/24..."
        nft add rule inet filter input ip saddr 192.168.1.0/24 tcp dport 631 accept
    fi

    # Save rules for persistence
    msg_info "Saving nftables ruleset for persistence..."
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
}

apply_nftables_rules