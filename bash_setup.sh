#!/usr/bin/env bash
# Dotfiles Workstation Assistant
# A non-destructive, selectable Linux workstation bootstrap.

# Intentionally no `set -e`: an interactive control plane must report recoverable
# failures and continue. Functions still return meaningful status codes.
set -u
set -o pipefail
IFS=$'\n\t'
umask 022

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SCRIPT_VERSION="2.0.0-workstation-control-plane"
OS_MODULE_LOADED=0

usage() {
    cat <<EOF_HELP
Dotfiles Workstation Assistant v${SCRIPT_VERSION}

Usage:
  ./bash_setup.sh                 interactive control plane
  ./bash_setup.sh --minimal       shell + Git + utilities + minimal official packages
  ./bash_setup.sh --recommended   developer/sysadmin workstation; Vim excluded
  ./bash_setup.sh --full          all dotfiles modules, including Vim and optional desktop tools
  ./bash_setup.sh --status        read-only readiness/status view
  ./bash_setup.sh --hardening     open the system hardening assistant
  ./bash_setup.sh --no-color      disable ANSI colors
  ./bash_setup.sh --help

The assistant uses only packages available from repositories already configured
for the detected distribution. It does not bootstrap AUR helpers, PPAs, COPRs,
third-party repositories, curl-to-shell installers or GitHub release binaries.
EOF_HELP
}

