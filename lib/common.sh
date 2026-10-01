# shellcheck shell=bash
# Shared runtime for the dotfiles assistants.
# This file is sourced; it intentionally does not change the caller's shell options.

[[ -n "${DOTFILES_COMMON_LOADED:-}" ]] && return 0
DOTFILES_COMMON_LOADED=1

DOTFILES_STATE_HOME="${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/dotfiles"
DOTFILES_BACKUP_HOME="${DOTFILES_STATE_HOME}/backups"
DOTFILES_RUN_ID="${DOTFILES_RUN_ID:-$(date +%Y%m%d-%H%M%S)-$$}"
DOTFILES_NO_COLOR="${DOTFILES_NO_COLOR:-0}"
DOTFILES_PKG_REFRESHED=0
DOTFILES_RESULT_FILE="${DOTFILES_RESULT_FILE:-}"

TASK_PASS=0
TASK_WARN=0
TASK_FAIL=0
TASK_SKIP=0
TASK_RESULTS=()

command_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_target_dir() {
    local dir="$1" mode="${2:-0755}" existed=0
    [[ -d "$dir" ]] && existed=1
    mkdir -p "$dir" || return 1
    if (( existed == 0 )); then
        chmod "$mode" "$dir" 2>/dev/null || true
    fi
    if (( EUID == 0 )) && [[ -n "${TARGET_USER:-}" ]]; then
        chown "$TARGET_USER:${TARGET_GROUP:-$(id -gn "$TARGET_USER" 2>/dev/null || printf '%s' "$TARGET_USER")}" "$dir" 2>/dev/null || true
    fi
}

ui_has_tty() {
    [[ ( -t 0 || -t 1 || -t 2 ) && -r /dev/tty && -w /dev/tty ]]
}

