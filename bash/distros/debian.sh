# shellcheck shell=bash
# Package provider for Debian/Ubuntu family. Sourced by bash_setup.sh/hardening_setup.sh.

DISTRO_PACKAGE_MANAGER="apt-get"

pkg_refresh() { run_as_root apt-get update; }
pkg_available() { apt-cache show "$1" >/dev/null 2>&1; }
pkg_installed() { dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii '; }
pkg_install() { run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }
pkg_upgrade() { run_as_root env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; }
pkg_remove() { run_as_root env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@"; }

DISTRO_PACKAGES_CORE=(
    bash bash-completion ca-certificates curl wget git vim openssl less man-db
    unzip zip tar xz-utils rsync jq tree file openssh-client
)
DISTRO_PACKAGES_DEV=(
    build-essential make gcc g++ pkg-config git-lfs shellcheck
    python3 python3-venv python3-pip wamerican
)
DISTRO_PACKAGES_ADMIN=(
    iproute2 iputils-ping dnsutils traceroute mtr-tiny netcat-openbsd
    procps psmisc lsof pciutils usbutils smartmontools
    htop btop iotop tmux ripgrep fd-find bat fzf ncdu duf eza zoxide whois nmap
)
DISTRO_PACKAGES_DESKTOP=(
    xclip wl-clipboard libnotify-bin
)
DISTRO_PACKAGES_SECURITY=(
    nftables fail2ban lynis clamav
)
DISTRO_PACKAGES_PRIVACY=(
    tor torsocks
)
