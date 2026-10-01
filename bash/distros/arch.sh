# shellcheck shell=bash
# Package provider for Arch-family systems. Official repositories only; no AUR bootstrap.

DISTRO_PACKAGE_MANAGER="pacman"

pkg_refresh() { return 0; }
pkg_available() { pacman -Si "$1" >/dev/null 2>&1; }
pkg_installed() { pacman -Q "$1" >/dev/null 2>&1; }
pkg_install() { run_as_root pacman -S --needed --noconfirm "$@"; }
pkg_upgrade() { run_as_root pacman -Syu --noconfirm; }
pkg_remove() { run_as_root pacman -Rns --noconfirm "$@"; }

DISTRO_PACKAGES_CORE=(
    bash bash-completion ca-certificates curl wget git vim openssl less man-db man-pages
    unzip zip tar xz rsync jq tree file openssh
)
DISTRO_PACKAGES_DEV=(
    base-devel git-lfs shellcheck python python-pip words
)
DISTRO_PACKAGES_ADMIN=(
    iproute2 iputils bind traceroute mtr openbsd-netcat
    procps-ng psmisc lsof pciutils usbutils smartmontools
    htop btop iotop tmux ripgrep fd bat fzf ncdu duf eza zoxide whois nmap
)
DISTRO_PACKAGES_DESKTOP=(
    xclip wl-clipboard libnotify
)
DISTRO_PACKAGES_SECURITY=(
    nftables fail2ban lynis clamav
)
DISTRO_PACKAGES_PRIVACY=(
    tor torsocks
)