ui_color_init() {
    if [[ "$DOTFILES_NO_COLOR" == "1" || -n "${NO_COLOR:-}" || ! -t 1 ]]; then
        C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN="" C_WHITE=""
    else
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_RED=$'\033[31m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_BLUE=$'\033[34m'
        C_MAGENTA=$'\033[35m'
        C_CYAN=$'\033[36m'
        C_WHITE=$'\033[97m'
    fi
}
ui_color_init

UI_RULE="========================================================================================"
UI_THIN="----------------------------------------------------------------------------------------"

msg_info()    { printf '%b[INFO]%b %s
' "$C_CYAN" "$C_RESET" "$*" >&2; }
msg_success() { printf '%b[ OK ]%b %s
' "$C_GREEN" "$C_RESET" "$*" >&2; }
msg_warn()    { printf '%b[WARN]%b %s
' "$C_YELLOW" "$C_RESET" "$*" >&2; }
msg_error()   { printf '%b[FAIL]%b %s
' "$C_RED" "$C_RESET" "$*" >&2; }
msg_skip()    { printf '%b[SKIP]%b %s
' "$C_DIM" "$C_RESET" "$*" >&2; }
msg_exec()    { printf '%b[EXEC]%b %s
' "$C_MAGENTA" "$C_RESET" "$*" >&2; }

ui_rule() { printf '%b%s%b
' "$C_DIM" "$UI_THIN" "$C_RESET"; }

ui_clear() {
    [[ -t 1 ]] && command_exists clear && clear 2>/dev/null || true
}

ui_brand() {
    local product="${1:-WORKSTATION CONTROL PLANE}"
    printf '%b' "$C_CYAN"
    cat <<'EOF_BRAND'
   ____        __  _____ __         
  / __ \____  / /_/ __(_) /__  _____
 / / / / __ \/ __/ /_/ / / _ \/ ___/
/ /_/ / /_/ / /_/ __/ / /  __(__  ) 
\____/\____/\__/_/ /_/_/\___/____/  
EOF_BRAND
    printf '%b' "$C_RESET"
    printf '%b  %s%b
' "$C_BOLD" "$product" "$C_RESET"
}

ui_header() {
    local title="$1" subtitle="${2:-}" product="${3:-WORKSTATION CONTROL PLANE}"
    ui_clear
    ui_brand "$product"
    printf '%b%s%b
' "$C_DIM" "$UI_RULE" "$C_RESET"
    printf '  %-14s %s
' "Host" "$(hostname 2>/dev/null || printf unknown)"
    printf '  %-14s %s
' "Platform" "${OS_PRETTY:-Linux} (${OS_FAMILY:-unknown})"
    printf '  %-14s %s
' "Target" "${TARGET_USER:-unknown} -> ${TARGET_HOME:-unknown}"
    printf '  %-14s %s
' "Login shell" "${TARGET_SHELL:-unknown}"
    printf '%b%s%b
' "$C_DIM" "$UI_RULE" "$C_RESET"
    printf '%b%s%b
' "$C_BOLD" "$title" "$C_RESET"
    [[ -n "$subtitle" ]] && printf '%b%s%b
' "$C_DIM" "$subtitle" "$C_RESET"
    printf '
'
}

ui_section() {
    local title="$1"
    printf '
%b-- %s %s%b
' "$C_BOLD$C_WHITE" "$title" "$(printf '%*s' "$((68-${#title}))" '' | tr ' ' '-')" "$C_RESET"
}

ui_menu_item() {
    local key="$1" title="$2" desc="${3:-}" colour="${4:-$C_CYAN}" tag="${5:-}"
    if [[ -n "$tag" ]]; then
        printf '  %b[%2s]%b  %b%-25s%b %b%-10s%b %b%s%b
' "$C_DIM" "$key" "$C_RESET" "$colour" "$title" "$C_RESET" "$C_BOLD" "$tag" "$C_RESET" "$C_DIM" "$desc" "$C_RESET"
    else
        printf '  %b[%2s]%b  %b%-25s%b %b%s%b
' "$C_DIM" "$key" "$C_RESET" "$colour" "$title" "$C_RESET" "$C_DIM" "$desc" "$C_RESET"
    fi
}

ui_pause() {
    ui_has_tty || return 0
    printf '\n' >/dev/tty
    read -r -p "Press [ENTER] to continue..." _ </dev/tty || true
}

ask() {
    local prompt="$1" default="${2:-}" answer=""
    ui_has_tty || return 1
    if [[ -n "$default" ]]; then
        printf '%b>%b %s %b[%s]%b: ' "$C_CYAN" "$C_RESET" "$prompt" "$C_DIM" "$default" "$C_RESET" >/dev/tty
    else
        printf '%b>%b %s: ' "$C_CYAN" "$C_RESET" "$prompt" >/dev/tty
    fi
    IFS= read -r answer </dev/tty || return 1
    printf '%s' "${answer:-$default}"
}

confirm() {
    local prompt="$1" default="${2:-N}" answer=""
    ui_has_tty || return 1
    while true; do
        if [[ "${default^^}" == "Y" ]]; then
            printf '%b?%b %s %b[Y/n]%b: ' "$C_CYAN" "$C_RESET" "$prompt" "$C_DIM" "$C_RESET" >/dev/tty
        else
            printf '%b?%b %s %b[y/N]%b: ' "$C_CYAN" "$C_RESET" "$prompt" "$C_DIM" "$C_RESET" >/dev/tty
        fi
        IFS= read -r answer </dev/tty || return 1
        answer="${answer:-$default}"
        case "${answer^^}" in
            Y|YES|S|SI|SÍ) return 0 ;;
            N|NO) return 1 ;;
            *) msg_warn "Please answer yes or no." ;;
        esac
    done
}

confirm_literal() {
    local prompt="$1" literal="$2" answer=""
    ui_has_tty || return 1
    printf '%b%s%b\n' "$C_YELLOW" "$prompt" "$C_RESET" >/dev/tty
    printf 'Type %b%s%b to continue: ' "$C_RED" "$literal" "$C_RESET" >/dev/tty
    IFS= read -r answer </dev/tty || return 1
    [[ "$answer" == "$literal" ]]
}

record_result() {
    local status="$1" label="$2" detail="${3:-}"
    TASK_RESULTS+=("${status}|${label}|${detail}")
    if [[ -n "${DOTFILES_RESULT_FILE:-}" ]]; then
        mkdir -p "$(dirname "$DOTFILES_RESULT_FILE")" 2>/dev/null || true
        printf '%s\t%s\t%s\t%s\n' "$(date -Is)" "$status" "$label" "$detail" >>"$DOTFILES_RESULT_FILE" 2>/dev/null || true
    fi
    case "$status" in
        PASS) ((TASK_PASS+=1)) ;;
        WARN) ((TASK_WARN+=1)) ;;
        FAIL) ((TASK_FAIL+=1)) ;;
        SKIP) ((TASK_SKIP+=1)) ;;
    esac
}

run_task() {
    local label="$1"; shift
    printf '\n%b==>%b %s\n' "$C_CYAN" "$C_RESET" "$label"
    local rc=0
    if "$@"; then
        record_result PASS "$label"
        msg_success "$label"
    else
        rc=$?
        record_result WARN "$label" "rc=$rc"
        msg_warn "$label finished with rc=$rc; the assistant will continue."
    fi
    return 0
}

show_run_summary() {
    printf '\n'
    ui_rule
    printf '%bRun summary%b\n' "$C_BOLD" "$C_RESET"
    printf '  PASS=%d  WARN=%d  FAIL=%d  SKIP=%d\n' "$TASK_PASS" "$TASK_WARN" "$TASK_FAIL" "$TASK_SKIP"
    local row status label detail
    for row in "${TASK_RESULTS[@]}"; do
        IFS='|' read -r status label detail <<<"$row"
        [[ "$status" == "WARN" || "$status" == "FAIL" ]] || continue
        printf '  %-5s %-34s %s\n' "$status" "$label" "$detail"
    done
    [[ -n "${DOTFILES_RESULT_FILE:-}" ]] && printf '  Evidence: %s\n' "$DOTFILES_RESULT_FILE"
    ui_rule
}

is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease /proc/version 2>/dev/null
}

