#!/usr/bin/env bash
set -Eeuo pipefail

# server-init.sh
# One-file Ubuntu Server bootstrap + hardening.
#
# Designed for:
#   curl -fsSL https://raw.githubusercontent.com/sempitern0/dotfiles/<COMMIT>/server-init.sh \
#     | sudo bash -s -- apply --profile base --yes
#
# Design goals:
#   - Secure by default, but avoid locking the operator out.
#   - Idempotent and conservative: no UFW reset, no firewall flush.
#   - SSH snippets are syntax-checked before reload.
#   - Stronger/higher-risk hardening is opt-in.
#   - Service exposure is controlled by profile + explicit ports.
#   - Backups are created before managed configuration changes.
#
# Profiles:
#   base      Ubuntu administration/security baseline.
#   web       base + HTTP/HTTPS firewall access.
#   docker    base + Docker Engine from the official Docker repository.
#   homelab   base + HTTP/HTTPS + WireGuard tools.
#
# Actions:
#   plan      Show intended changes without modifying the host.
#   apply     Apply the selected profile.
#   check     Inspect detected state without modifying the host.
#   status    Print the resulting security/service status.
#   help      Show usage.

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

# Do not let environment-provided startup hooks alter the script.
unset BASH_ENV ENV CDPATH PYTHONPATH PERL5LIB RUBYOPT NODE_OPTIONS 2>/dev/null || true
export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
umask 077

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------

ACTION="${1:-plan}"
PROFILE="base"
YES="false"
SSH_PORT="22"
SSH_PASSWORD_AUTH="auto"     # auto|on|off
ROOT_SSH="auto"               # auto|on|prohibit-password|off
SSH_ALLOW_FROM=""             # comma-separated CIDRs/IPs
EXTRA_TCP_PORTS=""
EXTRA_UDP_PORTS=""
ADMIN_USER=""
ADMIN_KEY_FILE=""
TIMEZONE=""
FIREWALL_BACKEND="auto"       # auto|ufw|none
ENABLE_FAIL2BAN="true"
ENABLE_AUDITD="true"
ENABLE_JOURNAL_PERSISTENCE="true"
DISABLE_UNUSED_SERVICES="true"
STRICT_KERNEL="false"
SECURE_SHARED_MEMORY="false"
STRICT_UMASK="true"
INSTALL_LYNIS="false"
INSTALL_CLAMAV="false"
INSTALL_DOCKER="false"
INSTALL_WIREGUARD="false"

BACKUP_ROOT="/var/backups/server-init"
STATE_DIR="/var/lib/server-init"
LOCK_DIR="/run/server-init"
SSH_DROPIN="/etc/ssh/sshd_config.d/99-server-init.conf"
FAIL2BAN_DROPIN="/etc/fail2ban/jail.d/99-server-init.local"
SYSCTL_DROPIN="/etc/sysctl.d/99-server-init.conf"
STRICT_SYSCTL_DROPIN="/etc/sysctl.d/99-server-init-strict.conf"
STRICT_MODPROBE_DROPIN="/etc/modprobe.d/99-server-init.conf"
UMASK_DROPIN="/etc/profile.d/99-server-init-umask.sh"
JOURNAL_DROPIN="/etc/systemd/journald.conf.d/99-server-init.conf"
SHM_FSTAB_MARKER="# server-init: secure /dev/shm"
FIREWALL_SELECTED="none"
KEY_ADMIN_USER=""

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
PURPLE=$'\033[0;35m'
CYAN=$'\033[0;36m'
GRAY=$'\033[0;90m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

log()     { printf '%b[%s]%b %s\n' "$CYAN" INFO "$RESET" "$*" >&2; }
ok()      { printf '%b[%s]%b %s\n' "$GREEN" OK "$RESET" "$*" >&2; }
warn()    { printf '%b[%s]%b %s\n' "$YELLOW" WARN "$RESET" "$*" >&2; }
error()   { printf '%b[%s]%b %s\n' "$RED" ERROR "$RESET" "$*" >&2; }
debug()   { printf '%b[%s]%b %s\n' "$GRAY" DEBUG "$RESET" "$*" >&2; }
section() { printf '\n%b==> %s%b\n' "$BOLD" "$*" "$RESET" >&2; }

fatal() {
    error "$*"
    exit 1
}

has() {
    command -v "$1" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Generic safety helpers
# -----------------------------------------------------------------------------

require_root() {
    [[ $EUID -eq 0 ]] || fatal "Run as root (example: sudo bash server-init.sh ...)."
}

require_linux() {
    [[ "$(uname -s)" == "Linux" ]] || fatal "This script only supports Linux."
}

require_ubuntu() {
    [[ -r /etc/os-release ]] || fatal "/etc/os-release not found."
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || fatal "Ubuntu is required. Detected: ${ID:-unknown}."

    case "${VERSION_ID:-}" in
        22.04|24.04|26.04) ;;
        *) warn "Untested Ubuntu release ${VERSION_ID:-unknown}; continuing conservatively." ;;
    esac
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    (( $1 >= 1 && $1 <= 65535 ))
}

validate_username() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}\$?$ ]]
}

validate_ip_or_cidr() {
    local value="$1"
    [[ "$value" =~ ^[0-9a-fA-F:.]+(/[0-9]{1,3})?$ ]] || return 1
    has python3 || return 0
    python3 - "$value" <<'PY'
import ipaddress
import sys
try:
    ipaddress.ip_network(sys.argv[1], strict=False)
except ValueError:
    raise SystemExit(1)
PY
}

ensure_apt_noninteractive() {
    export DEBIAN_FRONTEND=noninteractive
}

apt_update() {
    ensure_apt_noninteractive
    apt-get update
}

