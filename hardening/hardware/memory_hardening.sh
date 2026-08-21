#!/usr/bin/env bash
# =========================================================================
# MODULE: HARDWARE & MEMORY HARDENING
# =========================================================================

SYSCTL_DIR="/etc/sysctl.d"

# Process limits and core dumps restriction
configure_resource_limits() {
    msg_info "Configuring process limits and core dumps in /etc/security/limits.conf..."

    local limits_file="/etc/security/limits.conf"
    local -a limits=(
        "* soft nofile 65536"
        "* hard nofile 65536"
        "* soft nproc 32768"
        "* hard nproc 32768"
        "* hard core 0"
    )

    for line in "${limits[@]}"; do
        if ! grep -qsF -- "$line" "$limits_file"; then
            echo "$line" >> "$limits_file"
        fi
    done

    msg_success "Resource limits updated in $limits_file."
}

# Install and enable process accounting service
setup_process_accounting() {
    local package_manager="$1"

    msg_info "Setting up process accounting service (acct)..."

    case "$package_manager" in
        apt)
            apt install -y -qq acct &>/dev/null
            systemctl enable --now acct &>/dev/null
            msg_success "Process accounting (acct) installed and enabled."
            ;;
        pacman)
            if pacman -Si acct &>/dev/null; then
                pacman -S --needed --noconfirm acct &>/dev/null
                mkdir -p /var/account
                touch /var/account/pacct
                systemctl enable --now acct &>/dev/null
                msg_success "Process accounting (acct) installed and enabled."
            else
                msg_warn "Package 'acct' not found in pacman repositories. Skipping."
            fi
            ;;
        *)
            msg_warn "Unsupported package manager for acct setup."
            ;;
    esac
}

# Shared memory hardening in /etc/fstab (CIS Standard)
secure_shared_memory() {
    local fstab_file="/etc/fstab"
    local shm_entry="tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0"

    msg_info "Securing shared memory mount point (/dev/shm)..."

    if ! grep -qs "/dev/shm" "$fstab_file"; then
        echo "$shm_entry" >> "$fstab_file"
        msg_success "Added /dev/shm entry to $fstab_file with noexec,nosuid,nodev."
    else
        # If it exists but lacks our secure flags, sed could be used, but for safety we warn
        msg_info "Entry /dev/shm already present in $fstab_file (verify flags manually)."
    fi

    if mountpoint -q /dev/shm 2>/dev/null || [[ -d /dev/shm ]]; then
        mount -o remount,noexec,nosuid,nodev /dev/shm 2>/dev/null || true
        msg_success "Remounted /dev/shm with strict permissions."
    fi
}

# Disable SUID core dumps via sysctl
disable_suid_coredumps() {
    local sysctl_conf="$SYSCTL_DIR/99-disable-coredumps.conf"

    msg_info "Disabling SUID core dumps..."
    echo "fs.suid_dumpable = 0" > "$sysctl_conf"
    chmod 644 "$sysctl_conf"

    sysctl -p "$sysctl_conf" &>/dev/null || sysctl --system &>/dev/null
    msg_success "Disabled SUID core dumps via $sysctl_conf."
}

# Restrict dmesg kernel buffer
restrict_dmesg() {
    local sysctl_conf="$SYSCTL_DIR/99-dmesg-restrict.conf"

    msg_info "Restricting dmesg kernel buffer access to privileged users..."
    echo "kernel.dmesg_restrict = 1" > "$sysctl_conf"
    chmod 644 "$sysctl_conf"

    sysctl -p "$sysctl_conf" &>/dev/null || sysctl --system &>/dev/null
    msg_success "Restricted dmesg access (kernel.dmesg_restrict = 1)."
}

# Dynamic swap and VFS cache optimization
setup_dynamic_swap() {
    msg_info "Checking memory capacity and existing swap space..."

    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local current_swap_mb
    current_swap_mb=$(free -m | awk '/^Swap:/{print $2}')

    if [[ "$current_swap_mb" -gt 0 ]]; then
        msg_info "Active swap detected (${current_swap_mb}MB). Skipping swapfile allocation."
    elif [[ "$total_ram_mb" -le 2048 ]]; then
        msg_info "Low RAM detected (${total_ram_mb}MB). Creating a 2GB swapfile..."

        local swap_path="/swapfile"
        local swap_size_mb=2048

        if fallocate -l "${swap_size_mb}M" "$swap_path" 2>/dev/null || \
           dd if=/dev/zero of="$swap_path" bs=1M count="$swap_size_mb" status=none; then
            chmod 600 "$swap_path"
            mkswap "$swap_path" &>/dev/null
            swapon "$swap_path"

            if ! grep -q "$swap_path" /etc/fstab; then
                echo "$swap_path none swap defaults 0 0" >> /etc/fstab
            fi
            msg_success "Swapfile created and mounted at $swap_path."
        else
            msg_error "Failed to allocate swapfile."
            return 1
        fi
    else
        msg_info "Sufficient RAM available (${total_ram_mb}MB). No swap needed."
    fi

    msg_info "Optimizing virtual memory kernel parameters..."
    
    cat << 'EOF' > /etc/sysctl.d/99-swap-optimization.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
    chmod 644 /etc/sysctl.d/99-swap-optimization.conf
    sysctl -p /etc/sysctl.d/99-swap-optimization.conf &>/dev/null || sysctl --system &>/dev/null
    
    msg_success "Swappiness (10) and cache pressure (50) configured persistently."
}

# Module blacklisting and advanced protections
setup_memory_protections() {
    local hardware_dir="${CURRENT_DIR:-.}/hardware"
    local blacklist_file="/etc/modprobe.d/block-unneeded.conf"

    msg_info "Evaluating kernel module blacklist..."
    
    if [[ -f "${hardware_dir}/block-unneeded.conf" ]]; then
        cp "${hardware_dir}/block-unneeded.conf" "$blacklist_file"
        chmod 644 "$blacklist_file"
        msg_success "Copied custom module blacklist from ${hardware_dir}."
    else
        msg_info "Custom blacklist not found. Generating default security blacklist..."
        cat << 'EOF' > "$blacklist_file"
# Block uncommon network protocols (Reduces attack surface)
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
# Block uncommon filesystems (Prevents malicious USB mounts)
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
EOF
        chmod 644 "$blacklist_file"
        msg_success "Default kernel module blacklist applied."
    fi

    if [[ -f "${hardware_dir}/99-security-advanced.conf" ]]; then
        msg_info "Deploying 99-security-advanced.conf to /etc/sysctl.d/..."
        cp "${hardware_dir}/99-security-advanced.conf" /etc/sysctl.d/99-security-advanced.conf
        chmod 644 /etc/sysctl.d/99-security-advanced.conf
        
        sysctl --system &>/dev/null || true
        msg_success "Advanced sysctl hardening reloaded successfully."
    fi
}

# Main wrapper function
apply_process_memory_hardening() {
    local package_manager="$1"

    msg_info "=== STARTING HARDWARE & MEMORY HARDENING ==="

    configure_resource_limits
    print_separator

    setup_process_accounting "$package_manager"
    print_separator

    secure_shared_memory
    print_separator

    disable_suid_coredumps
    print_separator

    restrict_dmesg
    print_separator

    setup_dynamic_swap
    print_separator

    setup_memory_protections 

    msg_success "Hardware and memory hardening applied successfully."
}