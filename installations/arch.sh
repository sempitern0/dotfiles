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

BOOT_MODE="unknown"

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

    if command_exists loadkeys; then
        loadkeys $KEYMAP
    fi

   if command_exists setfont; then
        if setfont "$CONSOLEFONT" 2>/dev/null; then
            msg_success "Console font set to '$CONSOLEFONT'."
        elif setfont "default8x16" 2>/dev/null; then
            msg_warn "Font '$CONSOLEFONT' not found. Fallback font 'default8x16' applied."
        else
            msg_warn "Unable to load console font '$CONSOLEFONT' or default fallback."
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

        ## By default, WSL will try to set your locale to match windows, this command overrides the locale.
        ln -sf /etc/locale.conf /etc/default/locale

    else
        msg_info "Native environment detected. Skipping WSL-specific configurations."
    fi
}

detect_boot_mode() {
    msg_info "Detecting System Boot Mode..."

    # Bypass firmware checks under WSL
    if is_wsl; then
        msg_info "WSL environment detected. Bootloader setup will be skipped."
        BOOT_MODE="wsl"
        return 0
    fi

    local efi_file="/sys/firmware/efi/fw_platform_size"

    if [[ -f "$efi_file" ]]; then
        local fw_size
        fw_size=$(cat "$efi_file" 2>/dev/null || echo "")

        case "$fw_size" in
            64)
                msg_success "Boot mode: UEFI 64-bit (x64)."
                BOOT_MODE="uefi64"
                ;;
            32)
                msg_warn "Boot mode: UEFI 32-bit (IA32). Requires mixed-mode bootloader support."
                BOOT_MODE="uefi32"
                ;;
            *)
                msg_warn "UEFI detected, but unknown platform size ('$fw_size')."
                BOOT_MODE="uefi_unknown"
                ;;
        esac
    else
        msg_info "File '$efi_file' not found. Boot mode: BIOS / CSM."
        BOOT_MODE="bios"
    fi

}

install_bootloader() {
    case "$BOOT_MODE" in
        wsl)
            msg_info "Skipping bootloader installation for WSL environment."
            ;;
        uefi64)
            msg_info "Installing GRUB for 64-bit UEFI system..."
            # pacman -S --noconfirm grub efibootmgr
            # grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
            ;;
        uefi32)
            msg_warn "Installing GRUB for 32-bit UEFI system (IA32)..."
            # pacman -S --noconfirm grub efibootmgr
            # grub-install --target=i386-efi --efi-directory=/boot --bootloader-id=GRUB
            ;;
        bios)
            msg_info "Installing GRUB for BIOS/CSM system..."
            # pacman -S --noconfirm grub
            # grub-install --target=i386-pc /dev/sda
            ;;
        *)
            msg_error "Cannot install bootloader: Unrecognized boot mode '$BOOT_MODE'."
            return 1
            ;;
    esac

}

check_internet_connection() {
    msg_info "Checking internet connection..."

    # Attempt to ping the official Arch Linux server
    if ping -c 2 ping.archlinux.org >/dev/null 2>&1; then
        msg_success "Internet connection established."
        return 0
    fi

    msg_warn "No internet connection detected."

    if is_wsl; then
        msg_error "Running under WSL. Please check your Windows host network configuration."
        return 1
    fi

    # Diagnostic output for native environment / Arch Live ISO
    msg_info "Listing system network interfaces:"
    ip -br link show 2>/dev/null || ip link

    # Check and unblock wireless interfaces blocked by rfkill
    if command_exists rfkill; then
        if rfkill list 2>/dev/null | grep -q "blocked: yes"; then
            msg_warn "Interfaces blocked by rfkill detected. Unblocking all..."
            rfkill unblock all
        fi
    fi

    msg_error "An active internet connection is required to proceed."
    echo -e "${yellowColour}Recommended steps from the Arch Wiki:${endColour}"
    echo "  - Ethernet: Ensure your cable is connected."
    echo "  - Wi-Fi: Authenticate using 'iwctl'."
    echo "  - Mobile Broadband: Connect using 'mmcli'."
    
    return 1
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
    detect_boot_mode
    check_internet_connection || exit 1
    
    setup_wsl_integrations
}

main