apt_install() {
    ensure_apt_noninteractive
    apt-get install -y --no-install-recommends "$@"
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

backup_file() {
    local path="$1"
    [[ -e "$path" ]] || return 0

    local rel="${path#/}"
    local destination="${BACKUP_CURRENT_DIR}/${rel}"
    mkdir -p "$(dirname "$destination")"
    cp -a -- "$path" "$destination"
}

backup_targets() {
    section "Creating pre-change backup"
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    BACKUP_CURRENT_DIR="${BACKUP_ROOT}/${stamp}"
    mkdir -p "$BACKUP_CURRENT_DIR"
    chmod 700 "$BACKUP_CURRENT_DIR"

    local targets=(
        /etc/ssh
        /etc/ufw
        /etc/fail2ban
        /etc/sysctl.d
        /etc/modprobe.d
        /etc/security/limits.conf
        /etc/login.defs
        /etc/profile.d
        /etc/apt/apt.conf.d
        /etc/systemd/journald.conf.d
        /etc/docker
        /etc/fstab
    )

    local target
    for target in "${targets[@]}"; do
        backup_file "$target"
    done

    printf '%s\n' "$BACKUP_CURRENT_DIR" > "$STATE_DIR/last-backup"
    chmod 600 "$STATE_DIR/last-backup"
    ok "Backup stored in $BACKUP_CURRENT_DIR"
}

write_managed_file() {
    local path="$1"
    local mode="$2"
    local tmp
    tmp="$(mktemp)"

    cat > "$tmp"

    if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then
        chmod "$mode" "$path"
        rm -f "$tmp"
        return 0
    fi

    if [[ -e "$path" ]]; then
        backup_file "$path"
    fi

    install -D -m "$mode" "$tmp" "$path"
    rm -f "$tmp"
}

acquire_lock() {
    mkdir -p "$LOCK_DIR"
    chmod 755 "$LOCK_DIR"

    if has flock; then
        exec 9>"$LOCK_DIR/lock"
        flock -n 9 || fatal "Another server-init instance is already running."
    else
        warn "flock is unavailable; continuing without an execution lock."
    fi
}

command_failure_report() {
    local line=$1
    local code=$2
    error "Command failed at line $line with exit code $code."
    warn "The latest pre-change backup is recorded at: ${BACKUP_CURRENT_DIR:-unknown}"
}

trap 'command_failure_report "$LINENO" "$?"' ERR
trap 'printf "\n" >&2; warn "Interrupted."; exit 130' INT TERM

# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

usage() {
    cat >&2 <<EOF
$SCRIPT_NAME $SCRIPT_VERSION

Usage:
  $SCRIPT_NAME plan [options]
  $SCRIPT_NAME apply [options]
  $SCRIPT_NAME check
  $SCRIPT_NAME status
  $SCRIPT_NAME help

Profiles:
  base       Security baseline only.
  web        base + TCP/80 and TCP/443.
  docker     base + Docker Engine from Docker's official repository.
  homelab    base + TCP/80, TCP/443 + WireGuard tools.

Important options:
  --yes                         Non-interactive apply confirmation.
  --ssh-port PORT               SSH port protected by the firewall/Fail2ban.
                                It must match the port already configured in sshd;
                                this script does not silently remove other Port entries.
  --ssh-password-auth auto|on|off
                                auto disables password auth only when a usable
                                public-key administrator is detected.
  --root-ssh auto|on|prohibit-password|off
                                auto chooses a lockout-safe setting.
  --ssh-allow-from LIST         Comma-separated IPs/CIDRs allowed to SSH.
  --admin-user USER             Create/prepare an admin user with sudo access.
  --admin-key-file FILE         Install the first public key from FILE for admin.
  --timezone ZONE               Set timezone, e.g. Europe/Madrid or UTC.
  --firewall auto|ufw|none      Firewall backend. Default: auto.
  --tcp-ports LIST              Extra TCP ports to allow, e.g. 8080,9000.
  --udp-ports LIST              Extra UDP ports to allow, e.g. 51820,5353.

Hardening controls:
  --strict-kernel               Enable stronger kernel/filesystem restrictions.
  --secure-shared-memory        Persist nodev,nosuid,noexec on /dev/shm when safe.
  --no-umask                    Do not install global umask 027.
  --keep-services               Do not disable common desktop-only services.
  --disable-fail2ban            Skip Fail2ban.
  --disable-auditd              Skip auditd.
  --disable-journal-persistence Skip persistent journald configuration.

Optional software:
  --lynis                       Install Lynis for auditing.
  --clamav                      Install ClamAV/freshclam.
  --docker                      Install Docker regardless of profile.
  --wireguard                   Install WireGuard tools regardless of profile.

Examples:
  curl -fsSL https://raw.githubusercontent.com/sempitern0/dotfiles/<COMMIT>/server-init.sh \\
    | sudo bash -s -- apply --profile base --yes

  curl -fsSL https://raw.githubusercontent.com/sempitern0/dotfiles/<COMMIT>/server-init.sh \\
    | sudo bash -s -- apply --profile web --admin-user deploy --admin-key-file /root/deploy.pub --yes

  sudo bash server-init.sh plan --profile homelab
  sudo bash server-init.sh check
  sudo bash server-init.sh status
EOF
}

parse_csv_ports() {
    local list="$1"
    if [[ -z "$list" ]]; then
        return 0
    fi
    local value
    IFS=',' read -r -a values <<< "$list"
    for value in "${values[@]}"; do
        value="${value//[[:space:]]/}"
        validate_port "$value" || fatal "Invalid port: $value"
    done
}

parse_allowlist() {
    if [[ -z "$SSH_ALLOW_FROM" ]]; then
        return 0
    fi
    local value
    IFS=',' read -r -a values <<< "$SSH_ALLOW_FROM"
    for value in "${values[@]}"; do
        value="${value//[[:space:]]/}"
        validate_ip_or_cidr "$value" || fatal "Invalid SSH allow-list value: $value"
    done
}

parse_args() {
    ACTION="${1:-plan}"
    case "$ACTION" in
        plan|apply|check|status|help|-h|--help) ;;
        *) fatal "Unknown action '$ACTION'. Use plan/apply/check/status/help." ;;
    esac

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)
                [[ $# -ge 2 ]] || fatal "--profile requires a value."
                PROFILE="$2"
                shift 2
                ;;
            --yes|-y)
                YES="true"
                shift
                ;;
            --ssh-port)
                [[ $# -ge 2 ]] || fatal "--ssh-port requires a value."
                SSH_PORT="$2"
                shift 2
                ;;
            --ssh-password-auth)
                [[ $# -ge 2 ]] || fatal "--ssh-password-auth requires a value."
                SSH_PASSWORD_AUTH="$2"
                shift 2
                ;;
            --root-ssh)
                [[ $# -ge 2 ]] || fatal "--root-ssh requires a value."
                ROOT_SSH="$2"
                shift 2
                ;;
            --ssh-allow-from)
                [[ $# -ge 2 ]] || fatal "--ssh-allow-from requires a value."
                SSH_ALLOW_FROM="$2"
                shift 2
                ;;
            --admin-user)
                [[ $# -ge 2 ]] || fatal "--admin-user requires a value."
                ADMIN_USER="$2"
                shift 2
                ;;
            --admin-key-file)
                [[ $# -ge 2 ]] || fatal "--admin-key-file requires a value."
                ADMIN_KEY_FILE="$2"
                shift 2
                ;;
            --timezone)
                [[ $# -ge 2 ]] || fatal "--timezone requires a value."
                TIMEZONE="$2"
                shift 2
                ;;
            --firewall)
                [[ $# -ge 2 ]] || fatal "--firewall requires a value."
                FIREWALL_BACKEND="$2"
                shift 2
                ;;
            --tcp-ports)
                [[ $# -ge 2 ]] || fatal "--tcp-ports requires a value."
                EXTRA_TCP_PORTS="$2"
                shift 2
                ;;
            --udp-ports)
                [[ $# -ge 2 ]] || fatal "--udp-ports requires a value."
                EXTRA_UDP_PORTS="$2"
                shift 2
                ;;
            --strict-kernel) STRICT_KERNEL="true"; shift ;;
            --secure-shared-memory) SECURE_SHARED_MEMORY="true"; shift ;;
            --no-umask) STRICT_UMASK="false"; shift ;;
            --keep-services) DISABLE_UNUSED_SERVICES="false"; shift ;;
            --disable-fail2ban) ENABLE_FAIL2BAN="false"; shift ;;
            --disable-auditd) ENABLE_AUDITD="false"; shift ;;
            --disable-journal-persistence) ENABLE_JOURNAL_PERSISTENCE="false"; shift ;;
            --lynis) INSTALL_LYNIS="true"; shift ;;
            --clamav) INSTALL_CLAMAV="true"; shift ;;
            --docker) INSTALL_DOCKER="true"; shift ;;
            --wireguard) INSTALL_WIREGUARD="true"; shift ;;
            -h|--help) usage; exit 0 ;;
            *) fatal "Unknown option '$1'." ;;
        esac
    done

    case "$PROFILE" in
        base|web|docker|homelab) ;;
        *) fatal "Invalid profile '$PROFILE'." ;;
    esac

    case "$SSH_PASSWORD_AUTH" in auto|on|off) ;; *) fatal "Invalid --ssh-password-auth value." ;; esac
    case "$ROOT_SSH" in auto|on|prohibit-password|off) ;; *) fatal "Invalid --root-ssh value." ;; esac
    case "$FIREWALL_BACKEND" in auto|ufw|none) ;; *) fatal "Invalid --firewall value." ;; esac

    validate_port "$SSH_PORT" || fatal "Invalid SSH port: $SSH_PORT"
    parse_csv_ports "$EXTRA_TCP_PORTS"
    parse_csv_ports "$EXTRA_UDP_PORTS"
    parse_allowlist

    if [[ -n "$ADMIN_USER" ]]; then
        validate_username "$ADMIN_USER" || fatal "Invalid admin username '$ADMIN_USER'."
    fi

    if [[ -n "$ADMIN_KEY_FILE" && ! -f "$ADMIN_KEY_FILE" ]]; then
        fatal "Admin key file not found: $ADMIN_KEY_FILE"
    fi

    if [[ "$PROFILE" == docker ]]; then
        INSTALL_DOCKER="true"
    fi
    if [[ "$PROFILE" == homelab ]]; then
        INSTALL_WIREGUARD="true"
    fi
    return 0
}

