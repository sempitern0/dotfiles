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


verify_distribution() {
    msg_info "Checking Linux distribution requirements..."
    
    if [[ "$(detect_distribution)" != "arch" ]]; then
        msg_error "Unsupported distribution. This script requires Arch Linux to proceed."
        exit 1
    fi
    
    msg_success "Distribution check passed: Arch Linux detected."
}

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

review_configuration() {
    msg_info "Reviewing Target Installation Settings"
    
    echo -e "  - Target OS:    ${cyanColour}Arch Linux${endColour}"
    echo -e "  - Keymap:       ${cyanColour}${KEYMAP}${endColour}"
    echo -e "  - Timezone:     ${cyanColour}${TIMEZONE}${endColour}"
    echo -e "  - Locale:       ${cyanColour}${LOCALE}${endColour}"
    echo -e "  - Hostname:     ${cyanColour}${HOSTNAME}${endColour}"
    echo -e "  - Target User:  ${cyanColour}${TARGET_USER}${endColour}"
    echo -e "  - Console Font: ${cyanColour}${CONSOLEFONT}${endColour}"
    echo

    if ! prompt_confirmation "Proceed with execution using these parameters?"; then
        msg_error "Execution aborted by user."
        exit 0
    fi

    msg_success "Step [${CURRENT_STEP}/${TOTAL_STEPS}] completed: Configuration confirmed."
}

main() {
    check_root
    verify_distribution
    review_configuration
    setup_console
}

main