is_container() {
    command_exists systemd-detect-virt && systemd-detect-virt --container >/dev/null 2>&1
}

is_desktop_environment() {
    [[ -n "${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] && return 0
    is_container && return 1
    command_exists systemctl || return 1
    [[ "$(systemctl get-default 2>/dev/null || true)" == "graphical.target" ]]
}

detect_distribution() {
    OS_ID="unknown"
    OS_ID_LIKE=""
    OS_PRETTY="Linux"
    OS_FAMILY="unknown"

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_ID_LIKE="${ID_LIKE:-}"
        OS_PRETTY="${PRETTY_NAME:-$OS_ID}"
    fi

    local haystack=" ${OS_ID,,} ${OS_ID_LIKE,,} "
    case "$haystack" in
        *debian*|*ubuntu*) OS_FAMILY="debian" ;;
        *arch*) OS_FAMILY="arch" ;;
        *fedora*|*rhel*|*centos*) OS_FAMILY="fedora" ;;
        *suse*|*opensuse*) OS_FAMILY="opensuse" ;;
        *)
            command_exists apt-get && OS_FAMILY="debian"
            [[ "$OS_FAMILY" == unknown ]] && command_exists pacman && OS_FAMILY="arch"
            [[ "$OS_FAMILY" == unknown ]] && command_exists dnf && OS_FAMILY="fedora"
            [[ "$OS_FAMILY" == unknown ]] && command_exists zypper && OS_FAMILY="opensuse"
            ;;
    esac

    [[ "$OS_FAMILY" != "unknown" ]]
}

