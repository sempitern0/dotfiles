# shellcheck shell=bash
# Package provider for openSUSE/SLES families. Configured distribution repositories only.

DISTRO_PACKAGE_MANAGER="zypper"

pkg_refresh() { run_as_root zypper --non-interactive refresh; }
pkg_available() { zypper --non-interactive info "$1" >/dev/null 2>&1; }
pkg_installed() { rpm -q "$1" >/dev/null 2>&1; }
pkg_install() { run_as_root zypper --non-interactive install --no-recommends "$@"; }
pkg_upgrade() {
    if [[ "${OS_ID:-}" == "opensuse-tumbleweed" || "${OS_ID:-}" == "opensuse-microos" ]]; then
        run_as_root zypper --non-interactive dup
    else
        run_as_root zypper --non-interactive update
    fi
}
pkg_remove() { run_as_root zypper --non-interactive remove "$@"; }

DISTRO_PACKAGES_CORE=(
    bash bash-completion ca-certificates curl wget git vim openssl less man
    unzip zip tar xz rsync jq tree file openssh
)
DISTRO_PACKAGES_DEV=(
    gcc gcc-c++ make pkg-config git-lfs ShellCheck python3 python3-pip words
)
DISTRO_PACKAGES_ADMIN=(
    iproute2 iputils bind-utils traceroute mtr netcat-openbsd
    procps psmisc lsof pciutils usbutils smartmontools
    htop btop iotop tmux ripgrep fd bat fzf ncdu duf eza zoxide whois nmap
)
DISTRO_PACKAGES_DESKTOP=(
    xclip wl-clipboard libnotify-tools
)
DISTRO_PACKAGES_SECURITY=(
    nftables firewalld fail2ban lynis clamav
)
DISTRO_PACKAGES_PRIVACY=(
    tor torsocks
)