# -----------------------------------------------------------------------------
# State / detection
# -----------------------------------------------------------------------------

is_ssh_session() {
    [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]
}

user_has_authorized_key() {
    local user="$1"
    local home
    home="$(getent passwd "$user" | cut -d: -f6)"
    [[ -n "$home" ]] || return 1

    local file="$home/.ssh/authorized_keys"
    [[ -f "$file" ]] || return 1
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        {
            # Accept normal public-key lines. Lines with SSH options are also
            # accepted conservatively by looking for a known key algorithm.
            if ($0 ~ /(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519|sk-ecdsa-sha2-nistp256@openssh.com)/) found=1
        }
        END { exit(found ? 0 : 1) }
    ' "$file"
}

find_key_admin_user() {
    if [[ -n "$ADMIN_USER" ]] && id "$ADMIN_USER" >/dev/null 2>&1 && user_is_privileged_admin "$ADMIN_USER" && user_has_authorized_key "$ADMIN_USER"; then
        KEY_ADMIN_USER="$ADMIN_USER"
        return 0
    fi

    if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER:-}" != root ]] && id "$SUDO_USER" >/dev/null 2>&1; then
        if user_is_privileged_admin "$SUDO_USER" && user_has_authorized_key "$SUDO_USER"; then
            KEY_ADMIN_USER="$SUDO_USER"
            return 0
        fi
    fi

    local user _ uid _ _ home shell
    while IFS=: read -r user _ uid _ _ home shell; do
        [[ "$uid" =~ ^[0-9]+$ ]] || continue
        (( uid >= 1000 )) || continue
        (( uid < 65534 )) || continue
        [[ "$user" != nobody ]] || continue
        [[ "$shell" =~ /(bash|zsh|fish|sh)$ ]] || continue
        if user_is_privileged_admin "$user" && user_has_authorized_key "$user"; then
            KEY_ADMIN_USER="$user"
            return 0
        fi
    done < /etc/passwd

    KEY_ADMIN_USER=""
    return 1
}

root_has_authorized_key() {
    user_has_authorized_key root
}

user_is_privileged_admin() {
    local user="$1"

    if [[ "$(id -u "$user" 2>/dev/null || printf 99999)" -eq 0 ]]; then
        return 0
    fi

    # Ubuntu's normal delegated-administration path is membership of sudo.
    if id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -Fxq sudo; then
        return 0
    fi

    return 1
}

show_detected() {
    section "Detected host"
    # shellcheck disable=SC1091
    source /etc/os-release
    printf 'OS:                 %s %s\n' "${NAME:-Ubuntu}" "${VERSION_ID:-}" >&2
    printf 'Kernel:              %s\n' "$(uname -r)" >&2
    printf 'Architecture:        %s\n' "$(dpkg --print-architecture 2>/dev/null || uname -m)" >&2
    printf 'Hostname:            %s\n' "$(hostnamectl --static 2>/dev/null || hostname)" >&2
    printf 'SSH session:         %s\n' "$(is_ssh_session && echo remote || echo local)" >&2
    printf 'SSH service:         %s\n' "$(systemctl is-active ssh.service 2>/dev/null || systemctl is-active sshd.service 2>/dev/null || echo inactive)" >&2
    printf 'UFW:                 %s\n' "$(ufw status 2>/dev/null | head -n1 || echo unavailable)" >&2
    printf 'AppArmor:            %s\n' "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null || echo unknown)" >&2
    printf 'Fail2ban:            %s\n' "$(systemctl is-active fail2ban.service 2>/dev/null || echo inactive)" >&2
    printf 'Auditd:              %s\n' "$(systemctl is-active auditd.service 2>/dev/null || echo inactive)" >&2
    printf 'Chrony:              %s\n' "$(systemctl is-active chrony.service 2>/dev/null || echo inactive)" >&2
    printf 'Docker:              %s\n' "$(systemctl is-active docker.service 2>/dev/null || echo inactive)" >&2
    printf 'Key admin detected:  %s\n' "${KEY_ADMIN_USER:-none}" >&2
    printf 'Listening sockets:\n' >&2
    ss -lntup 2>/dev/null || true
}