resolve_target_user() {
    local candidate="" repo_owner="" session_user=""

    if [[ -n "${DOTFILES_TARGET_USER:-}" ]]; then
        candidate="$DOTFILES_TARGET_USER"
    elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-root}" != "root" ]]; then
        candidate="$SUDO_USER"
    elif [[ -n "${PKEXEC_UID:-}" ]] && command_exists getent; then
        candidate="$(getent passwd "$PKEXEC_UID" 2>/dev/null | awk -F: 'NR==1{print $1}')"
    fi

    # Root shells created with `sudo -i`/`su` often lose SUDO_USER. Prefer the
    # non-root owner of the checkout, then the login session user, before root.
    if [[ -z "$candidate" && ${EUID:-0} -eq 0 ]]; then
        if [[ -n "${SCRIPT_DIR:-}" ]]; then
            repo_owner="$(stat -c '%U' "$SCRIPT_DIR" 2>/dev/null || true)"
            [[ -n "$repo_owner" && "$repo_owner" != "root" && "$repo_owner" != "UNKNOWN" ]] && candidate="$repo_owner"
        fi
        if [[ -z "$candidate" ]]; then
            session_user="$(logname 2>/dev/null || true)"
            [[ -n "$session_user" && "$session_user" != "root" ]] && candidate="$session_user"
        fi
    fi

    [[ -n "$candidate" ]] || candidate="${USER:-$(id -un 2>/dev/null || printf root)}"
    TARGET_USER="$candidate"

    if ! id "$TARGET_USER" >/dev/null 2>&1; then
        msg_error "Target user '$TARGET_USER' does not exist. Use --user USER to select it explicitly."
        return 1
    fi

    local passwd_entry=""
    passwd_entry="$(getent passwd "$TARGET_USER" 2>/dev/null | head -n1 || true)"
    TARGET_HOME="$(printf '%s' "$passwd_entry" | awk -F: '{print $6}')"
    TARGET_SHELL="$(printf '%s' "$passwd_entry" | awk -F: '{print $7}')"
    [[ -n "$TARGET_HOME" ]] || TARGET_HOME="$( [[ "$TARGET_USER" == root ]] && printf /root || printf '/home/%s' "$TARGET_USER" )"
    [[ -n "$TARGET_SHELL" ]] || TARGET_SHELL="${SHELL:-/bin/bash}"
    TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || printf '%s' "$TARGET_USER")"
    export TARGET_USER TARGET_HOME TARGET_GROUP TARGET_SHELL
}

require_linux() {
    [[ "$(uname -s 2>/dev/null)" == "Linux" ]] || {
        msg_error "This assistant targets Linux hosts."
        return 1
    }
}

ensure_root() {
    (( EUID == 0 )) && return 0
    command_exists sudo || {
        msg_error "Root privileges are required and sudo is not installed."
        return 1
    }
    local target="${TARGET_USER:-${USER:-}}"
    exec sudo --preserve-env=TERM,NO_COLOR,DOTFILES_NO_COLOR env DOTFILES_TARGET_USER="$target" bash "$0" "$@"
}

run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif command_exists sudo; then
        sudo -- "$@"
    else
        msg_error "Root privileges are required for: $*"
        return 1
    fi
}

run_as_target() {
    if (( EUID == 0 )) && [[ "${TARGET_USER:-root}" != "root" ]]; then
        if command_exists sudo; then
            sudo -H -u "$TARGET_USER" -- "$@"
        else
            runuser -u "$TARGET_USER" -- "$@"
        fi
    else
        "$@"
    fi
}

load_distro_module() {
    local root="$1" module=""
    module="${root}/bash/distros/${OS_FAMILY}.sh"
    [[ -r "$module" ]] || {
        msg_error "No package module for OS family '$OS_FAMILY': $module"
        return 1
    }
    # shellcheck disable=SC1090
    source "$module"
}

pkg_refresh_once() {
    (( DOTFILES_PKG_REFRESHED == 1 )) && return 0
    if pkg_refresh; then
        DOTFILES_PKG_REFRESHED=1
        return 0
    fi
    return 1
}

