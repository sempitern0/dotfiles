#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR=$(dirname -- "$(readlink -f -- "$0")")

source "${CURRENT_DIR}/lib/common.sh"

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

    if ! command_exists git; then
        msg_error "Git binary not found in PATH. Please ensure it is installed in your distro setup script."
        return 1
    fi

    # --- Git Configuration ---
    local git_src="$CURRENT_DIR/git/.gitconfig"
    local git_dest="$TARGET_HOME/.gitconfig"

    if [[ ! -f "$git_src" ]]; then
        msg_error "Git configuration source file not found at: '$git_src'"
        return 1
    fi

    copy_with_backup "$git_src" "$git_dest" "$TARGET_USER"
    msg_success "Git configured successfully for user '$TARGET_USER'!"

    # --- SSH Configuration ---
    local ssh_src="$CURRENT_DIR/git/ssh/config"
    local ssh_dir="$TARGET_HOME/.ssh"
    local ssh_dest="$ssh_dir/config"

    mkdir -p ~/.ssh/sockets
    
    if [[ -f "$ssh_src" ]]; then
        msg_info "Copying SSH configuration..."

        # Ensure ~/.ssh directory exists with correct permissions (700)
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown "$TARGET_USER:" "$ssh_dir" 2>/dev/null || true

        # Copy SSH config file with backup
        copy_with_backup "$ssh_src" "$ssh_dest" "$TARGET_USER"

        # Set strict permissions required by SSH (600)
        chmod 600 "$ssh_dest"
        chown "$TARGET_USER:" "$ssh_dest" 2>/dev/null || true

        msg_success "SSH configuration copied with secure permissions (600)!"
    else
        msg_warn "SSH configuration source file not found at: '$ssh_src'. Skipping SSH setup."
    fi
}

configure_vim() {
    print_section "Configuring Vim"

    # Check for existing Vim configuration and prompt user for overwrite permission
    if [[ -d "$TARGET_HOME/.vim_runtime" ]] || [[ -f "$TARGET_HOME/.vimrc" ]]; then
        if prompt_confirmation "Vim configuration (.vim_runtime or .vimrc) already exists. Do you want to overwrite it?" "N"; then
            msg_info "Removing existing Vim configuration..."
            rm -rf "$TARGET_HOME/.vim_runtime" "$TARGET_HOME/.vimrc"
        else
            return 0
        fi
    fi

    local fallback_src="$CURRENT_DIR/vim/.vimrc"
    local fallback_dest="$TARGET_HOME/.vimrc"

    if [[ -f "$fallback_src" ]]; then
        msg_info "Applying local fallback Vim configuration from '$fallback_src'..."

        copy_with_backup "$fallback_src" "$fallback_dest" "$TARGET_USER"
        chmod 644 "$fallback_dest"
        chown "$TARGET_USER:" "$fallback_dest" 2>/dev/null || true

        msg_success "Local Vim fallback configuration deployed successfully for '$TARGET_USER'!"
    else
        msg_error "Local fallback Vim configuration file not found at: '$fallback_src'"
        return 1
    fi
}

configure_bat_symlink() {
    if command_exists batcat; then
        local batcat_path=$(command -v batcat)

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
        exec sudo -E "$0" "$@"
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

}

main "$@"

## Auto source the terminal to see the changes
if [[ $- == *i* ]]; then
    if ! shopt -q login_shell; then
        source ~/.bashrc
    fi
fi