show_plan() {
    section "Plan"
    cat >&2 <<EOF
Profile:                 $PROFILE
SSH port:                $SSH_PORT
SSH password auth:      $SSH_PASSWORD_AUTH
Root SSH policy:         $ROOT_SSH
Firewall:                $FIREWALL_BACKEND
Strict kernel:           $STRICT_KERNEL
Secure /dev/shm:         $SECURE_SHARED_MEMORY
Global umask 027:        $STRICT_UMASK
Fail2ban:                $ENABLE_FAIL2BAN
Auditd:                  $ENABLE_AUDITD
Persistent journald:     $ENABLE_JOURNAL_PERSISTENCE
Disable unused services:$DISABLE_UNUSED_SERVICES
Docker:                  $INSTALL_DOCKER
WireGuard:               $INSTALL_WIREGUARD
Lynis:                   $INSTALL_LYNIS
ClamAV:                  $INSTALL_CLAMAV
EOF

    cat >&2 <<'EOF'
Baseline changes:
  - Upgrade installed Ubuntu packages and install administration/security tools.
  - Ensure OpenSSH server exists and deploy a dedicated sshd drop-in.
  - Disable root SSH and/or password SSH only when the access state is safe.
  - Enable UFW without resetting or flushing existing firewall rules.
  - Enable automatic security updates.
  - Enable AppArmor and time synchronization where available.
  - Configure Fail2ban for SSH.
  - Persist system logs and optionally enable auditd.
  - Apply conservative network/kernel sysctl hardening.

Explicitly avoided in the baseline:
  - Disabling IPv6 globally.
  - Disabling ICMP echo globally.
  - Disabling TCP SACK.
  - Flushing nftables/iptables.
  - Replacing existing DNS configuration.
  - Forcing all AppArmor profiles into enforce mode.
  - Automatically disabling arbitrary installed services.
EOF

    case "$PROFILE" in
        web)
            echo 'Profile addition: allow TCP/80 and TCP/443.' >&2 ;;
        docker)
            echo 'Profile addition: install Docker Engine + Compose plugin.' >&2 ;;
        homelab)
            echo 'Profile additions: allow TCP/80, TCP/443 and install WireGuard tools.' >&2 ;;
    esac
}

# -----------------------------------------------------------------------------
# Admin account
# -----------------------------------------------------------------------------

prepare_admin() {
    section "Administrative access"

    if [[ -z "$ADMIN_USER" ]]; then
        find_key_admin_user || true
        if [[ -n "$KEY_ADMIN_USER" ]]; then
            log "Detected existing key-based administrator: $KEY_ADMIN_USER"
        else
            warn "No non-root user with a usable authorized_keys entry was detected."
        fi
        return 0
    fi

    if ! id "$ADMIN_USER" >/dev/null 2>&1; then
        log "Creating administrative user: $ADMIN_USER"
        useradd --create-home --shell /bin/bash --groups sudo "$ADMIN_USER"
    else
        log "Administrative user already exists: $ADMIN_USER"
        usermod --append --groups sudo "$ADMIN_USER"
    fi

    passwd -l "$ADMIN_USER" >/dev/null 2>&1 || true

    local home
    home="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
    [[ -n "$home" ]] || fatal "Could not determine home directory for $ADMIN_USER"

    install -d -m 0700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$home/.ssh"

    if [[ -n "$ADMIN_KEY_FILE" ]]; then
        log "Validating administrator public key."
        ssh-keygen -l -f "$ADMIN_KEY_FILE" >/dev/null 2>&1 || fatal "Invalid public key file: $ADMIN_KEY_FILE"
        local first_key
        first_key="$(awk 'NF && $1 !~ /^#/ {print; exit}' "$ADMIN_KEY_FILE")"
        [[ -n "$first_key" ]] || fatal "No public key found in $ADMIN_KEY_FILE"

        touch "$home/.ssh/authorized_keys"
        chmod 600 "$home/.ssh/authorized_keys"
        chown "$ADMIN_USER:$ADMIN_USER" "$home/.ssh/authorized_keys"
        grep -qxF "$first_key" "$home/.ssh/authorized_keys" 2>/dev/null || printf '%s\n' "$first_key" >> "$home/.ssh/authorized_keys"
        chown -R "$ADMIN_USER:$ADMIN_USER" "$home/.ssh"
        KEY_ADMIN_USER="$ADMIN_USER"
        ok "Public key installed for $ADMIN_USER"
    else
        if user_has_authorized_key "$ADMIN_USER"; then
            KEY_ADMIN_USER="$ADMIN_USER"
        else
            warn "--admin-user was supplied without --admin-key-file and no usable key was found."
        fi
    fi
}

# -----------------------------------------------------------------------------
# Packages / updates
# -----------------------------------------------------------------------------

install_base_packages() {
    section "Base packages"
    apt_update
    apt-get upgrade -y

    local packages=(
        ca-certificates curl wget git vim-tiny tmux jq rsync unzip zip tar gzip
        btop htop iotop lsof ncdu socat acl ripgrep eza
        dnsutils iproute2 iputils-ping net-tools psmisc
        openssh-server ufw fail2ban unattended-upgrades apt-listchanges
        chrony apparmor apparmor-utils auditd audispd-plugins
    )

    apt_install "${packages[@]}"
    ok "Base packages installed."
}

configure_updates() {
    section "Automatic security updates"

    apt_install unattended-upgrades apt-listchanges

    write_managed_file /etc/apt/apt.conf.d/20auto-upgrades 0644 <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    write_managed_file /etc/apt/apt.conf.d/52server-init-unattended 0644 <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

    systemctl enable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    systemctl enable --now unattended-upgrades.service 2>/dev/null || true
    ok "Automatic security updates configured without automatic reboot."
}

