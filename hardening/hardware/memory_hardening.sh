# shellcheck shell=bash
# Balanced kernel/process hardening helpers. Sourced; no action is performed here.

apply_process_memory_hardening() {
    local src="${SCRIPT_DIR:-${CURRENT_DIR:-.}}/hardening/hardware/99-security-advanced.conf"
    local dst="/etc/sysctl.d/90-dotfiles-kernel-hardening.conf"
    [[ -f "$src" ]] || { msg_error "Kernel hardening template not found: $src"; return 1; }
    if hardening_install_sysctl_template "$src" "$dst"; then
        msg_success "Balanced kernel hardening applied."
    else
        msg_warn "Kernel hardening application returned an error; inspect the output above."
        return 1
    fi
}

strict_shared_memory() {
    msg_warn "noexec on /dev/shm may break browsers, build systems, scientific tools and some containers."
    confirm_literal "Apply noexec,nosuid,nodev to /dev/shm and persist it in /etc/fstab?" "HARDEN-SHM" || return 0
    hardening_backup_path /etc/fstab || return 1

    if grep -Eq '^[^#]+[[:space:]]+/dev/shm[[:space:]]' /etc/fstab; then
        msg_warn "/dev/shm already has a persistent fstab entry; refusing to rewrite it automatically."
        grep -E '^[^#]+[[:space:]]+/dev/shm[[:space:]]' /etc/fstab || true
        return 0
    fi

    printf 'tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec 0 0\n' >>/etc/fstab
    mountpoint -q /dev/shm && mount -o remount,nodev,nosuid,noexec /dev/shm || true
}

strict_module_blacklist() {
    local dst="/etc/modprobe.d/90-dotfiles-uncommon-protocols.conf"
    msg_warn "Kernel protocol blacklists can affect specialized networking/software."
    confirm_literal "Block DCCP, RDS and TIPC kernel modules? SCTP is deliberately left available." "BLOCK-PROTOCOLS" || return 0
    hardening_backup_path "$dst" || return 1
    cat >"$dst" <<'EOF_BLACKLIST'
# Explicit strict profile selected in Dotfiles Hardening.
install dccp /bin/false
install rds /bin/false
install tipc /bin/false
EOF_BLACKLIST
    chmod 0644 "$dst"
}

security_resource_audit() {
    printf 'Kernel pointer restriction : %s\n' "$(sysctl -n kernel.kptr_restrict 2>/dev/null || printf unavailable)"
    printf 'dmesg restriction         : %s\n' "$(sysctl -n kernel.dmesg_restrict 2>/dev/null || printf unavailable)"
    printf 'ptrace scope              : %s\n' "$(sysctl -n kernel.yama.ptrace_scope 2>/dev/null || printf unavailable)"
    printf 'unprivileged BPF          : %s\n' "$(sysctl -n kernel.unprivileged_bpf_disabled 2>/dev/null || printf unavailable)"
    printf 'user namespaces           : %s\n' "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || printf kernel-default)"
    printf '/dev/shm                  : %s\n' "$(findmnt -no OPTIONS /dev/shm 2>/dev/null || printf unavailable)"
}
