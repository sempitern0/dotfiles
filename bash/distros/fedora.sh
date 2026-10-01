# shellcheck shell=bash
# Package provider for Fedora/RHEL-compatible families. Configured official repositories only.

DISTRO_PACKAGE_MANAGER="dnf"

pkg_refresh() { run_as_root dnf -q makecache; }
pkg_available() { dnf -q info "$1" >/dev/null 2>&1; }
pkg_installed() { rpm -q "$1" >/dev/null 2>&1; }
pkg_install() { run_as_root dnf install -y "$@"; }
pkg_upgrade() { run_as_root dnf upgrade -y; }
pkg_remove() { run_as_root dnf remove -y "$@"; }

DISTRO_PACKAGES_CORE=(
    bash bash-completion ca-certificates curl wget git vim-enhanced openssl less man-db
    unzip zip tar xz rsync jq tree file openssh-clients
)
DISTRO_PACKAGES_DEV=(
    gcc gcc-c++ make pkgconf-pkg-config git-lfs ShellCheck
    python3 python3-pip words
)
DISTRO_PACKAGES_ADMIN=(
    iproute iputils bind-utils traceroute mtr nmap-ncat
    procps-ng psmisc lsof pciutils usbutils smartmontools
    htop btop iotop tmux ripgrep fd-find bat fzf ncdu duf eza zoxide whois nmap
)
DISTRO_PACKAGES_DESKTOP=(
    xclip wl-clipboard libnotify
)
DISTRO_PACKAGES_SECURITY=(
    nftables firewalld fail2ban lynis clamav
)
DISTRO_PACKAGES_PRIVACY=(
    tor torsocks
)