# -----------------------------------------------------------------------------
# SSH hardening
# -----------------------------------------------------------------------------

ssh_effective_value() {
    local query="$1"
    sshd -T 2>/dev/null | awk -v key="$query" '$1 == key {print $2; exit}'
}

calculate_ssh_policy() {
    find_key_admin_user || true

    local safe_key_admin="false"
    if [[ -n "$KEY_ADMIN_USER" ]] && [[ "$KEY_ADMIN_USER" != root ]]; then
        safe_key_admin="true"
    fi

    local root_key="false"
    if root_has_authorized_key; then
        root_key="true"
    fi

    # Password authentication:
    #   auto = disable only if we have a non-root key admin.
    case "$SSH_PASSWORD_AUTH" in
        on) SSH_PASSWORD_EFFECTIVE="yes" ;;
        off) SSH_PASSWORD_EFFECTIVE="no" ;;
        auto)
            if [[ "$safe_key_admin" == true ]]; then
                SSH_PASSWORD_EFFECTIVE="no"
            else
                SSH_PASSWORD_EFFECTIVE="yes"
                if is_ssh_session; then
                    warn "Keeping SSH password authentication enabled: no non-root key administrator was detected."
                    warn "After installing a key, rerun with --ssh-password-auth auto (or --off explicitly)."
                fi
            fi
            ;;
    esac

    # Root SSH:
    #   auto = fully disable root SSH when a non-root key admin exists.
    #          otherwise keep root key-only access when root has a key.
    #          otherwise preserve existing root SSH configuration to avoid lockout.
    case "$ROOT_SSH" in
        on) ROOT_SSH_EFFECTIVE="yes" ;;
        off)
            [[ "$safe_key_admin" == true ]] || fatal "--root-ssh off requires a non-root key administrator."
            ROOT_SSH_EFFECTIVE="no"
            ;;
        prohibit-password) ROOT_SSH_EFFECTIVE="prohibit-password" ;;
        auto)
            if [[ "$safe_key_admin" == true ]]; then
                ROOT_SSH_EFFECTIVE="no"
            elif [[ "$root_key" == true ]]; then
                ROOT_SSH_EFFECTIVE="prohibit-password"
            else
                ROOT_SSH_EFFECTIVE="$(ssh_effective_value permitrootlogin || printf 'prohibit-password')"
                case "$ROOT_SSH_EFFECTIVE" in yes|no|prohibit-password|forced-commands-only) ;; *) ROOT_SSH_EFFECTIVE="prohibit-password" ;; esac
                if [[ "$ROOT_SSH_EFFECTIVE" == yes ]] && is_ssh_session; then
                    warn "No proven key-based admin access; preserving current root SSH policy until an admin key exists."
                fi
            fi
            ;;
    esac

    if [[ "$SSH_PASSWORD_EFFECTIVE" == no && "$ROOT_SSH_EFFECTIVE" == yes ]]; then
        warn "Root SSH password access would remain while all passwords are disabled; switching root policy to prohibit-password."
        ROOT_SSH_EFFECTIVE="prohibit-password"
    fi
}

configure_ssh() {
    section "SSH hardening"

    apt_install openssh-server openssh-client
    mkdir -p /etc/ssh/sshd_config.d
    chmod 755 /etc/ssh/sshd_config.d

    calculate_ssh_policy

    if [[ "$ROOT_SSH_EFFECTIVE" == no && -z "$KEY_ADMIN_USER" ]]; then
        fatal "Refusing to disable root SSH without a detected non-root key administrator."
    fi

    local challenge="no"
    if [[ "$SSH_PASSWORD_EFFECTIVE" == yes ]]; then
        challenge="yes"
    fi

    write_managed_file "$SSH_DROPIN" 0600 <<EOF
# Managed by $SCRIPT_NAME $SCRIPT_VERSION
# Do not edit this file manually; change server-init arguments instead.

PermitRootLogin $ROOT_SSH_EFFECTIVE
PubkeyAuthentication yes
PasswordAuthentication $SSH_PASSWORD_EFFECTIVE
KbdInteractiveAuthentication $challenge
PermitEmptyPasswords no
MaxAuthTries 4
LoginGraceTime 30
MaxSessions 10
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
GatewayPorts no
PermitTunnel no
ClientAliveInterval 300
ClientAliveCountMax 2
StrictModes yes
EOF

    ssh-keygen -A >/dev/null 2>&1 || true
    mkdir -p /run/sshd
    chmod 755 /run/sshd

    log "Validating effective OpenSSH configuration."
    sshd -t
    ok "sshd configuration syntax is valid."

    local ssh_service="ssh.service"
    if ! systemctl list-unit-files ssh.service >/dev/null 2>&1; then
        ssh_service="sshd.service"
    fi

    systemctl enable "$ssh_service"
    systemctl reload "$ssh_service"

    log "Effective SSH policy: PermitRootLogin=$(ssh_effective_value permitrootlogin), PasswordAuthentication=$(ssh_effective_value passwordauthentication), PubkeyAuthentication=$(ssh_effective_value pubkeyauthentication)"
}

# -----------------------------------------------------------------------------
# Firewall
# -----------------------------------------------------------------------------

ufw_rule_present() {
    local pattern="$1"
    ufw status | grep -Fq -- "$pattern"
}

ufw_allow_port() {
    local port="$1" proto="$2" comment_text="$3"
    local display="${port}/${proto}"
    if ! ufw_rule_present "$display"; then
        ufw allow "$display" comment "$comment_text"
    fi
}

ufw_limit_port() {
    local port="$1"
    local display="${port}/tcp"
    if ! ufw_rule_present "$display"; then
        ufw limit "$display" comment "server-init SSH brute-force limit"
    fi
}

validate_ssh_listener_port() {
    local effective_ports
    effective_ports="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' | sort -nu | tr '\n' ' ' | sed 's/[[:space:]]*$//' || true)"

    [[ -n "$effective_ports" ]] || fatal "Could not determine the effective sshd listening port(s)."

    if ! printf '%s\n' "$effective_ports" | tr ' ' '\n' | grep -Fxq "$SSH_PORT"; then
        fatal "--ssh-port $SSH_PORT does not match an effective sshd Port. sshd currently reports: $effective_ports. Change sshd first, then rerun server-init."
    fi

    log "Verified SSH listener port $SSH_PORT is present in sshd's effective configuration."
}