filter_available_packages() {
    VALID_PACKAGES=()
    local pkg
    for pkg in "$@"; do
        [[ -n "$pkg" ]] || continue
        if pkg_available "$pkg"; then
            VALID_PACKAGES+=("$pkg")
        else
            msg_skip "Package unavailable in configured official repositories: $pkg"
        fi
    done
}

install_packages() {
    (($#)) || return 0
    pkg_refresh_once || msg_warn "Repository metadata refresh failed; trying package installation with current metadata."
    filter_available_packages "$@"
    ((${#VALID_PACKAGES[@]})) || {
        msg_warn "No requested packages are available from configured repositories."
        return 0
    }
    msg_exec "Installing ${#VALID_PACKAGES[@]} package(s) from configured distribution repositories."
    if pkg_install "${VALID_PACKAGES[@]}"; then
        hash -r 2>/dev/null || true
        return 0
    fi
    return 1
}

package_group_install() {
    local group="$1" var=""
    var="DISTRO_PACKAGES_${group^^}"
    # shellcheck disable=SC1083
    local -n ref="$var"
    install_packages "${ref[@]}"
}

backup_path() {
    local path="$1" rel="" dest=""
    [[ -e "$path" || -L "$path" ]] || return 0
    rel="${path#/}"
    dest="${DOTFILES_BACKUP_HOME}/${DOTFILES_RUN_ID}/${rel}"
    ensure_target_dir "$DOTFILES_BACKUP_HOME" 0700 || return 1
    ensure_target_dir "$DOTFILES_BACKUP_HOME/$DOTFILES_RUN_ID" 0700 || return 1
    mkdir -p "$(dirname "$dest")"
    if (( EUID == 0 )); then chown "$TARGET_USER:$TARGET_GROUP" "$(dirname "$dest")" 2>/dev/null || true; fi
    cp -a -- "$path" "$dest"
    if (( EUID == 0 )) && [[ -n "${TARGET_USER:-}" && "${TARGET_USER:-root}" != root ]]; then
        chown -R "$TARGET_USER:${TARGET_GROUP:-$(id -gn "$TARGET_USER" 2>/dev/null || printf "$TARGET_USER")}" "$dest" 2>/dev/null || true
    fi
}

copy_with_backup() {
    local src="$1" dest="$2" owner="${3:-${TARGET_USER:-root}}" mode="${4:-}"
    [[ -f "$src" ]] || { msg_error "Source file not found: $src"; return 1; }
    mkdir -p "$(dirname "$dest")"
    backup_path "$dest"
    local tmp="${dest}.dotfiles.$$"
    cp -- "$src" "$tmp" || return 1
    [[ -n "$mode" ]] && chmod "$mode" "$tmp"
    if (( EUID == 0 )); then
        chown "$owner:$(id -gn "$owner" 2>/dev/null || printf "$owner")" "$tmp" 2>/dev/null || true
    fi
    mv -f -- "$tmp" "$dest"
}

ensure_line() {
    local file="$1" line="$2"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    grep -Fqx -- "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >>"$file"
}

service_exists() {
    local unit="$1" state=""
    command_exists systemctl || return 1
    state="$(systemctl show -p LoadState --value "$unit" 2>/dev/null || true)"
    [[ -n "$state" && "$state" != "not-found" ]]
}

service_active() {
    command_exists systemctl && systemctl is-active --quiet "$1" 2>/dev/null
}

service_enabled() {
    command_exists systemctl && systemctl is-enabled --quiet "$1" 2>/dev/null
}

safe_service_enable_now() {
    local unit="$1"
    service_exists "$unit" || { msg_skip "systemd unit not installed: $unit"; return 0; }
    systemctl enable --now "$unit"
}

file_sha256() {
    if command_exists sha256sum; then
        sha256sum "$1" | awk '{print $1}'
    elif command_exists shasum; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        printf 'unavailable'
    fi
}
