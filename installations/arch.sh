#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR=$(dirname -- "$(readlink -f -- "$0")")

source "${CURRENT_DIR}/../lib/common.sh"

KEYMAP="${KEYMAP:-es}"                    
TIMEZONE="${TIMEZONE:-Europe/London}"     
LOCALE="${LOCALE:-es_ES.UTF-8}"       
LOCALE_GEN="${LOCALE_GEN:-es_ES.UTF-8 UTF-8}" #etc/locale.gen
HOSTNAME="${HOSTNAME:-archlinux}"         
TARGET_USER="${TARGET_USER:-usuario}"      
CONSOLEFONT="${CONSOLEFONT:-ter-132b}"

ROOT_PASSWORD="${ROOT_PASSWORD:-}"
USER_PASSWORD="${USER_PASSWORD:-}"


# Verify system architecture compatibility
if [[ "$(detect_distribution)" != "arch" ]]; then
    msg_error "Unsupported distribution. This installation script requires Arch Linux to proceed."
    exit 1
fi


setup_console() {
    # WSL handles fonts and keymaps through the Windows host terminal
    if is_wsl; then
        msg_info "WSL environment detected. Skipping TTY font and keymap configuration."
        return 0
    fi

   if command_exists setfont; then
        if setfont "$FONT" 2>/dev/null; then
            msg_success "Console font set to '$FONT'."
        elif setfont "default8x16" 2>/dev/null; then
            msg_warn "Font '$FONT' not found. Fallback font 'default8x16' applied."
        else
            msg_warn "Unable to load console font '$FONT' or default fallback."
        fi
    fi
}


main() {
    setup_console
}

main