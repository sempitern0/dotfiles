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

# This needs to be executed after creating the local user
setup_wsl_integrations() {
    if is_wsl; then
        msg_info "Applying System Integrations for WSL environment"
        msg_info "Writing /etc/wsl.conf..."
        cat <<EOF > /etc/wsl.conf
[user]
default=${TARGET_USER}

[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=true
EOF
        msg_success "/etc/wsl.conf generated successfully."

        msg_info "Configuring environment variables for WSLg Direct3D12..."
        local bashrc="/home/${TARGET_USER}/.bashrc"
        if [[ -f "$bashrc" ]]; then
            {
                echo '# WSLg Graphics Acceleration'
                echo 'export GALLIUM_DRIVER=d3d12'
                echo 'export LIBVA_DRIVER_NAME=d3d12'
            } >> "$bashrc"
        fi
        
        # Install WSL specific utility packages
        msg_info "Installing WSL interoperability utilities..."
        pacman -S --noconfirm --needed xdg-utils mesa vulkan-icd-loader >/dev/null 2>&1 || msg_warn "Package sync skipped or non-interactive failure."
    else
        msg_info "Native environment detected. Skipping WSL-specific configurations."
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
}

main() {
    check_root
    verify_distribution
    review_configuration
    setup_console
    setup_wsl_integrations
}

main