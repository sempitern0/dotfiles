#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR=$(dirname -- "$(readlink -f -- "$0")")

source "${CURRENT_DIR}/lib/common.sh"

prepare_distribution() {
    if [[ ! -f /etc/os-release ]]; then
        msg_error "Distribution could not be identified (/etc/os-release does not exist)."
        exit 1
    fi

    source /etc/os-release

    local os_id="${ID:-}"
    local os_like="${ID_LIKE:-}"
    local target_module=""

    case "${os_id}" in
        debian|ubuntu|pop|mint|kali|raspbian) target_module="debian" ;;
        arch|manjaro|endeavouros|garuda)       target_module="arch" ;;
        fedora|rhel|centos)                    target_module="fedora" ;;
    esac

    if [[ -z "${target_module}" && -n "${os_like}" ]]; then
        for family in ${os_like}; do
            case "${family}" in
                debian|ubuntu) target_module="debian"; break ;;
                arch)          target_module="arch"; break ;;
                fedora|rhel)   target_module="fedora"; break ;;
            esac
        done
    fi

    if [[ -z "${target_module}" ]]; then
        msg_error "Unsupported distribution: ID='${os_id}'"
        exit 1
    fi

    local module_path="${CURRENT_DIR}/distros/${target_module}.sh"

    if [[ ! -f "${module_path}" ]]; then
        msg_error "Module not found: ${module_path}"
        exit 1
    fi

    msg_info "Detected distribution: ${os_id} -> Loading module: ${target_module}.sh"
    
    source "${module_path}"
}

configure_bash_files() {
    msg_info "Configuring Bash dotfiles..."

    local target_user="${SUDO_USER:-$USER}"
    local target_home
    target_home=$(getent passwd "$target_user" | cut -d: -f6)

    local source_dir="$CURRENT_DIR/bash"

    if [ ! -d "$source_dir" ]; then
        msg_error "Source directory '$source_dir' not found in the repository."
        return 1
    fi

    # Corrección de la errata en .bash.aliases
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

    clear
    print_separator
    echo -e "${cyanColour}Preparing the environment...${endColour}"
    print_separator

    local real_user="${SUDO_USER:-$USER}"
    local real_home
    real_home=$(getent passwd "$real_user" | cut -d: -f6)

    prepare_distribution
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