configure_ufw() {
    section "Firewall"

    apt_install ufw

    # Never reset or flush an existing firewall.
    # If another firewall service is currently enforcing policy, leave it alone.
    if systemctl is-active --quiet firewalld.service 2>/dev/null; then
        if [[ "$FIREWALL_BACKEND" == ufw ]]; then
            fatal "firewalld is active; refusing to enable a competing UFW firewall."
        fi
        warn "firewalld is active; leaving it untouched instead of enabling UFW."
        FIREWALL_SELECTED="firewalld"
        return 0
    fi
    if systemctl is-active --quiet nftables.service 2>/dev/null; then
        if [[ "$FIREWALL_BACKEND" == ufw ]]; then
            fatal "nftables.service is active; refusing to enable a competing UFW firewall."
        fi
        warn "nftables.service is active; leaving it untouched instead of enabling UFW."
        FIREWALL_SELECTED="nftables"
        return 0
    fi

    FIREWALL_SELECTED="ufw"

    # SSH rule must exist before the default deny is applied.
    if [[ -n "$SSH_ALLOW_FROM" ]]; then
        local source
        IFS=',' read -r -a sources <<< "$SSH_ALLOW_FROM"
        for source in "${sources[@]}"; do
            source="${source//[[:space:]]/}"
            if ! ufw status | grep -Fq "${source}"; then
                ufw limit from "$source" to any port "$SSH_PORT" proto tcp comment "server-init SSH"
            fi
        done
    else
        ufw_limit_port "$SSH_PORT"
    fi

    ufw default deny incoming
    ufw default allow outgoing
    ufw default deny routed
    ufw logging low

    case "$PROFILE" in
        web|homelab)
            ufw_allow_port 80 tcp "server-init HTTP"
            ufw_allow_port 443 tcp "server-init HTTPS"
            ;;
    esac

    if [[ "$PROFILE" == homelab ]]; then
        ufw_allow_port 51820 udp "server-init WireGuard"
    fi

    if [[ -n "$EXTRA_TCP_PORTS" ]]; then
        local tcp_port
        IFS=',' read -r -a tcp_values <<< "$EXTRA_TCP_PORTS"
        for tcp_port in "${tcp_values[@]}"; do
            tcp_port="${tcp_port//[[:space:]]/}"
            ufw_allow_port "$tcp_port" tcp "server-init custom TCP"
        done
    fi

    if [[ -n "$EXTRA_UDP_PORTS" ]]; then
        local udp_port
        IFS=',' read -r -a udp_values <<< "$EXTRA_UDP_PORTS"
        for udp_port in "${udp_values[@]}"; do
            udp_port="${udp_port//[[:space:]]/}"
            ufw_allow_port "$udp_port" udp "server-init custom UDP"
        done
    fi

    ufw --force enable
    ok "UFW enabled without resetting existing rules."
    ufw status verbose >&2
}

select_firewall() {
    case "$FIREWALL_BACKEND" in
        none)
            FIREWALL_SELECTED="none"
            warn "Firewall configuration explicitly disabled via --firewall none."
            ;;
        auto|ufw)
            configure_ufw
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Fail2ban
# -----------------------------------------------------------------------------

configure_fail2ban() {
    if [[ "$ENABLE_FAIL2BAN" != true ]]; then
        warn "Fail2ban disabled by option."
        return 0
    fi

    section "Fail2ban"
    apt_install fail2ban
    mkdir -p /etc/fail2ban/jail.d

    local banaction="iptables-multiport"
    if [[ "$FIREWALL_SELECTED" == ufw && -f /etc/fail2ban/action.d/ufw.conf ]]; then
        banaction="ufw"
    fi

    write_managed_file "$FAIL2BAN_DROPIN" 0644 <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 1w
backend = systemd
banaction = $banaction
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = $SSH_PORT
mode = extra
EOF

    fail2ban-client -t >/dev/null
    systemctl enable --now fail2ban.service
    systemctl restart fail2ban.service
    ok "Fail2ban SSH jail enabled."
}

# -----------------------------------------------------------------------------
# AppArmor + time
# -----------------------------------------------------------------------------

configure_apparmor() {
    section "AppArmor"
    apt_install apparmor apparmor-utils

    systemctl enable --now apparmor.service 2>/dev/null || true

    local active="unknown"
    if [[ -f /sys/module/apparmor/parameters/enabled ]]; then
        active="$(cat /sys/module/apparmor/parameters/enabled)"
    fi

    if [[ "$active" == Y ]]; then
        ok "AppArmor kernel support is active."
    else
        warn "AppArmor service is installed but the running kernel does not report it active. No bootloader changes were made."
    fi
}

configure_time() {
    section "Time synchronization"
    apt_install chrony

    if [[ -n "$TIMEZONE" ]]; then
        timedatectl list-timezones | grep -Fxq "$TIMEZONE" || fatal "Invalid timezone: $TIMEZONE"
        timedatectl set-timezone "$TIMEZONE"
        log "Timezone set to $TIMEZONE"
    fi

    systemctl enable --now chrony.service
    timedatectl set-ntp true 2>/dev/null || true
    chronyc tracking 2>/dev/null || true
    ok "Time synchronization enabled."
}

# -----------------------------------------------------------------------------
# Sysctl hardening
# -----------------------------------------------------------------------------

configure_sysctl() {
    section "Kernel/network hardening"

    write_managed_file "$SYSCTL_DROPIN" 0644 <<'EOF'
# Managed by server-init.

# Reverse-path filtering against source-address spoofing.
# Strict mode can break asymmetric routing; the baseline uses strict mode.
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable IP source routing.
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Do not accept or emit ICMP redirects on a server.
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# SYN-flood protection.
net.ipv4.tcp_syncookies = 1

# Ignore bogus broadcast/error patterns and log suspicious source addresses.
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Do not allow unprivileged redirects to become trusted routing information.
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
EOF

    sysctl --system
    ok "Conservative sysctl hardening applied."

    if [[ "$STRICT_KERNEL" == true ]]; then
        write_managed_file "$STRICT_SYSCTL_DROPIN" 0644 <<'EOF'
# Optional strict hardening. Review before using on specialized workloads.
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 2
kernel.dmesg_restrict = 1
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1
fs.suid_dumpable = 0
fs.protected_fifos = 2
fs.protected_regular = 2
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
EOF
        write_managed_file "$STRICT_MODPROBE_DROPIN" 0644 <<'EOF'
# Optional attack-surface reduction. Do not use if these protocols are required.
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
install firewire-core /bin/true
EOF
        sysctl --system
        ok "Strict kernel controls enabled."
    else
        rm -f "$STRICT_SYSCTL_DROPIN" "$STRICT_MODPROBE_DROPIN"
    fi
}