prepare_context() {
    require_linux || return 1
    resolve_target_user || return 1

    # User-facing backups/state belong to the target account even when setup was
    # launched through sudo.
    DOTFILES_STATE_HOME="${XDG_STATE_HOME:-$TARGET_HOME/.local/state}/dotfiles"
    [[ "$DOTFILES_STATE_HOME" == /root/* && "$TARGET_USER" != root ]] && DOTFILES_STATE_HOME="$TARGET_HOME/.local/state/dotfiles"
    DOTFILES_BACKUP_HOME="$DOTFILES_STATE_HOME/backups"
    # Do not create state during read-only status. State/backups are created lazily
    # by modifying operations or by start_workstation_evidence().
    if detect_distribution; then
        if load_distro_module "$SCRIPT_DIR"; then
            OS_MODULE_LOADED=1
        fi
    else
        OS_FAMILY="unknown"
        OS_PRETTY="$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}")"
        msg_warn "Unsupported package family. Dotfiles can still be deployed, but package actions are disabled."
    fi
}

start_workstation_evidence() {
    DOTFILES_RESULT_FILE="$DOTFILES_STATE_HOME/runs/$DOTFILES_RUN_ID/results.tsv"
    mkdir -p "$(dirname "$DOTFILES_RESULT_FILE")"
    : >"$DOTFILES_RESULT_FILE"
    chmod 0600 "$DOTFILES_RESULT_FILE"
    (( EUID == 0 )) && chown "$TARGET_USER:$TARGET_GROUP" "$DOTFILES_RESULT_FILE" "$(dirname "$DOTFILES_RESULT_FILE")" 2>/dev/null || true
}

require_package_provider() {
    (( OS_MODULE_LOADED == 1 )) || {
        msg_warn "No package provider for '${OS_PRETTY:-unknown}'. Supported families: Debian/Ubuntu, Arch, Fedora/RHEL-like, openSUSE/SLES."
        return 1
    }
}

configure_shell() {
    local src="$SCRIPT_DIR/bash/conf" f
    [[ -d "$src" ]] || { msg_error "Missing Bash configuration directory: $src"; return 1; }
    for f in .bashrc .bash.aliases .bash.functions; do
        copy_with_backup "$src/$f" "$TARGET_HOME/$f" "$TARGET_USER" 0644 || return 1
    done
    msg_info "Previous files, when present, were copied below: $DOTFILES_BACKUP_HOME/$DOTFILES_RUN_ID"
}

configure_git() {
    command_exists git || { msg_warn "Git is not installed. Install the Core package profile first."; return 1; }

    local config_dir="$TARGET_HOME/.config/git"
    local managed="$config_dir/dotfiles.gitconfig"
    local local_cfg="$config_dir/local.gitconfig"
    mkdir -p "$config_dir"
    if (( EUID == 0 )); then chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.config" "$config_dir" 2>/dev/null || true; fi

    copy_with_backup "$SCRIPT_DIR/git/.gitconfig" "$managed" "$TARGET_USER" 0644 || return 1

    # Preserve the user's ~/.gitconfig. Add a single managed include if missing.
    if ! run_as_target git config --global --get-all include.path 2>/dev/null | grep -Fxq "$managed"; then
        run_as_target git config --global --add include.path "$managed" || return 1
    fi

    if [[ ! -e "$local_cfg" ]]; then
        cat >"$local_cfg" <<'EOF_LOCAL'
# Machine/user-specific Git identity belongs here, not in the public dotfiles repo.
# [user]
#     name = Your Name
#     email = you@example.com
EOF_LOCAL
        chmod 0600 "$local_cfg"
        (( EUID == 0 )) && chown "$TARGET_USER:$TARGET_GROUP" "$local_cfg" 2>/dev/null || true
    fi

    msg_info "Git identity is intentionally not set by the public template."
    msg_info "Optional local identity file: $local_cfg"
}

configure_ssh_client() {
    local ssh_dir="$TARGET_HOME/.ssh" conf_dir="" main=""
    conf_dir="$ssh_dir/conf.d"
    main="$ssh_dir/config"
    mkdir -p "$conf_dir"
    chmod 0700 "$ssh_dir" "$conf_dir"
    # Never recursively chown an existing ~/.ssh tree: private keys and agent-
    # managed files are personal state. Only normalize directories we manage.
    (( EUID == 0 )) && chown "$TARGET_USER:$TARGET_GROUP" "$ssh_dir" "$conf_dir" 2>/dev/null || true

    copy_with_backup "$SCRIPT_DIR/git/ssh/config" "$conf_dir/90-dotfiles.conf" "$TARGET_USER" 0600 || return 1

    # OpenSSH supports Include. Preserve personal hosts/keys in the user's main file.
    local include_line='Include ~/.ssh/conf.d/*.conf'
    if [[ -e "$main" ]]; then
        backup_path "$main"
        grep -Fqx "$include_line" "$main" 2>/dev/null || {
            local tmp="${main}.dotfiles.$$"
            { printf '%s\n\n' "$include_line"; cat "$main"; } >"$tmp"
            chmod 0600 "$tmp"
            (( EUID == 0 )) && chown "$TARGET_USER:$TARGET_GROUP" "$tmp" 2>/dev/null || true
            mv -f "$tmp" "$main"
        }
    else
        printf '%s\n' "$include_line" >"$main"
        chmod 0600 "$main"
        (( EUID == 0 )) && chown "$TARGET_USER:$TARGET_GROUP" "$main" 2>/dev/null || true
    fi

    if command_exists ssh; then
        run_as_target ssh -G github.com >/dev/null 2>&1 || msg_warn "OpenSSH client did not accept the generated include; inspect $main."
    fi
}

configure_git_ssh() {
    configure_git || return 1
    configure_ssh_client
}

configure_vim() {
    local src="$SCRIPT_DIR/vim/.vimrc" dest="$TARGET_HOME/.vimrc"
    [[ -f "$src" ]] || { msg_error "Missing Vim template: $src"; return 1; }
    copy_with_backup "$src" "$dest" "$TARGET_USER" 0644 || return 1
    msg_info "The supplied Vim profile is pluginless and performs no network downloads."
}

configure_commands() {
    local src_root="$SCRIPT_DIR/bash/bin" dest="$TARGET_HOME/.local/bin" tool name
    [[ -d "$src_root" ]] || { msg_warn "No custom command directory found."; return 0; }
    mkdir -p "$dest"
    (( EUID == 0 )) && chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.local" "$dest" 2>/dev/null || true

    # Copy, do not symlink into the checkout: commands keep working if the repo is moved/removed.
    while IFS= read -r -d '' tool; do
        name="$(basename "$tool" .sh)"
        [[ "$name" == "pstree" ]] && name="pstree-info"
        backup_path "$dest/$name"
        cp -- "$tool" "$dest/$name" || return 1
        chmod 0755 "$dest/$name"
        (( EUID == 0 )) && chown "$TARGET_USER:$TARGET_GROUP" "$dest/$name" 2>/dev/null || true
    done < <(find "$src_root" -type f -name '*.sh' -print0)
}

install_group() {
    local group="$1"
    require_package_provider || return 1
    package_group_install "$group"
}

install_desktop_group() {
    if is_desktop_environment; then
        install_group desktop
    else
        msg_skip "No graphical session detected; desktop helper packages skipped."
    fi
}

upgrade_system() {
    require_package_provider || return 1
    printf '\n'
    msg_warn "This upgrades installed distribution packages; it is intentionally not part of automatic profiles."
    confirm "Run the distribution package upgrade now?" N || return 0
    pkg_refresh_once || return 1
    pkg_upgrade
}

configure_privacy_tools() {
    require_package_provider || return 1
    msg_info "Installs Tor/torsocks from configured distribution repositories only."
    msg_info "No torrc is overwritten and no service is automatically enabled."
    install_group privacy
}

status_report() {
    ui_header "WORKSTATION READINESS" "Read-only inventory; missing optional tools are not failures"
    printf '  %-24s %s\n' "Distribution" "${OS_PRETTY:-unknown}"
    printf '  %-24s %s\n' "Package provider" "${DISTRO_PACKAGE_MANAGER:-unavailable}"
    printf '  %-24s %s\n' "Desktop session" "$(is_desktop_environment && printf detected || printf not-detected)"
    printf '  %-24s %s\n' "WSL" "$(is_wsl && printf yes || printf no)"
    printf '  %-24s %s\n' "Container" "$(is_container && printf yes || printf no)"
    printf '\n'
    local cmd
    for cmd in git ssh vim python3 gcc make jq rg fzf bat fd tmux btop shellcheck; do
        if command_exists "$cmd"; then
            printf '  %b[ OK ]%b %-18s %s\n' "$C_GREEN" "$C_RESET" "$cmd" "$(command -v "$cmd")"
        else
            printf '  %b[ -- ]%b %-18s optional/missing\n' "$C_DIM" "$C_RESET" "$cmd"
        fi
    done
    printf '\n  Backups: %s\n' "$DOTFILES_BACKUP_HOME"
}

run_hardening_assistant() {
    local script="$SCRIPT_DIR/hardening_setup.sh"
    [[ -f "$script" ]] || { msg_error "Hardening assistant not found: $script"; return 1; }
    msg_info "Opening the separate hardening policy workspace. No hardening is implicit in workstation profiles."
    if (( EUID == 0 )); then
        env DOTFILES_TARGET_USER="$TARGET_USER" bash "$script"
    elif command_exists sudo; then
        sudo env DOTFILES_TARGET_USER="$TARGET_USER" bash "$script"
    else
        msg_error "sudo/root is required for system hardening."
        return 1
    fi
}

profile_minimal() {
    run_task "Core distribution packages" install_group core
    run_task "Bash environment" configure_shell
    run_task "Git and SSH client defaults" configure_git_ssh
    run_task "Portable custom commands" configure_commands
}

profile_recommended() {
    run_task "Core distribution packages" install_group core
    run_task "Developer toolchain" install_group dev
    run_task "Sysadmin/diagnostic tools" install_group admin
    run_task "Desktop integration tools" install_desktop_group
    run_task "Bash environment" configure_shell
    run_task "Git and SSH client defaults" configure_git_ssh
    run_task "Portable custom commands" configure_commands
}

profile_full() {
    profile_recommended
    run_task "Vim profile" configure_vim
}

execute_option() {
    case "${1,,}" in
        1|min|minimal) profile_minimal ;;
        2|rec|recommended) profile_recommended ;;
        3|full|all) profile_full ;;
        4|core) run_task "Core distribution packages" install_group core ;;
        5|dev) run_task "Developer toolchain" install_group dev ;;
        6|admin) run_task "Sysadmin/diagnostic tools" install_group admin ;;
        7|desktop) run_task "Desktop integration tools" install_desktop_group ;;
        8|bash|shell) run_task "Bash environment" configure_shell ;;
        9|git|ssh) run_task "Git and SSH client defaults" configure_git_ssh ;;
        10|vim) run_task "Vim profile" configure_vim ;;
        11|commands|tools) run_task "Portable custom commands" configure_commands ;;
        12|privacy|tor) run_task "Privacy tools" configure_privacy_tools ;;
        13|upgrade|update) run_task "System package upgrade" upgrade_system ;;
        14|status|audit) status_report ;;
        15|hardening|hard) run_hardening_assistant ;;
        0|q|quit|exit) return 20 ;;
        *) msg_warn "Unknown selection: $1" ;;
    esac
    return 0
}

interactive_menu() {
    ui_has_tty || { msg_error "Interactive mode requires /dev/tty. Use --recommended/--minimal/--full/--status."; return 1; }
    while true; do
        ui_header "WORKSTATION SETUP" "Select one or multiple entries (example: 5,6,8,9,11). Errors remain visible and the menu continues."
        ui_menu_item "1" "Minimal profile" "Core packages + Bash + Git/SSH + local commands" "$C_GREEN"
        ui_menu_item "2" "Recommended profile" "Developer + sysadmin workstation; does NOT apply Vim/hardening" "$C_GREEN"
        ui_menu_item "3" "Full dotfiles profile" "Recommended + Vim configuration" "$C_YELLOW"
        printf '\n'
        ui_menu_item "4" "Core packages" "Portable baseline from configured official repositories"
        ui_menu_item "5" "Developer toolchain" "Compiler/build/Python/ShellCheck/Git LFS"
        ui_menu_item "6" "Sysadmin tools" "Network/process/storage diagnostics and terminal utilities"
        ui_menu_item "7" "Desktop helpers" "Clipboard/notification integration when graphical desktop exists"
        ui_menu_item "8" "Bash configuration" ".bashrc, aliases and functions"
        ui_menu_item "9" "Git + SSH client" "Preserve personal config; add managed includes"
        ui_menu_item "10" "Vim configuration" "Optional, pluginless, no network bootstrap" "$C_MAGENTA"
        ui_menu_item "11" "Custom commands" "Copy repo utilities to ~/.local/bin"
        ui_menu_item "12" "Privacy tools" "Optional Tor/torsocks packages; no forced service/config"
        ui_menu_item "13" "System upgrade" "Explicit package-manager upgrade; never implicit" "$C_YELLOW"
        ui_menu_item "14" "Readiness / status" "Read-only workstation inventory"
        ui_menu_item "15" "Hardening workspace" "System security policy and rollback" "$C_RED"
        ui_menu_item "0" "Exit" "Leave the assistant" "$C_RED"
        ui_rule

        local input token rc=0
        local -a selections=()
        input="$(ask 'Selection(s)' '2')" || return 1
        input="${input//,/ }"
        IFS=' ' read -r -a selections <<<"$input"
        for token in "${selections[@]}"; do
            [[ -n "$token" ]] || continue
            execute_option "$token" || rc=$?
            (( rc == 20 )) && { show_run_summary; return 0; }
        done
        ui_pause
    done
}

main() {
    local mode="interactive"
    while (($#)); do
        case "$1" in
            --minimal) mode="minimal" ;;
            --recommended) mode="recommended" ;;
            --full|--all) mode="full" ;;
            --status|--audit) mode="status" ;;
            --hardening) mode="hardening" ;;
            --no-color) DOTFILES_NO_COLOR=1; ui_color_init ;;
            --help|-h) usage; return 0 ;;
            *) msg_error "Unknown argument: $1"; usage >&2; return 2 ;;
        esac
        shift
    done

    prepare_context || return 1
    [[ "$mode" == "status" ]] || start_workstation_evidence
    local rc=0
    case "$mode" in
        minimal) profile_minimal; show_run_summary ;;
        recommended) profile_recommended; show_run_summary ;;
        full) profile_full; show_run_summary ;;
        status) status_report || rc=$? ;;
        hardening) run_hardening_assistant || rc=$? ;;
        interactive) interactive_menu || rc=$? ;;
    esac

    if (( rc == 0 )); then
        printf '\n'
        msg_info "Open a new shell (or run: exec bash) to activate a replaced ~/.bashrc."
    fi
    return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    trap 'printf "\n" >&2; msg_warn "Interrupted by user; no package-manager lock files were removed."; exit 130' INT TERM
    main "$@"
fi
