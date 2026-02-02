#!/bin/bash
#
# 03-provision-container.sh
# Installs complete dev stack in LXC container and connects to Tailscale
# Run as root or with sudo
#
# Usage: ./03-provision-container.sh <container-name> <tailscale-authkey>
# Example: ./03-provision-container.sh relay-dev tskey-auth-xxxxxxxx
#
# Features:
# - Tailscale VPN for direct IP access (100.x.x.x)
# - Node.js 22 via nvm with npm, yarn, pnpm
# - PostgreSQL with dev/dev credentials
# - Playwright with Chromium and Firefox
# - Claude Code CLI
# - Shell environment with database vars and aliases
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
    echo "Usage: ./03-provision-container.sh <container-name> <tailscale-authkey>"
    echo "       ./03-provision-container.sh <container-name> --no-tailscale"
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
    exit 1
fi

CONTAINER_NAME="$1"
TAILSCALE_AUTHKEY="$2"
SKIP_TAILSCALE=false

if [[ "$TAILSCALE_AUTHKEY" == "--no-tailscale" ]]; then
    SKIP_TAILSCALE=true
fi

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

# Execute command inside the container
container_exec() {
    lxc exec "$CONTAINER_NAME" -- bash -c "$1"
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
    container_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        npx playwright install --with-deps chromium firefox
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

# -------------------------------------------
# SSH Key Setup
# -------------------------------------------

# Copy host's authorized SSH keys to container for passwordless access
setup_ssh_keys() {
    log_info "Setting up SSH keys..."

    # Create .ssh directory in container
    container_exec 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'

    # Find authorized_keys from the user who ran sudo (or root)
    local auth_keys=""
    local source_user="${SUDO_USER:-root}"
    local source_home

    if [[ "$source_user" == "root" ]]; then
        source_home="/root"
    else
        source_home=$(getent passwd "$source_user" | cut -d: -f6)
    fi

    # Check for authorized_keys
    if [[ -f "$source_home/.ssh/authorized_keys" ]]; then
        auth_keys="$source_home/.ssh/authorized_keys"
    elif [[ -f "/root/.ssh/authorized_keys" ]]; then
        auth_keys="/root/.ssh/authorized_keys"
    fi

    if [[ -n "$auth_keys" && -f "$auth_keys" ]]; then
        log_info "Copying SSH keys from $auth_keys"
        lxc file push "$auth_keys" "$CONTAINER_NAME/root/.ssh/authorized_keys"
        container_exec 'chmod 600 ~/.ssh/authorized_keys'
        log_info "SSH keys configured ✓"
    else
        log_warn "No authorized_keys found - SSH key auth not configured"
        log_warn "Add keys manually: lxc exec $CONTAINER_NAME -- nano ~/.ssh/authorized_keys"
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

    log_info "Shell environment configured"
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

    container_exec "cat > ~/.claude/CLAUDE.md << 'CLAUDE_CONFIG'
# Dev Sandbox Environment

This is an isolated LXC container for development. You have full root access.

## System
- **Container:** $container_name
- **OS:** Ubuntu 24.04 LTS
- **Tailscale IP:** $tailscale_ip
- **User:** root

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
- Claude Code CLI
- git, curl, jq, build-essential

## Common Commands

\`\`\`bash
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
cd /root/projects/<name>     # Migrated projects go here
\`\`\`

## Environment Variables

These are pre-configured in ~/.bashrc:
- \`DATABASE_URL\` - PostgreSQL connection string
- \`PGHOST\`, \`PGPORT\`, \`PGUSER\`, \`PGPASSWORD\`, \`PGDATABASE\`
- \`NVM_DIR\` - nvm installation directory

## Notes

- This container is ephemeral - create snapshots before risky operations
- PostgreSQL uses trust auth locally, password auth for Tailscale connections
- Projects are migrated to /root/projects/<project-name>
CLAUDE_CONFIG"

    # Also symlink to home directory for visibility
    container_exec 'ln -sf ~/.claude/CLAUDE.md ~/CLAUDE.md'

    log_info "CLAUDE.md created at ~/.claude/CLAUDE.md"
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
    echo ""
    echo "=========================================="
    echo "Connection Instructions"
    echo "=========================================="
    echo ""
    echo "SSH (from any Tailscale device):"
    echo "  ssh root@$ts_ip"
    echo "  ssh $CONTAINER_NAME  # if MagicDNS enabled"
    echo ""
    echo "PostgreSQL (from dev machine):"
    echo "  psql -h $ts_ip -U dev dev"
    echo "  # or with DATABASE_URL:"
    echo "  postgresql://dev:dev@$ts_ip:5432/dev"
    echo ""
    echo "Inside container:"
    echo "  lxc exec $CONTAINER_NAME -- bash"
    echo ""
    echo "=========================================="
    echo "QUICK START"
    echo "=========================================="
    echo ""
    echo "  ssh root@$ts_ip"
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
install_postgresql     # Early - apt-based, stable
install_node           # After apt, provides npm
install_playwright     # Requires npm
install_claude_code    # Last - independent
setup_ssh_keys         # Copy host's authorized keys
configure_shell        # After all tools installed
create_claude_md       # Claude Code environment awareness

# Final verification and status summary
print_status_summary