# -----------------------------------------------------------------------------
# Filesystem / shell defaults
# -----------------------------------------------------------------------------

configure_umask() {
    [[ "$STRICT_UMASK" == true ]] || { warn "Global umask hardening disabled by option."; return 0; }
    section "Restrictive default umask"

    if [[ -f /etc/login.defs ]]; then
        backup_file /etc/login.defs
        if grep -Eq '^[[:space:]]*UMASK[[:space:]]+' /etc/login.defs; then
            sed -i -E 's/^[[:space:]]*UMASK[[:space:]]+.*/UMASK 027/' /etc/login.defs
        else
            printf '\nUMASK 027\n' >> /etc/login.defs
        fi
    fi

    write_managed_file "$UMASK_DROPIN" 0644 <<'EOF'
# Managed by server-init.
umask 027
EOF
    ok "System-wide login umask set to 027."
}

configure_shared_memory() {
    [[ "$SECURE_SHARED_MEMORY" == true ]] || return 0
    section "Shared-memory hardening"

    if grep -Eq '^[[:space:]]*[^#[:space:]]+[[:space:]]+/dev/shm[[:space:]]+' /etc/fstab; then
        local shm_line
        shm_line="$(grep -E '^[[:space:]]*[^#[:space:]]+[[:space:]]+/dev/shm[[:space:]]+' /etc/fstab | head -n1 || true)"
        if [[ "$shm_line" == *nodev* && "$shm_line" == *nosuid* && "$shm_line" == *noexec* ]]; then
            log "/dev/shm already has all requested mount flags; leaving it untouched."
        else
            warn "/dev/shm has an existing fstab entry without all strict flags; leaving it untouched to avoid breaking boot configuration."
        fi
    else
        backup_file /etc/fstab
        printf '\n%s\ntmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec 0 0\n' "$SHM_FSTAB_MARKER" >> /etc/fstab
    fi

    if mountpoint -q /dev/shm; then
        mount -o remount,nodev,nosuid,noexec /dev/shm 2>/dev/null || warn "Could not remount /dev/shm; fstab configuration was left in place."
    fi
    ok "Shared-memory hardening requested."
}

# -----------------------------------------------------------------------------
# Service reduction + journald + audit
# -----------------------------------------------------------------------------

disable_unused_services() {
    [[ "$DISABLE_UNUSED_SERVICES" == true ]] || return 0
    section "Unused service reduction"

    local services=(
        bluetooth.service
        cups.service
        cups-browsed.service
        avahi-daemon.service
        ModemManager.service
        speech-dispatcher.service
        geoclue.service
        whoopsie.service
        apport.service
    )

    local service
    for service in "${services[@]}"; do
        if systemctl list-unit-files "$service" >/dev/null 2>&1; then
            if systemctl is-enabled --quiet "$service" 2>/dev/null || systemctl is-active --quiet "$service" 2>/dev/null; then
                log "Disabling common non-server service: $service"
                systemctl disable --now "$service" 2>/dev/null || true
            fi
        fi
    done

    if systemctl is-enabled --quiet rpcbind.service 2>/dev/null || systemctl is-active --quiet rpcbind.service 2>/dev/null; then
        if ! systemctl is-active --quiet nfs-server.service 2>/dev/null && ! grep -Eq '^[^#].*nfs' /proc/mounts; then
            systemctl disable --now rpcbind.service rpcbind.socket 2>/dev/null || true
        else
            log "Keeping rpcbind because NFS appears to be in use."
        fi
    fi

    ok "Unused desktop-oriented services reviewed."
}

configure_journald() {
    [[ "$ENABLE_JOURNAL_PERSISTENCE" == true ]] || return 0
    section "Persistent system journal"

    mkdir -p /etc/systemd/journald.conf.d
    write_managed_file "$JOURNAL_DROPIN" 0644 <<'EOF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=500M
RuntimeMaxUse=128M
EOF

    systemctl restart systemd-journald.service
    ok "Persistent journald storage configured."
}

configure_auditd() {
    [[ "$ENABLE_AUDITD" == true ]] || return 0
    section "Auditd"

    apt_install auditd audispd-plugins
    systemctl enable auditd.service 2>/dev/null || true
    systemctl restart auditd.service 2>/dev/null || systemctl start auditd.service 2>/dev/null || true

    if systemctl is-active --quiet auditd.service; then
        ok "auditd enabled and active."
    else
        warn "auditd is installed but not active; inspect 'systemctl status auditd'."
    fi
}

# -----------------------------------------------------------------------------
# Optional tools
# -----------------------------------------------------------------------------

install_optional_tools() {
    if [[ "$INSTALL_LYNIS" == true ]]; then
        section "Lynis"
        apt_install lynis
        ok "Lynis installed. Run: lynis audit system"
    fi

    if [[ "$INSTALL_CLAMAV" == true ]]; then
        section "ClamAV"
        apt_install clamav clamav-daemon
        systemctl enable --now clamav-freshclam.service 2>/dev/null || true
        systemctl enable --now clamav-daemon.service 2>/dev/null || true
        ok "ClamAV installed and freshclam enabled."
    fi
}

# -----------------------------------------------------------------------------
# Docker
# -----------------------------------------------------------------------------

install_docker() {
    [[ "$INSTALL_DOCKER" == true ]] || return 0
    section "Docker Engine"

    if systemctl is-active --quiet nftables.service 2>/dev/null || [[ "$FIREWALL_SELECTED" == nftables ]]; then
        fatal "Refusing Docker installation while a standalone nftables.service ruleset is active. Docker documents this firewall combination as unsupported; use UFW/iptables-nft or disable/reconfigure nftables first."
    fi

    apt_install ca-certificates curl gnupg

    # Docker warns that published container ports can bypass UFW filtering.
    # This script therefore installs Docker but does not publish any containers.
    log "Docker will be installed from the official Docker APT repository."

    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    fi
    chmod a+r /etc/apt/keyrings/docker.asc

    # shellcheck disable=SC1091
    source /etc/os-release
    local codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    [[ -n "$codename" ]] || fatal "Could not determine Ubuntu codename for Docker repository."

    write_managed_file /etc/apt/sources.list.d/docker.sources 0644 <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $codename
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    apt_update
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker.service

    docker --version
    docker compose version
    warn "Remember: Docker-published ports may bypass UFW. Prefer explicit host binding (for example 127.0.0.1:8080:80) and control exposure at the Docker firewall layer."
    ok "Docker Engine installed."
}

