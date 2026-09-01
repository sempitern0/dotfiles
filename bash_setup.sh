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
configure_tor() {
    print_section "Configuring Tor and Torsocks"

    local tor_user="tor"

    # Install Tor and Torsocks based on the available package manager
    if command_exists apt-get; then
        msg_info "Installing Tor and Torsocks via apt..."
        apt-get update -y
        apt-get install -y tor torsocks
        tor_user="debian-tor"
    elif command_exists pacman; then
        msg_info "Installing Tor and Torsocks via pacman..."
        pacman -Sy --noconfirm tor torsocks
        tor_user="tor"
    else
        msg_error "Unsupported package manager. Unable to install Tor and Torsocks."
        return 1
    fi

    # --- Deploy /etc/tor/torrc ---
    local torrc="/etc/tor/torrc"
    msg_info "Deploying hardened Tor client configuration..."

    if [[ -f "$torrc" ]]; then
        cp "$torrc" "${torrc}.bak" 2>/dev/null || true
    fi

    # Note: RunAsDaemon is omitted because systemd manages process daemonization
    cat << 'EOF' > "$torrc"
# Hardened Tor Client Configuration
SocksPort 127.0.0.1:9050 IsolateClientAddr IsolateSOCKSAuth
SocksPolicy accept 127.0.0.1
SocksPolicy reject *

# Prevent DNS leaks
DNSPort 127.0.0.1:5353

# Process hardening options
DataDirectory /var/lib/tor
EOF
    chmod 644 "$torrc"

    # --- Ensure correct directory permissions ---
    msg_info "Setting secure permissions on /var/lib/tor..."
    mkdir -p /var/lib/tor
    chown -R "${tor_user}:${tor_user}" /var/lib/tor
    chmod 700 /var/lib/tor

    # --- Deploy /etc/tor/torsocks.conf ---
    local torsocks_conf="/etc/tor/torsocks.conf"
    msg_info "Deploying Torsocks wrapper configuration..."

    if [[ -f "$torsocks_conf" ]]; then
        cp "$torsocks_conf" "${torsocks_conf}.bak" 2>/dev/null || true
    fi

    cat << 'EOF' > "$torsocks_conf"
# Hardened Torsocks Configuration
TorAddress 127.0.0.1
TorPort 9050
OnL2FTN Reject
IsolatePID 1
EOF
    chmod 644 "$torsocks_conf"

    # --- Verify Tor configuration syntax ---
    msg_info "Verifying Tor configuration syntax..."
    if ! sudo -u "$tor_user" tor --verify-config -f "$torrc" &>/dev/null; then
        msg_error "Tor configuration validation failed."
        return 1
    fi

    # --- Systemd Service Integration ---
    msg_info "Enabling and starting Tor system service..."
    systemctl daemon-reload
    systemctl reset-failed tor.service 2>/dev/null || true
    systemctl enable --now tor

    msg_success "Tor and Torsocks installed, configured, and service started successfully!"
}

## To restore the system use sudo timeshift --restor
## By defaul timeshift exclude the user /home directory
configure_system_snapshot() {
    print_section "Creating System Snapshot"

     if is_wsl; then
        msg_error "WSL environment detected, aborting system snapshot..."
        return 1
    fi

    if ! command_exists timeshift; then
        msg_info "Timeshift is not installed. Attempting installation..."
        if command_exists apt-get; then
            apt-get update -y
            apt-get install -y timeshift
        elif command_exists pacman; then
            pacman -Sy --noconfirm timeshift
        else
            msg_error "Unsupported package manager. Unable to install Timeshift."
            return 1
        fi
    fi

    local timestamp
    timestamp=$(date +'%Y-%m-%d_%H-%M-%S')
    local comment="Post-setup auto snapshot ($timestamp)"

    msg_info "Generating system snapshot: '$comment'..."

    if timeshift --create --comments "$comment" --tags D; then
        msg_success "System snapshot created successfully!"
    else
        msg_error "Failed to create system snapshot."
        return 1
    fi
}

configure_custom_commands() {
    print_section "Configuring Custom System Commands"

    local tools_src_dir="$CURRENT_DIR/bash/bin"
    local bin_dest_dir="$TARGET_HOME/.local/bin"

    if [[ ! -d "$tools_src_dir" ]]; then
        msg_warn "Source directory '$tools_src_dir' not found. Skipping custom commands setup."
        return 0
    fi

    sudo -u "$TARGET_USER" mkdir -p "$bin_dest_dir"

    msg_info "Cleaning up broken symlinks in '$bin_dest_dir'..."
    find "$bin_dest_dir" -xtype l -delete 2>/dev/null || true

    msg_info "Scanning recursively for scripts in '$tools_src_dir'..."

    while IFS= read -r -d '' tool_path; do
        local tool_file
        tool_file=$(basename "$tool_path")

        local command_name="${tool_file%.sh}"
        local dest_link="$bin_dest_dir/$command_name"

        if is_wsl; then
            chmod +x "$tool_path" 2>/dev/null || true
        else
            chmod +x "$tool_path"
        fi

        msg_info "Creating symlink: '$command_name' -> '$dest_link' (from ${tool_path#$tools_src_dir/})"
        sudo -u "$TARGET_USER" ln -sf "$tool_path" "$dest_link"
    done < <(find "$tools_src_dir" -type f \( -name "*.sh" -o -perm /111 \) -print0)

    msg_success "Custom commands successfully linked to '$bin_dest_dir'!"
}

cleanup() {
    local exit_code=$?
    msg_error "[!] Script execution interrupted by user (Ctrl + C). Cleaning up...${endColour}"

   # --- Timeshift Locks ---
    rm -f /var/run/timeshift.lock 2>/dev/null || true
    rm -rf /tmp/timeshift* 2>/dev/null || true

    # --- APT / DPKG Locks (Debian, Ubuntu, Kali, Mint) ---
    rm -f /var/lib/dpkg/lock \
          /var/lib/dpkg/lock-frontend \
          /var/lib/apt/lists/lock \
          /var/cache/apt/archives/lock 2>/dev/null || true

    # --- Pacman Locks (Arch Linux, Manjaro, EndeavourOS) ---
    rm -f /var/lib/pacman/db.lck 2>/dev/null || true

    # --- DNF / YUM Locks (Fedora, RHEL, CentOS, AlmaLinux) ---
    rm -f /var/run/dnf.lock \
          /var/run/yum.pid \
          /var/lib/dnf/lock 2>/dev/null || true

    # --- Zypper Locks (openSUSE) ---
    rm -f /var/run/zypp.pid 2>/dev/null || true

    # --- Snapd & Flatpak Locks ---
    rm -f /var/lib/snapd/state.json.lock 2>/dev/null || true
    
    msg_warn "Execution stopped. The next run will start fresh from the beginning."
    exit "${exit_code:-1}"
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
    configure_custom_commands
    configure_tor
    configure_system_snapshot

    print_section "Setup Complete"
    msg_success "The environment is ready to use!"
    msg_info "Run 'exec bash' or 'source ~/.bashrc' or restart your terminal to apply changes."
}

trap cleanup INT TERM
main "$@"

## Auto source the terminal to see the changes
if [[ $- == *i* ]]; then
    if ! shopt -q login_shell; then
        source ~/.bashrc
    fi
fi