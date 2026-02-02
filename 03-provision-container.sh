#!/bin/bash
#
# 03-provision-container.sh
# Installs complete dev stack in LXC container and connects to Tailscale
# Run as root or with sudo
#
# Usage: ./03-provision-container.sh <container-name> <tailscale-authkey> [options]
# Example: ./03-provision-container.sh relay-dev tskey-auth-xxxxxxxx
#
# Features:
# - Tailscale VPN for direct IP access (100.x.x.x)
# - Node.js 22 via nvm with npm, yarn, pnpm
# - PostgreSQL with dev/dev credentials
# - Playwright with Chromium and Firefox
# - Claude Code CLI
# - Shell environment with database vars and aliases
# - Git/GitHub credentials (SSH keys, .gitconfig, gh CLI) from host
# - Claude Code credentials from host
#

set -euo pipefail

# Trap for clean error messages
trap 'log_error "Script failed at line $LINENO"' ERR

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -------------------------------------------
# Argument Handling
# -------------------------------------------
if [[ $# -lt 2 ]]; then
    echo "Usage: ./03-provision-container.sh <container-name> <tailscale-authkey> [options]"
    echo "       ./03-provision-container.sh <container-name> --no-tailscale [options]"
    echo ""
    echo "Example: ./03-provision-container.sh relay-dev tskey-auth-xxxxxxxx"
    echo ""
    echo "Arguments:"
    echo "  container-name    Name of existing LXC container (created by 02-create-container.sh)"
    echo "  tailscale-authkey Reusable auth key from Tailscale admin console"
    echo "                    Get one at: https://login.tailscale.com/admin/settings/keys"
    echo ""
    echo "Options:"
    echo "  --no-tailscale    Skip Tailscale setup (local development only)"
    echo ""
    echo "Note: Git credentials (SSH keys, .gitconfig, gh CLI) and Claude Code credentials"
    echo "      are automatically copied from the host user who runs sudo."
    exit 1
fi

CONTAINER_NAME="$1"
TAILSCALE_AUTHKEY="$2"
SKIP_TAILSCALE=false

if [[ "$TAILSCALE_AUTHKEY" == "--no-tailscale" ]]; then
    SKIP_TAILSCALE=true
fi

# Parse additional options
shift 2
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-tailscale)
            # Allow --no-tailscale as trailing option too
            SKIP_TAILSCALE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Configuration variables
NVM_VERSION="v0.40.4"
NODE_VERSION="22"
PG_USER="dev"
PG_PASS="dev"
PG_DB="dev"

# -------------------------------------------
# Validate Container Exists
# -------------------------------------------
if ! lxc info "$CONTAINER_NAME" &>/dev/null; then
    log_error "Container '$CONTAINER_NAME' does not exist"
    echo ""
    echo "Create it first with:"
    echo "  ./02-create-container.sh $CONTAINER_NAME"
    exit 1
fi

# -------------------------------------------
# Validate Tailscale Auth Key Format
# -------------------------------------------
if [[ "$SKIP_TAILSCALE" == false ]]; then
    if [[ ! "$TAILSCALE_AUTHKEY" =~ ^tskey- ]]; then
        log_error "Invalid Tailscale auth key format"
        echo ""
        echo "Auth key must start with 'tskey-'"
        echo "Get a key at: https://login.tailscale.com/admin/settings/keys"
        echo ""
        echo "Recommended settings:"
        echo "  - Reusable: Yes"
        echo "  - Ephemeral: Yes (optional, auto-removes device on container delete)"
        echo ""
        echo "Or use --no-tailscale to skip Tailscale setup"
        exit 1
    fi
fi

# -------------------------------------------
# Root Check (after arg validation for better UX)
# -------------------------------------------
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (or with sudo)"
    exit 1
fi

# -------------------------------------------
# Helper Functions
# -------------------------------------------

# Execute command inside the container (as root)
container_exec() {
    lxc exec "$CONTAINER_NAME" -- bash -c "$1"
}

# Execute command inside the container as dev user
container_exec_as_dev() {
    lxc exec "$CONTAINER_NAME" -- su - dev -c "$1"
}

# Wait for apt lock to be released (cloud-init may be running)
wait_for_apt_lock() {
    container_exec '
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
            sleep 1
        done
    '
}

# Validate TUN device exists in container (required for Tailscale)
validate_tun_device() {
    log_info "Checking TUN device availability..."

    if ! container_exec 'ls /dev/net/tun &>/dev/null'; then
        log_error "TUN device not found in container"
        echo ""
        echo "The container needs a TUN device for Tailscale."
        echo "This should have been configured by 02-create-container.sh"
        echo ""
        echo "To fix manually:"
        echo "  lxc config device add $CONTAINER_NAME tun unix-char path=/dev/net/tun"
        echo "  lxc restart $CONTAINER_NAME"
        exit 1
    fi

    log_info "TUN device available"
}

# -------------------------------------------
# Dev User Setup
# -------------------------------------------

# Create non-root dev user for Claude Code YOLO mode
# Claude Code's --dangerously-skip-permissions doesn't work as root
create_dev_user() {
    log_info "Creating dev user..."

    # Check if user already exists
    if container_exec 'id dev &>/dev/null'; then
        log_info "Dev user already exists"
        return 0
    fi

    container_exec '
        # Create dev user with home directory and bash shell
        useradd -m -s /bin/bash dev

        # Add to sudo group with passwordless sudo
        echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev
        chmod 440 /etc/sudoers.d/dev

        # Create projects directory
        mkdir -p /home/dev/projects
        chown dev:dev /home/dev/projects
    '

    log_info "Dev user created with passwordless sudo"
}

# -------------------------------------------
# Tailscale Installation (PROV-02, PROV-03, PROV-04)
# -------------------------------------------

# Wait for Tailscale to establish connection
wait_for_tailscale() {
    local timeout=60
    local elapsed=0
    local spinstr='|/-\'

    echo -n "  Waiting for Tailscale connection..."

    while [[ $elapsed -lt $timeout ]]; do
        if container_exec 'tailscale status 2>/dev/null | grep -q "^100\."'; then
            printf "\r\033[K"  # Clear line
            local ts_ip
            ts_ip=$(container_exec 'tailscale ip -4')
            log_info "Tailscale connected: $ts_ip"
            return 0
        fi

        local temp=${spinstr#?}
        printf "\r  [%c] Waiting for Tailscale... (%ds/%ds)" "$spinstr" "$elapsed" "$timeout"
        spinstr=$temp${spinstr%"$temp"}

        sleep 1
        ((elapsed++))
    done

    printf "\r\033[K"  # Clear line
    log_error "Tailscale connection timed out after ${timeout}s"
    echo "Container left running for debugging:"
    echo "  lxc exec $CONTAINER_NAME -- tailscale status"
    echo "  lxc exec $CONTAINER_NAME -- journalctl -u tailscaled"
    return 1
}

# Install and connect Tailscale
install_tailscale() {
    log_info "Setting up Tailscale..."

    # Validate TUN device before proceeding
    validate_tun_device

    # Check if already installed and connected
    if container_exec 'command -v tailscale &>/dev/null'; then
        if container_exec 'tailscale status 2>/dev/null | grep -q "^100\."'; then
            local ts_ip
            ts_ip=$(container_exec 'tailscale ip -4')
            log_info "Tailscale already connected: $ts_ip"
            return 0
        fi
        log_info "Tailscale installed but not connected, connecting..."
    else
        log_info "Installing Tailscale..."
        container_exec 'curl -fsSL https://tailscale.com/install.sh | sh'
    fi

    # Connect with authkey
    log_info "Connecting to Tailscale..."
    container_exec "tailscale up --authkey='$TAILSCALE_AUTHKEY'"

    # Wait for connection with timeout (60s per CONTEXT.md)
    wait_for_tailscale
}

# -------------------------------------------
# PostgreSQL Installation (PROV-07, PROV-08)
# -------------------------------------------

# Create PostgreSQL user and database
create_pg_user_db() {
    log_info "Creating PostgreSQL user and database..."

    # Create user if not exists
    container_exec "sudo -u postgres psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$PG_USER'\" | grep -q 1 || sudo -u postgres createuser $PG_USER"

    # Set password
    container_exec "sudo -u postgres psql -c \"ALTER USER $PG_USER WITH PASSWORD '$PG_PASS';\""

    # Create database if not exists
    container_exec "sudo -u postgres psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$PG_DB'\" | grep -q 1 || sudo -u postgres createdb -O $PG_USER $PG_DB"

    # Install pgcrypto extension (per RESEARCH.md recommendation for gen_random_uuid)
    container_exec "sudo -u postgres psql -d $PG_DB -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto;'"

    log_info "PostgreSQL user '$PG_USER', database '$PG_DB' ready"
}

# Configure PostgreSQL for remote access via Tailscale
configure_pg_remote_access() {
    log_info "Configuring PostgreSQL for remote access..."

    container_exec '
        # Find PostgreSQL version directory
        PG_VERSION=$(ls /etc/postgresql/)
        PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
        PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

        # Listen on all interfaces (for Tailscale access)
        sed -i "s/#listen_addresses = '"'"'localhost'"'"'/listen_addresses = '"'"'*'"'"'/" "$PG_CONF"

        # Check if trust rules already exist
        if ! grep -q "host.*all.*all.*0.0.0.0/0.*trust" "$PG_HBA"; then
            # Add trust authentication for all connections (dev only!)
            echo "# Allow all connections with trust (dev environment)" >> "$PG_HBA"
            echo "host    all    all    0.0.0.0/0    trust" >> "$PG_HBA"
            echo "host    all    all    ::0/0        trust" >> "$PG_HBA"
        fi

        # Restart PostgreSQL to apply changes
        systemctl restart postgresql
    '

    log_info "PostgreSQL configured for remote access"
}

# Install and configure PostgreSQL
install_postgresql() {
    log_info "Setting up PostgreSQL..."

    # Check if already installed
    if container_exec 'dpkg-query -W -f="${Status}" postgresql 2>/dev/null | grep -q "install ok installed"'; then
        log_info "PostgreSQL already installed"

        # Verify user/db exist
        if container_exec "sudo -u postgres psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$PG_USER'\" | grep -q 1"; then
            log_info "PostgreSQL user '$PG_USER' exists"
        else
            create_pg_user_db
        fi
        return 0
    fi

    wait_for_apt_lock

    log_info "Installing PostgreSQL..."
    container_exec '
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            postgresql \
            postgresql-contrib
    '

    # Wait for PostgreSQL to start
    container_exec 'systemctl enable postgresql && systemctl start postgresql'
    sleep 2

    create_pg_user_db
    configure_pg_remote_access
}

# -------------------------------------------
# Node.js Installation (PROV-05, PROV-06)
# -------------------------------------------

# Install nvm, Node.js, and enable corepack for yarn/pnpm
install_node() {
    log_info "Setting up Node.js environment..."

    # Check if nvm already installed
    if container_exec '[ -s "$HOME/.nvm/nvm.sh" ]'; then
        log_info "nvm already installed"
    else
        log_info "Installing nvm $NVM_VERSION..."
        container_exec "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash"
    fi

    # Source nvm and check/install Node.js
    # CRITICAL: Must source nvm.sh for non-interactive shell
    container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

        if nvm ls '"$NODE_VERSION"' &>/dev/null; then
            echo "Node.js '"$NODE_VERSION"' already installed"
        else
            echo "Installing Node.js '"$NODE_VERSION"'..."
            nvm install '"$NODE_VERSION"'
        fi

        nvm alias default '"$NODE_VERSION"'
        nvm use default

        # Update npm to latest
        npm install -g npm@latest
    '

    # Verify installation
    local node_version
    node_version=$(container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        node --version
    ')
    log_info "Node.js installed: $node_version"

    # Enable corepack for yarn and pnpm
    log_info "Enabling corepack for yarn and pnpm..."
    container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        corepack enable
    '

    # Verify package managers
    local npm_ver yarn_ver pnpm_ver
    npm_ver=$(container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        npm --version
    ')
    yarn_ver=$(container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        yarn --version
    ')
    pnpm_ver=$(container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        pnpm --version
    ')

    log_info "Package managers: npm $npm_ver, yarn $yarn_ver, pnpm $pnpm_ver"
}

# -------------------------------------------
# Playwright Installation (PROV-09)
# -------------------------------------------

# Install Playwright with Chromium and Firefox browsers
install_playwright() {
    log_info "Setting up Playwright..."

    # Check if Playwright browsers already installed
    if container_exec '[ -d "$HOME/.cache/ms-playwright" ]'; then
        log_info "Playwright browsers already installed"
        return 0
    fi

    log_info "Installing Playwright with Chromium and Firefox..."
    # --with-deps installs system dependencies automatically
    # npx -y auto-confirms package installation
    container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        npx -y playwright install --with-deps chromium firefox
    '

    log_info "Playwright browsers installed"
}

# -------------------------------------------
# Claude Code Installation (PROV-10)
# -------------------------------------------

# Install Claude Code CLI using native installer
install_claude_code() {
    log_info "Setting up Claude Code..."

    # Check if already installed
    if container_exec 'command -v claude &>/dev/null || [ -f "$HOME/.local/bin/claude" ]'; then
        local claude_ver
        claude_ver=$(container_exec '$HOME/.local/bin/claude --version 2>/dev/null || claude --version 2>/dev/null' || echo "installed")
        log_info "Claude Code already installed: $claude_ver"
        return 0
    fi

    log_info "Installing Claude Code CLI..."
    # Use native installer per RESEARCH.md recommendation (not npm)
    container_exec 'curl -fsSL https://claude.ai/install.sh | bash'

    # Verify installation
    if container_exec '[ -f "$HOME/.local/bin/claude" ]'; then
        log_info "Claude Code installed at ~/.local/bin/claude"
    else
        log_warn "Claude Code installation may have failed - check manually"
    fi
}

# Copy Claude Code credentials and config from host to container
copy_claude_credentials() {
    log_info "Copying Claude Code credentials and config..."

    # Find credentials from the user who ran sudo (or root)
    local source_user="${SUDO_USER:-root}"
    local source_home

    if [[ "$source_user" == "root" ]]; then
        source_home="/root"
    else
        source_home=$(getent passwd "$source_user" | cut -d: -f6)
    fi

    local creds_file="$source_home/.claude/.credentials.json"
    local config_file="$source_home/.claude.json"
    local copied=false

    # Create .claude directories
    container_exec 'mkdir -p ~/.claude && chmod 700 ~/.claude'
    container_exec 'mkdir -p /home/dev/.claude && chmod 700 /home/dev/.claude && chown dev:dev /home/dev/.claude'

    # Copy credentials file if exists
    if [[ -f "$creds_file" ]]; then
        log_info "Copying credentials..."
        lxc file push "$creds_file" "$CONTAINER_NAME/root/.claude/.credentials.json"
        container_exec 'chmod 600 ~/.claude/.credentials.json'
        lxc file push "$creds_file" "$CONTAINER_NAME/home/dev/.claude/.credentials.json"
        container_exec 'chown dev:dev /home/dev/.claude/.credentials.json && chmod 600 /home/dev/.claude/.credentials.json'
        copied=true
    fi

    # Copy main config file if exists (contains onboarding state, theme, account info)
    if [[ -f "$config_file" ]]; then
        log_info "Copying config..."
        lxc file push "$config_file" "$CONTAINER_NAME/root/.claude.json"
        container_exec 'chmod 600 ~/.claude.json'
        lxc file push "$config_file" "$CONTAINER_NAME/home/dev/.claude.json"
        container_exec 'chown dev:dev /home/dev/.claude.json && chmod 600 /home/dev/.claude.json'
        copied=true
    fi

    if [[ "$copied" == "true" ]]; then
        log_info "Claude credentials and config copied to root and dev users"
    else
        log_warn "No Claude credentials found at $creds_file or $config_file"
        log_warn "You'll need to authenticate Claude Code manually in the container"
    fi
}

# -------------------------------------------
# Dev User Environment Setup
# -------------------------------------------

# Set up Node.js, Claude Code, etc. for the dev user
# This runs after root installations are complete
setup_dev_user_environment() {
    log_info "Setting up dev user environment..."

    # Install nvm for dev user
    log_info "Installing nvm for dev user..."
    container_exec_as_dev "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash"

    # Install Node.js for dev user
    log_info "Installing Node.js $NODE_VERSION for dev user..."
    container_exec_as_dev '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install '"$NODE_VERSION"'
        nvm alias default '"$NODE_VERSION"'
        nvm use default

        # Update npm to latest
        npm install -g npm@latest

        corepack enable
    '

    # Install Claude Code for dev user
    log_info "Installing Claude Code for dev user..."
    container_exec_as_dev 'curl -fsSL https://claude.ai/install.sh | bash'

    # Verify Claude Code installation
    if container_exec_as_dev '[ -f "$HOME/.local/bin/claude" ]'; then
        log_info "Claude Code installed for dev user"
    else
        log_warn "Claude Code installation for dev user may have failed"
    fi

    # Install Get Shit Done (GSD) for Claude Code
    log_info "Installing Get Shit Done (GSD) for Claude Code..."
    container_exec_as_dev '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        npx -y get-shit-done-cc --claude --global
    '
    log_info "GSD installed - use /gsd:help in Claude Code"
}

# -------------------------------------------
# SSH Key Setup
# -------------------------------------------

# Copy SSH keys to container for passwordless access (root and dev)
setup_ssh_keys() {
    log_info "Setting up SSH keys..."

    # Find keys from the user who ran sudo, with fallbacks
    local source_user="${SUDO_USER:-}"
    local source_home=""
    local keys_added=0

    # Try SUDO_USER first
    if [[ -n "$source_user" ]]; then
        source_home=$(getent passwd "$source_user" | cut -d: -f6)
        log_info "Looking for SSH keys in $source_home/.ssh/ (from SUDO_USER=$source_user)"
    fi

    # Fallback: check common locations if SUDO_USER didn't work
    if [[ -z "$source_home" ]] || [[ ! -d "$source_home/.ssh" ]]; then
        for try_home in /home/*; do
            if [[ -d "$try_home/.ssh" ]] && [[ -f "$try_home/.ssh/authorized_keys" || -f "$try_home/.ssh/id_ed25519.pub" || -f "$try_home/.ssh/id_rsa.pub" ]]; then
                source_home="$try_home"
                log_info "Found SSH keys in $source_home/.ssh/ (fallback)"
                break
            fi
        done
    fi

    if [[ -z "$source_home" ]] || [[ ! -d "$source_home/.ssh" ]]; then
        log_warn "No SSH keys found on host - SSH key auth not configured"
        log_warn "Add keys manually after provisioning"
        return 0
    fi

    # Create .ssh directories
    container_exec 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'
    container_exec 'mkdir -p /home/dev/.ssh && chmod 700 /home/dev/.ssh && chown dev:dev /home/dev/.ssh'

    # Start with empty authorized_keys
    container_exec 'rm -f ~/.ssh/authorized_keys /home/dev/.ssh/authorized_keys'
    container_exec 'touch ~/.ssh/authorized_keys /home/dev/.ssh/authorized_keys'

    # 1. Add host user's public keys
    for pubkey in "$source_home"/.ssh/id_*.pub; do
        if [[ -f "$pubkey" ]]; then
            log_info "Adding public key: $pubkey"
            lxc file push "$pubkey" "$CONTAINER_NAME/home/dev/.ssh/tmp_key.pub"
            container_exec 'cat /home/dev/.ssh/tmp_key.pub >> /home/dev/.ssh/authorized_keys && rm /home/dev/.ssh/tmp_key.pub'
            ((keys_added++))
        fi
    done

    # 2. Add authorized_keys (for external access like Termius)
    # Check all home directories for authorized_keys, not just the sudo user's
    # Collect all unique keys to avoid duplicates
    local temp_keys=$(mktemp)
    local auth_keys_found=false
    for check_home in "$source_home" /home/*; do
        if [[ -f "$check_home/.ssh/authorized_keys" ]] && [[ -r "$check_home/.ssh/authorized_keys" ]]; then
            log_info "Found authorized_keys in $check_home/.ssh/"
            cat "$check_home/.ssh/authorized_keys" >> "$temp_keys"
            auth_keys_found=true
        fi
    done
    if [[ "$auth_keys_found" == "true" ]]; then
        # Deduplicate and append to container
        sort -u "$temp_keys" | lxc exec "$CONTAINER_NAME" -- tee -a /home/dev/.ssh/authorized_keys > /dev/null
        ((keys_added++))
        log_info "Added authorized_keys for external SSH access"
    else
        log_warn "No authorized_keys found on host - external SSH access (like Termius) may not work"
    fi
    rm -f "$temp_keys"

    # Set permissions for dev user
    container_exec 'chown dev:dev /home/dev/.ssh/authorized_keys && chmod 600 /home/dev/.ssh/authorized_keys'

    # Copy to root as well (for admin access)
    container_exec 'cp /home/dev/.ssh/authorized_keys /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys'

    if [[ $keys_added -gt 0 ]]; then
        log_info "SSH keys configured for root and dev ✓ ($keys_added sources from $source_home)"
    else
        log_warn "No SSH keys found in $source_home/.ssh/"
        log_warn "Add keys manually: lxc exec $CONTAINER_NAME -- nano /home/dev/.ssh/authorized_keys"
    fi
}

# -------------------------------------------
# Git Credentials Setup
# -------------------------------------------

# Copy git credentials from host to container
# Includes: SSH private keys, .gitconfig, GitHub CLI config
# Copies to both root and dev users for consistency
setup_git_credentials() {
    log_info "Setting up git credentials for root and dev users..."

    # Find credentials from the user who ran sudo (or root)
    local source_user="${SUDO_USER:-root}"
    local source_home
    local copied_items=0

    if [[ "$source_user" == "root" ]]; then
        source_home="/root"
    else
        source_home=$(getent passwd "$source_user" | cut -d: -f6)
    fi

    # --- SSH Private Keys ---
    log_info "Copying SSH private keys..."
    container_exec 'mkdir -p /home/dev/.ssh && chmod 700 /home/dev/.ssh && chown dev:dev /home/dev/.ssh'
    container_exec 'mkdir -p /root/.ssh && chmod 700 /root/.ssh'

    for keyfile in "$source_home"/.ssh/id_*; do
        if [[ -f "$keyfile" ]] && [[ ! "$keyfile" =~ \.pub$ ]]; then
            local keyname
            keyname=$(basename "$keyfile")
            log_info "  Copying $keyname"
            # Copy to dev user
            lxc file push "$keyfile" "$CONTAINER_NAME/home/dev/.ssh/$keyname"
            container_exec "chown dev:dev /home/dev/.ssh/$keyname && chmod 600 /home/dev/.ssh/$keyname"
            # Copy to root user
            lxc file push "$keyfile" "$CONTAINER_NAME/root/.ssh/$keyname"
            container_exec "chmod 600 /root/.ssh/$keyname"
            ((copied_items++))

            # Also copy the corresponding .pub file if it exists
            if [[ -f "${keyfile}.pub" ]]; then
                lxc file push "${keyfile}.pub" "$CONTAINER_NAME/home/dev/.ssh/${keyname}.pub"
                container_exec "chown dev:dev /home/dev/.ssh/${keyname}.pub && chmod 644 /home/dev/.ssh/${keyname}.pub"
                lxc file push "${keyfile}.pub" "$CONTAINER_NAME/root/.ssh/${keyname}.pub"
                container_exec "chmod 644 /root/.ssh/${keyname}.pub"
            fi
        fi
    done

    # Copy known_hosts if exists (to avoid host key verification prompts)
    if [[ -f "$source_home/.ssh/known_hosts" ]]; then
        log_info "  Copying known_hosts"
        lxc file push "$source_home/.ssh/known_hosts" "$CONTAINER_NAME/home/dev/.ssh/known_hosts"
        container_exec 'chown dev:dev /home/dev/.ssh/known_hosts && chmod 644 /home/dev/.ssh/known_hosts'
        lxc file push "$source_home/.ssh/known_hosts" "$CONTAINER_NAME/root/.ssh/known_hosts"
        container_exec 'chmod 644 /root/.ssh/known_hosts'
    fi

    # Ensure GitHub and GitLab are in known_hosts (even if host didn't have them)
    log_info "  Adding GitHub and GitLab to known_hosts..."
    container_exec '
        # For dev user
        touch /home/dev/.ssh/known_hosts
        if ! grep -q "github.com" /home/dev/.ssh/known_hosts 2>/dev/null; then
            ssh-keyscan -t ed25519,rsa github.com >> /home/dev/.ssh/known_hosts 2>/dev/null || true
        fi
        if ! grep -q "gitlab.com" /home/dev/.ssh/known_hosts 2>/dev/null; then
            ssh-keyscan -t ed25519,rsa gitlab.com >> /home/dev/.ssh/known_hosts 2>/dev/null || true
        fi
        chown dev:dev /home/dev/.ssh/known_hosts
        chmod 644 /home/dev/.ssh/known_hosts

        # For root user
        touch /root/.ssh/known_hosts
        if ! grep -q "github.com" /root/.ssh/known_hosts 2>/dev/null; then
            ssh-keyscan -t ed25519,rsa github.com >> /root/.ssh/known_hosts 2>/dev/null || true
        fi
        if ! grep -q "gitlab.com" /root/.ssh/known_hosts 2>/dev/null; then
            ssh-keyscan -t ed25519,rsa gitlab.com >> /root/.ssh/known_hosts 2>/dev/null || true
        fi
        chmod 644 /root/.ssh/known_hosts
    '

    # Copy SSH config if exists
    if [[ -f "$source_home/.ssh/config" ]]; then
        log_info "  Copying SSH config"
        lxc file push "$source_home/.ssh/config" "$CONTAINER_NAME/home/dev/.ssh/config"
        container_exec 'chown dev:dev /home/dev/.ssh/config && chmod 600 /home/dev/.ssh/config'
        lxc file push "$source_home/.ssh/config" "$CONTAINER_NAME/root/.ssh/config"
        container_exec 'chmod 600 /root/.ssh/config'
    fi

    # --- Git Config ---
    if [[ -f "$source_home/.gitconfig" ]]; then
        log_info "Copying .gitconfig..."
        lxc file push "$source_home/.gitconfig" "$CONTAINER_NAME/home/dev/.gitconfig"
        container_exec 'chown dev:dev /home/dev/.gitconfig && chmod 644 /home/dev/.gitconfig'
        lxc file push "$source_home/.gitconfig" "$CONTAINER_NAME/root/.gitconfig"
        container_exec 'chmod 644 /root/.gitconfig'
        ((copied_items++))
    else
        log_warn "No .gitconfig found at $source_home/.gitconfig"
    fi

    # --- GitHub CLI Config ---
    if [[ -d "$source_home/.config/gh" ]]; then
        log_info "Copying GitHub CLI config..."
        # For dev user
        container_exec 'mkdir -p /home/dev/.config && chown dev:dev /home/dev/.config'
        tar -C "$source_home/.config" -cf - gh | lxc exec "$CONTAINER_NAME" -- tar -C /home/dev/.config -xf -
        container_exec 'chown -R dev:dev /home/dev/.config/gh && chmod 700 /home/dev/.config/gh'
        # For root user
        container_exec 'mkdir -p /root/.config'
        tar -C "$source_home/.config" -cf - gh | lxc exec "$CONTAINER_NAME" -- tar -C /root/.config -xf -
        container_exec 'chmod 700 /root/.config/gh'
        ((copied_items++))
        log_info "GitHub CLI config copied (gh auth status will work)"
    else
        log_warn "No GitHub CLI config found at $source_home/.config/gh"
    fi

    if [[ $copied_items -gt 0 ]]; then
        log_info "Git credentials configured for root and dev users ✓ ($copied_items items)"
        echo ""
        echo "  Git operations (push/pull) should now work in the container."
        echo "  Test with: ssh dev@<container-ip> 'git ls-remote git@github.com:user/repo.git'"
        echo ""
    else
        log_warn "No git credentials found to copy"
    fi
}

# -------------------------------------------
# Shell Configuration (PROV-11)
# -------------------------------------------

# Configure shell environment with database vars and useful aliases
configure_shell() {
    log_info "Configuring shell environment..."

    # Add to .bashrc if not already present
    container_exec '
        BASHRC="$HOME/.bashrc"
        MARKER="# Dev Sandbox Environment"

        if grep -q "$MARKER" "$BASHRC"; then
            echo "Shell already configured"
        else
            cat >> "$BASHRC" << '"'"'SHELL_CONFIG'"'"'

# Dev Sandbox Environment
# Added by 03-provision-container.sh

# Database environment variables
export PGHOST=localhost
export PGPORT=5432
export PGUSER=dev
export PGPASSWORD=dev
export PGDATABASE=dev
export DATABASE_URL="postgresql://dev:dev@localhost:5432/dev"

# Node.js via nvm (auto-load)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Claude Code
export PATH="$HOME/.local/bin:$PATH"

# Useful aliases
alias ll="ls -la"
alias pg="psql -U dev dev"
alias pgstart="sudo systemctl start postgresql"
alias pgstop="sudo systemctl stop postgresql"
alias pgstatus="sudo systemctl status postgresql"
alias tsstatus="tailscale status"
alias tsip="tailscale ip -4"

# Dev helper aliases
alias npmi="npm install"
alias npmr="npm run"
alias pnpmi="pnpm install"
alias yarni="yarn install"

SHELL_CONFIG
        fi
    '

    # Also configure dev user's bashrc
    container_exec '
        DEV_BASHRC="/home/dev/.bashrc"
        MARKER="# Dev Sandbox Environment"

        if ! grep -q "$MARKER" "$DEV_BASHRC" 2>/dev/null; then
            cat >> "$DEV_BASHRC" << '"'"'SHELL_CONFIG'"'"'

# Dev Sandbox Environment
# Added by 03-provision-container.sh

# Database environment variables
export PGHOST=localhost
export PGPORT=5432
export PGUSER=dev
export PGPASSWORD=dev
export PGDATABASE=dev
export DATABASE_URL="postgresql://dev:dev@localhost:5432/dev"

# Node.js via nvm (auto-load)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Claude Code
export PATH="$HOME/.local/bin:$PATH"

# Useful aliases
alias ll="ls -la"
alias pg="psql -U dev dev"
alias pgstart="sudo systemctl start postgresql"
alias pgstop="sudo systemctl stop postgresql"
alias pgstatus="sudo systemctl status postgresql"
alias tsstatus="tailscale status"
alias tsip="tailscale ip -4"

# Dev helper aliases
alias npmi="npm install"
alias npmr="npm run"
alias pnpmi="pnpm install"
alias yarni="yarn install"

SHELL_CONFIG
            chown dev:dev "$DEV_BASHRC"
        fi
    '

    # Also add ~/.local/bin to /etc/environment for non-interactive shells
    # This ensures 'claude' command works in all contexts (lxc exec, scripts, etc.)
    # Include both root and dev user paths
    container_exec '
        if ! grep -q "/.local/bin" /etc/environment 2>/dev/null; then
            # Append PATH modification to /etc/environment
            if grep -q "^PATH=" /etc/environment; then
                # PATH exists, prepend ~/.local/bin to it
                sed -i "s|^PATH=\"|PATH=\"/home/dev/.local/bin:/root/.local/bin:|" /etc/environment
            else
                # No PATH line, add one
                echo "PATH=\"/home/dev/.local/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"" >> /etc/environment
            fi
            echo "Added ~/.local/bin to /etc/environment"
        fi
    '

    log_info "Shell environment configured for root and dev"
}

# Create CLAUDE.md for Claude Code awareness
create_claude_md() {
    log_info "Creating CLAUDE.md for Claude Code..."

    local node_version pg_version tailscale_ip container_name
    node_version=$(container_exec 'node --version 2>/dev/null || echo "not installed"')
    pg_version=$(container_exec 'psql --version 2>/dev/null | head -1 || echo "not installed"')
    tailscale_ip=$(container_exec 'tailscale ip -4 2>/dev/null || echo "not connected"')
    container_name="$CONTAINER_NAME"

    # Ensure ~/.claude directory exists (created by Claude Code installer)
    container_exec 'mkdir -p ~/.claude'

    # Create CLAUDE.md content
    local claude_md_content="# Dev Sandbox Environment

This is an isolated LXC container for development.

## Claude Code Instructions

When suggesting commands that the user must run manually (e.g., on the host, or commands requiring user interaction), **always append tee to a log file** so the user can just tell you when to check the log:

\\\`\\\`\\\`bash
# Good - user says \"check the log\" when done
sudo some-command 2>&1 | tee -a ~/ops.log

# Bad - requires copy-pasting potentially long output
sudo some-command
\\\`\\\`\\\`

This minimizes user wait time and copy-paste overhead.

## System
- **Container:** $container_name
- **OS:** Ubuntu 24.04 LTS
- **Tailscale IP:** $tailscale_ip
- **Users:** root (admin), dev (for Claude Code)

## IMPORTANT: Use 'dev' user for Claude Code

Claude Code's \\\`--dangerously-skip-permissions\\\` mode (YOLO mode) does not work as root.
**Always SSH as the dev user when using Claude Code:**

\\\`\\\`\\\`bash
ssh dev@$tailscale_ip
cd ~/projects/<name>
claude --dangerously-skip-permissions
\\\`\\\`\\\`

The dev user has passwordless sudo for any admin tasks.

## Installed Tools

### Node.js
- **Version:** $node_version
- **Manager:** nvm (in ~/.nvm)
- **Package managers:** npm, yarn, pnpm

### PostgreSQL
- **Version:** $pg_version
- **Host:** localhost:5432
- **User:** dev
- **Password:** dev
- **Database:** dev
- **DATABASE_URL:** postgresql://dev:dev@localhost:5432/dev

### Other Tools
- Playwright (Chromium, Firefox)
- Claude Code CLI with Get Shit Done (GSD) - use /gsd:help
- git, curl, mosh, build-essential

## Common Commands

\\\`\\\`\\\`bash
# Database
psql -U dev dev              # Connect to PostgreSQL
pg                           # Alias for above

# Node.js
nvm use 22                   # Switch Node version
npm install / yarn / pnpm install

# Tailscale
tailscale status             # Check connection
tailscale ip -4              # Get Tailscale IP

# Project location
cd ~/projects/<name>         # Migrated projects go here
\\\`\\\`\\\`

## Environment Variables

These are pre-configured in ~/.bashrc:
- \\\`DATABASE_URL\\\` - PostgreSQL connection string
- \\\`PGHOST\\\`, \\\`PGPORT\\\`, \\\`PGUSER\\\`, \\\`PGPASSWORD\\\`, \\\`PGDATABASE\\\`
- \\\`NVM_DIR\\\` - nvm installation directory

## Notes

- This container is ephemeral - create snapshots before risky operations
- PostgreSQL uses trust auth locally, password auth for Tailscale connections
- Projects are migrated to /home/dev/projects/<project-name>
- Use dev user for Claude Code YOLO mode, root for admin tasks"

    # Write to root's .claude directory
    container_exec "mkdir -p ~/.claude && cat > ~/.claude/CLAUDE.md << 'CLAUDE_CONFIG'
$claude_md_content
CLAUDE_CONFIG"
    container_exec 'ln -sf ~/.claude/CLAUDE.md ~/CLAUDE.md'

    # Write to dev user's .claude directory
    container_exec "mkdir -p /home/dev/.claude && cat > /home/dev/.claude/CLAUDE.md << 'CLAUDE_CONFIG'
$claude_md_content
CLAUDE_CONFIG"
    container_exec 'chown -R dev:dev /home/dev/.claude && ln -sf /home/dev/.claude/CLAUDE.md /home/dev/CLAUDE.md && chown -h dev:dev /home/dev/CLAUDE.md'

    log_info "CLAUDE.md created for root and dev users"
}

# -------------------------------------------
# Status Summary
# -------------------------------------------

# Print comprehensive status summary with versions and connection info
print_status_summary() {
    echo ""
    echo "=========================================="
    echo "Provisioning Complete!"
    echo "=========================================="
    echo ""

    # Gather all version info
    local ts_ip node_ver npm_ver yarn_ver pnpm_ver pg_ver claude_ver

    ts_ip=$(container_exec 'tailscale ip -4' 2>/dev/null || echo "not connected")

    node_ver=$(container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        node --version
    ' 2>/dev/null || echo "not installed")

    npm_ver=$(container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        npm --version
    ' 2>/dev/null || echo "not installed")

    yarn_ver=$(container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        yarn --version
    ' 2>/dev/null || echo "not installed")

    pnpm_ver=$(container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        pnpm --version
    ' 2>/dev/null || echo "not installed")

    pg_ver=$(container_exec 'psql --version' 2>/dev/null | head -1 || echo "not installed")

    claude_ver=$(container_exec '$HOME/.local/bin/claude --version' 2>/dev/null || echo "not installed")

    echo "Container: $CONTAINER_NAME"
    echo ""
    echo "Tailscale:"
    echo "  IP: $ts_ip"
    echo "  Status: $(container_exec 'tailscale status --self' 2>/dev/null | head -1 || echo 'unknown')"
    echo ""
    echo "Node.js:"
    echo "  Node: $node_ver"
    echo "  npm: $npm_ver"
    echo "  yarn: $yarn_ver"
    echo "  pnpm: $pnpm_ver"
    echo ""
    echo "PostgreSQL:"
    echo "  Version: $pg_ver"
    echo "  User: $PG_USER"
    echo "  Database: $PG_DB"
    echo "  Listen: 0.0.0.0:5432 (accessible via Tailscale)"
    echo ""
    echo "Playwright:"
    echo "  Browsers: Chromium, Firefox"
    echo ""
    echo "Claude Code:"
    echo "  Version: $claude_ver"
    echo "  Path: ~/.local/bin/claude"
    echo "  Credentials: copied from host (if available)"
    echo ""
    echo "Git Credentials (copied from host):"
    echo "  SSH keys: ~/.ssh/ (root and dev)"
    echo "  .gitconfig: ~/ (root and dev)"
    echo "  GitHub CLI: ~/.config/gh/ (root and dev)"
    echo "  known_hosts: github.com, gitlab.com pre-added"
    echo ""
    echo "=========================================="
    echo "Connection Instructions"
    echo "=========================================="
    echo ""
    echo "SSH (from any Tailscale device):"
    echo "  ssh dev@$ts_ip       # For Claude Code (recommended)"
    echo "  ssh root@$ts_ip      # For admin tasks"
    echo "  ssh $CONTAINER_NAME  # if MagicDNS enabled"
    echo ""
    echo "PostgreSQL (from dev machine):"
    echo "  psql -h $ts_ip -U dev dev"
    echo "  # or with DATABASE_URL:"
    echo "  postgresql://dev:dev@$ts_ip:5432/dev"
    echo ""
    echo "Inside container:"
    echo "  lxc exec $CONTAINER_NAME -- su - dev  # as dev user"
    echo "  lxc exec $CONTAINER_NAME -- bash      # as root"
    echo ""
    echo "=========================================="
    echo "QUICK START (for Claude Code)"
    echo "=========================================="
    echo ""
    echo "  ssh dev@$ts_ip"
    echo "  cd ~/projects/<name>"
    echo "  claude --dangerously-skip-permissions"
    echo ""
}

# ============================================
# MAIN SCRIPT
# ============================================

echo "=========================================="
echo "Dev Sandbox - Stack Provisioning"
echo "=========================================="
echo ""

log_info "Provisioning container: $CONTAINER_NAME"
echo ""

# Install components in dependency order (per RESEARCH.md)
if [[ "$SKIP_TAILSCALE" == true ]]; then
    log_warn "Skipping Tailscale setup (--no-tailscale)"
    log_warn "Container will only be accessible via lxc exec or bridge IP"
else
    install_tailscale      # First - provides connectivity verification
fi
create_dev_user        # Create non-root user early (for Claude Code YOLO mode)
install_postgresql     # Early - apt-based, stable
install_node           # After apt, provides npm for root
install_playwright     # Requires npm
install_claude_code    # Claude Code for root
setup_dev_user_environment  # Node.js and Claude Code for dev user
copy_claude_credentials    # Copy host's Claude auth to container
setup_ssh_keys         # Copy host's authorized keys to root and dev
setup_git_credentials  # Copy SSH keys, .gitconfig, gh CLI for git push/pull
configure_shell        # After all tools installed
create_claude_md       # Claude Code environment awareness

# Final verification and status summary
print_status_summary