# -----------------------------------------------------------------------------
# WireGuard
# -----------------------------------------------------------------------------

install_wireguard() {
    [[ "$INSTALL_WIREGUARD" == true ]] || return 0
    section "WireGuard tools"
    apt_install wireguard
    ok "WireGuard tools installed; no private keys or peers were generated."
}

# -----------------------------------------------------------------------------
# State + final verification
# -----------------------------------------------------------------------------

persist_state() {
    section "Saving server-init state"
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

    write_managed_file "$STATE_DIR/state.conf" 0600 <<EOF
SCRIPT_VERSION=$SCRIPT_VERSION
APPLIED_AT=$(date -Is)
PROFILE=$PROFILE
SSH_PORT=$SSH_PORT
SSH_PASSWORD_AUTH=$SSH_PASSWORD_EFFECTIVE
ROOT_SSH=$ROOT_SSH_EFFECTIVE
KEY_ADMIN_USER=${KEY_ADMIN_USER:-}
FIREWALL=$FIREWALL_SELECTED
STRICT_KERNEL=$STRICT_KERNEL
STRICT_UMASK=$STRICT_UMASK
SECURE_SHARED_MEMORY=$SECURE_SHARED_MEMORY
FAIL2BAN=$ENABLE_FAIL2BAN
AUDITD=$ENABLE_AUDITD
JOURNAL_PERSISTENCE=$ENABLE_JOURNAL_PERSISTENCE
DOCKER=$INSTALL_DOCKER
WIREGUARD=$INSTALL_WIREGUARD
BACKUP=${BACKUP_CURRENT_DIR:-}
EOF
    ok "State saved to $STATE_DIR/state.conf"
}

final_security_check() {
    section "Final verification"

    sshd -t
    systemctl is-active --quiet ssh.service 2>/dev/null || systemctl is-active --quiet sshd.service 2>/dev/null || fatal "SSH service is not active."

    if [[ "$FIREWALL_SELECTED" == ufw ]]; then
        ufw status | grep -q '^Status: active' || fatal "UFW is not active."
    fi

    if [[ "$ENABLE_FAIL2BAN" == true ]]; then
        fail2ban-client status sshd >/dev/null 2>&1 || warn "Fail2ban sshd jail could not be verified."
    fi

    if systemctl is-enabled --quiet apparmor.service 2>/dev/null || systemctl is-active --quiet apparmor.service 2>/dev/null; then
        debug "AppArmor service enabled/active."
    fi

    if systemctl is-active --quiet chrony.service 2>/dev/null; then
        debug "Chrony active."
    fi

    ok "Security verification completed."
}

show_status() {
    section "SSH"
    systemctl --no-pager --full status ssh.service 2>/dev/null || systemctl --no-pager --full status sshd.service 2>/dev/null || true
    printf '\nEffective SSH policy:\n' >&2
    ssh_effective_value permitrootlogin 2>/dev/null | sed 's/^/  PermitRootLogin /' >&2 || true
    ssh_effective_value passwordauthentication 2>/dev/null | sed 's/^/  PasswordAuthentication /' >&2 || true
    ssh_effective_value pubkeyauthentication 2>/dev/null | sed 's/^/  PubkeyAuthentication /' >&2 || true

    section "Firewall"
    if has ufw; then ufw status verbose 2>/dev/null || true; fi

    section "Fail2ban"
    fail2ban-client status sshd 2>/dev/null || true

    section "AppArmor"
    aa-status 2>/dev/null | head -n 30 || true

    section "Auditd / Journal"
    systemctl --no-pager --full status auditd.service 2>/dev/null | head -n 20 || true
    journalctl --disk-usage 2>/dev/null || true

    section "Listening sockets"
    ss -lntup 2>/dev/null || true

    section "Filesystem"
    df -hT / /var /srv 2>/dev/null || true

    section "Failed systemd units"
    systemctl --failed --no-pager 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Apply / check
# -----------------------------------------------------------------------------

confirm_apply() {
    if [[ "$YES" == true ]]; then
        return 0
    fi

    if [[ ! -t 0 ]]; then
        fatal "apply is running without a TTY; add --yes for unattended use."
    fi

    printf '%bThis will modify system security, SSH, firewall and package configuration.%b\n' "$YELLOW" "$RESET" >&2
    printf 'Profile: %s\n' "$PROFILE" >&2
    printf 'SSH port: %s\n' "$SSH_PORT" >&2
    read -r -p 'Type APPLY to continue: ' answer
    [[ "$answer" == APPLY ]] || fatal "Apply cancelled."
}

apply() {
    require_root
    require_linux
    require_ubuntu
    acquire_lock
    confirm_apply

    mkdir -p "$BACKUP_ROOT" "$STATE_DIR"
    chmod 700 "$BACKUP_ROOT" "$STATE_DIR"
    backup_targets

    prepare_admin
    install_base_packages
    configure_updates
    configure_apparmor
    configure_time
    configure_ssh
    validate_ssh_listener_port
    select_firewall
    configure_fail2ban
    configure_sysctl
    configure_umask
    configure_shared_memory
    disable_unused_services
    configure_journald
    configure_auditd
    install_optional_tools
    install_docker
    install_wireguard

    persist_state
    final_security_check

    section "Bootstrap complete"
    ok "Server baseline applied successfully."
    warn "Keep the current console/SSH session open until you verify a NEW SSH connection works."
    warn "The script never forces a reboot. Reboot manually after reviewing kernel/package changes."

    if [[ -n "$KEY_ADMIN_USER" ]]; then
        log "Key-based administrator detected: $KEY_ADMIN_USER"
    fi
    if [[ "$SSH_PASSWORD_EFFECTIVE" == yes ]]; then
        warn "PasswordAuthentication remains enabled for lockout safety. After key access is verified, rerun with --ssh-password-auth off."
    fi
    if [[ "$ROOT_SSH_EFFECTIVE" != no ]]; then
        warn "Root SSH is not fully disabled yet. Once a verified non-root key administrator exists, rerun with --root-ssh off."
    fi
}

check() {
    require_root
    require_linux
    require_ubuntu
    find_key_admin_user || true
    show_detected
}

main() {
    parse_args "$@"

    case "$ACTION" in
        help|-h|--help)
            usage
            ;;
        plan)
            require_root
            require_linux
            require_ubuntu
            find_key_admin_user || true
            show_detected
            show_plan
            ;;
        check)
            check
            ;;
        status)
            require_root
            require_linux
            require_ubuntu
            show_status
            ;;
        apply)
            apply
            ;;
    esac
}

main "$@"
