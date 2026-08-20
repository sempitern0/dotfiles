#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR=$(dirname -- "$(readlink -f -- "$0")")

source "${CURRENT_DIR}/lib/common.sh"


configure_bash_files() {
    msg_info "Configuring Bash dotfiles..."

    local target_user="${SUDO_USER:-$USER}"
    local target_home
    target_home=$(getent passwd "$target_user" | cut -d: -f6)

    local source_dir="$CURRENT_DIR/bash/conf"

    if [ ! -d "$source_dir" ]; then
        msg_error "Source directory '$source_dir' not found in the repository."
        return 1
    fi

    local files=(".bashrc" ".bash.aliases" ".bash.functions")

    for file in "${files[@]}"; do
        local src="$source_dir/$file"
        local dest="$target_home/$file"

        if [ -f "$src" ]; then
            if [ -f "$dest" ]; then
                msg_info "Backing up existing $file to $file.bak"
                cp "$dest" "$dest.bak"
            fi

            msg_info "Copying $file to $target_home..."
            cp "$src" "$dest"

            chown "$target_user:$target_user" "$dest"
            [ -f "$dest.bak" ] && chown "$target_user:$target_user" "$dest.bak"
        else
            msg_warn "File '$file' not found in '$source_dir', skipping."
        fi
    done

    msg_success "Bash dotfiles successfully configured for user $target_user!"
}

configure_vim() {
    local target_user="${SUDO_USER:-$USER}"
    local target_home
    target_home=$(getent passwd "$target_user" | cut -d: -f6)

    if [ -d "$target_home/.vim_runtime" ]; then
        msg_warn "Vim configuration (.vim_runtime) already exists for $target_user. Skipping installation."
        return 0
    fi

    msg_info "Configuring Vim with amix/vimrc for user $target_user..."

    if ! sudo -u "$target_user" git clone --depth=1 https://github.com/amix/vimrc.git "$target_home/.vim_runtime" &> /dev/null; then
        msg_error "Failed to clone amix/vimrc repository."
        return 1
    fi

    if ! sudo -u "$target_user" sh "$target_home/.vim_runtime/install_basic_vimrc.sh" &> /dev/null; then
        msg_error "Failed to run amix/vimrc installer script."
        return 1
    fi

    msg_success "Vim successfully configured for $target_user!"
}


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
    print_separator
    echo -e "${cyanColour}Preparing the environment...${endColour}"
    print_separator

    local real_user="${SUDO_USER:-$USER}"
    local real_home=$(getent passwd "$real_user" | cut -d: -f6)
    local os_distribution=$(detect_distribution) || exit 1

    if [[ -z "${os_distribution}" ]]; then
        msg_error "Unsupported distribution: ID='${os_distribution}'"
        exit 1
    fi

    local os_module_path="${CURRENT_DIR}/bash/distros/${os_distribution}.sh"

    if [[ ! -f "${os_module_path}" ]]; then
        msg_error "Module not found: ${os_module_path}"
        exit 1
    fi

    msg_info "Detected distribution: ${os_distribution} -> Loading module: ${os_distribution}.sh"
    
    source "${os_module_path}"

    print_separator
    configure_bash_files
    print_separator
    configure_vim

    if command -v batcat &> /dev/null; then
        if [ ! -f "$real_home/.local/bin/bat" ]; then
            msg_info "Creating symlink for 'bat' command..."
            mkdir -p "$real_home/.local/bin"
            ln -s /usr/bin/batcat "$real_home/.local/bin/bat"
            chown -R "$real_user:$real_user" "$real_home/.local/bin"
        fi
    fi

    msg_success "The environment is ready to use, enjoy!"
}

main "$@"

## Auto source the terminal to see the changes
if [[ $- == *i* ]]; then
    if ! shopt -q login_shell; then
        source ~/.bashrc
    fi
fi