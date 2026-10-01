# shellcheck shell=bash
# Optional threat tooling from configured distribution repositories only.

setup_clamav_cli() {
    msg_info "Installing ClamAV from configured distribution repositories."
    local pre_svc
    for pre_svc in clamav-freshclam.service freshclam.service clamav-daemon.service clamd@scan.service clamd.service; do
        hardening_record_service "$pre_svc"
    done
    case "${OS_FAMILY:-}" in
        debian) install_packages clamav clamav-freshclam ;;
        arch|fedora|opensuse) install_packages clamav ;;
        *) msg_warn "ClamAV package mapping unavailable for this OS family."; return 1 ;;
    esac

    local svc updater_active=0
    for svc in clamav-freshclam.service freshclam.service clamav-daemon.service clamd@scan.service clamd.service; do
        service_exists "$svc" || continue
        hardening_record_service "$svc"
        systemctl enable --now "$svc" >/dev/null 2>&1 || msg_warn "Could not enable $svc; CLI scanning remains available."
        if [[ "$svc" == clamav-freshclam.service || "$svc" == freshclam.service ]]; then
            systemctl is-active --quiet "$svc" 2>/dev/null && updater_active=1
        fi
    done

    if command_exists freshclam && (( updater_active == 0 )); then
        freshclam || msg_warn "Initial freshclam update failed; package-managed updater can retry later."
    fi
}

setup_security_auditors() {
    msg_info "Installing available host-audit tools from configured repositories."
    install_packages lynis || true
    case "${OS_FAMILY:-}" in
        debian) install_packages chkrootkit rkhunter || true ;;
        arch|fedora|opensuse) install_packages rkhunter || true ;;
    esac
    msg_info "No third-party GUI, release binary or direct signature database is downloaded."
}

setup_threat_protection() {
    setup_clamav_cli || return 1
    setup_security_auditors || true
}
