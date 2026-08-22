#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR=$(dirname -- "$(readlink -f -- "$0")")

source "${CURRENT_DIR}/lib/common.sh"

# Globales del usuario objetivo (evita recalcularlas en cada función)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

print_section() {
    local title="$1"
    echo -e "\n${cyanColour}======================================================================${endColour}"
    echo -e "${cyanColour}  :: ${title}${endColour}"
    echo -e "${cyanColour}======================================================================${endColour}\n"
}

configure_bash_files() {
    print_section "Configuring Bash Dotfiles"

    local source_dir="$CURRENT_DIR/bash/conf"

    if [[ ! -d "$source_dir" ]]; then
        msg_error "Source directory '$source_dir' not found. Skipping Bash configuration."
        return 1
    fi

    local files=(".bashrc" ".bash.aliases" ".bash.functions")

    for file in "${files[@]}"; do
        local src="$source_dir/$file"
        local dest="$TARGET_HOME/$file"

        if [[ -f "$src" ]]; then
            copy_with_backup "$src" "$dest" "$TARGET_USER"
        else
            msg_warn "Optional file '$file' not found in '$source_dir', skipping."
        fi
    done

    msg_success "Bash dotfiles successfully configured for user '$TARGET_USER'!"
}

configure_git() {
    print_section "Configuring Git"

    if ! command -v git &>/dev/null; then
        msg_error "Git binary not found in PATH. Please ensure it is installed in your distro setup script."
        return 1
    fi

    local src="$CURRENT_DIR/git/.gitconfig"
    local dest="$TARGET_HOME/.gitconfig"

    if [[ ! -f "$src" ]]; then
        msg_error "Git configuration source file not found at: '$src'"
        return 1
    fi

    copy_with_backup "$src" "$dest" "$TARGET_USER"
    msg_success "Git configured successfully for user '$TARGET_USER'!"
}

configure_vim() {
    print_section "Configuring Vim"

    if [[ -d "$TARGET_HOME/.vim_runtime" ]]; then
        msg_warn "Vim configuration (.vim_runtime) already exists. Skipping."
        return 0
    fi

    msg_info "Cloning amix/vimrc repository for user '$TARGET_USER'..."

    if ! sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/amix/vimrc.git "$TARGET_HOME/.vim_runtime" &>/dev/null; then
        msg_error "Failed to clone amix/vimrc repository."
        return 1
    fi

    msg_info "Executing vimrc setup script..."
    if ! sudo -u "$TARGET_USER" sh "$TARGET_HOME/.vim_runtime/install_basic_vimrc.sh" &>/dev/null; then
        msg_error "Failed to run amix/vimrc installer script."
        return 1
    fi

    msg_success "Vim configured successfully for '$TARGET_USER'!"
}

configure_bat_symlink() {
    if command -v batcat &>/dev/null; then
        local batcat_path
        batcat_path=$(command -v batcat)
        local bin_dir="$TARGET_HOME/.local/bin"
        local symlink="$bin_dir/bat"

        if [[ ! -f "$symlink" && ! -L "$symlink" ]]; then
            msg_info "Creating symlink 'bat' -> 'batcat' in $bin_dir..."
            sudo -u "$TARGET_USER" mkdir -p "$bin_dir"
            sudo -u "$TARGET_USER" ln -s "$batcat_path" "$symlink"
            msg_success "Symlink for 'bat' created successfully!"
        fi
    fi
}

# ------------------------------------------------------------------------------
# MAIN EXECUTION
# ------------------------------------------------------------------------------
main() {
    if [[ $(uname -s) != "Linux" ]]; then
        msg_error "This script is only compatible with Linux distributions."
        exit 1
    fi

    if [[ $EUID -ne 0 ]]; then
        msg_warn "Root privileges required. Re-running with sudo..."
        exec sudo "$0" "$@"
    fi

    clear
    print_section "Environment Setup - Initializing"

    local os_distribution
    os_distribution=$(detect_distribution) || exit 1

    msg_info "Target User: $TARGET_USER"
    msg_info "Target Home: $TARGET_HOME"
    msg_info "Detected Distribution: ${os_distribution:-Unknown}"

    local os_module_path="${CURRENT_DIR}/bash/distros/${os_distribution}.sh"
    
    if [[ -f "${os_module_path}" ]]; then
        msg_info "Loading distro module: ${os_distribution}.sh"
        source "${os_module_path}"
    else
        msg_warn "No specific module found for '${os_distribution}'. Proceeding with generic configuration..."
    fi

    configure_bash_files
    configure_git
    configure_vim
    configure_bat_symlink

    print_section "Setup Complete"
    msg_success "The environment is ready to use!"
    #msg_info "Run 'exec bash' or restart your terminal to apply changes."

    ## Auto source the terminal to see the changes
    if [[ $- == *i* ]]; then
        if ! shopt -q login_shell; then
            source ~/.bashrc
        fi
    fi
}

main "$@"
