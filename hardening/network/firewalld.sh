#!/usr/bin/env bash
set -euo pipefail

# Global default variables
SSH_PORT="${SSH_PORT:-22}"
ALLOWED_SERVICES=("80/tcp" "443/tcp")

apply_firewalld_rules() {
    msg_info "Starting network hardening with firewalld..."

    if ! command_exists firewall-cmd; then
        msg_error "firewalld is not installed. Please install it first."
        return 1
    fi

    # Security check: Ensure we don't drop existing SSH connections blindly
    if [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]; then
        msg_warn "SSH session detected. Ensuring port $SSH_PORT is authorized."
    fi

    systemctl enable --now firewalld &>/dev/null || true

    msg_info "Setting default zone to drop..."
    firewall-cmd --set-default-zone=drop &>/dev/null

    # Anti brute-force for SSH (Dynamic rich rule tied to SSH_PORT)
    msg_info "Configuring SSH anti brute-force protection on port ${SSH_PORT}..."
    firewall-cmd --permanent --add-rich-rule="rule port port=\"${SSH_PORT}\" protocol=\"tcp\" limit value=\"10/m\" accept" &>/dev/null

    # Public services and allowed ports
    for service in "${ALLOWED_SERVICES[@]}"; do
        msg_info "Allowing traffic on port ${service}..."
        firewall-cmd --permanent --add-port="${service}" &>/dev/null
    done

    # Hypervisor detection and rule injection
    local hypervisor
    hypervisor=$(detect_hypervisor || true)

    if [[ "$hypervisor" == "virtualbox" ]]; then
        msg_info "VirtualBox environment detected. Injecting network isolation egress policy into firewalld..."

        # Create an egress policy object for outbound traffic filtering
        firewall-cmd --permanent --new-policy=vbox-egress &>/dev/null || true
        firewall-cmd --permanent --policy=vbox-egress --add-ingress-zone=HOST &>/dev/null || true
        firewall-cmd --permanent --policy=vbox-egress --add-egress-zone=ANY &>/dev/null || true

        # 1. Allow outbound traffic to the VirtualBox NAT Gateway (10.0.2.2)
        firewall-cmd --permanent --policy=vbox-egress --add-rich-rule='rule family="ipv4" destination address="10.0.2.2" accept' &>/dev/null

        # 2. Deny outbound traffic to private local network ranges (RFC 1918)
        # Prevents the VM from scanning or accessing the host's local LAN
        firewall-cmd --permanent --policy=vbox-egress --add-rich-rule='rule family="ipv4" destination address="10.0.0.0/8" drop' &>/dev/null
        firewall-cmd --permanent --policy=vbox-egress --add-rich-rule='rule family="ipv4" destination address="172.16.0.0/12" drop' &>/dev/null
        firewall-cmd --permanent --policy=vbox-egress --add-rich-rule='rule family="ipv4" destination address="192.168.0.0/16" drop' &>/dev/null

        msg_success "VirtualBox firewalld network isolation policy applied."
    else
        msg_skip "Hypervisor is '$hypervisor'. Skipping VirtualBox-specific firewalld rules."

        # Specific internal rules for physical local network (CUPS)
        msg_info "Allowing CUPS printer traffic from 192.168.1.0/24..."
        firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="631" protocol="tcp" accept' &>/dev/null
    fi

    # Reload runtime configuration to apply permanent rules
    msg_info "Reloading firewalld configuration..."
    firewall-cmd --reload &>/dev/null

    msg_success "firewalld configured and applied successfully."

    print_separator
    echo -e "${cyanColour}=== FIREWALLD CURRENT STATUS ===${endColour}"
    firewall-cmd --list-all
    print_separator
}

apply_firewalld_rules