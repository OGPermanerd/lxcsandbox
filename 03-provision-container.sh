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
if [[ $# -ne 2 ]]; then
    echo "Usage: ./03-provision-container.sh <container-name> <tailscale-authkey>"
    echo ""
    echo "Example: ./03-provision-container.sh relay-dev tskey-auth-xxxxxxxx"
    echo ""
    echo "Arguments:"
    echo "  container-name    Name of existing LXC container (created by 02-create-container.sh)"
    echo "  tailscale-authkey Reusable auth key from Tailscale admin console"
    echo "                    Get one at: https://login.tailscale.com/admin/settings/keys"
    exit 1
fi

CONTAINER_NAME="$1"
TAILSCALE_AUTHKEY="$2"

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
if [[ ! "$TAILSCALE_AUTHKEY" =~ ^tskey- ]]; then
    log_error "Invalid Tailscale auth key format"
    echo ""
    echo "Auth key must start with 'tskey-'"
    echo "Get a key at: https://login.tailscale.com/admin/settings/keys"
    echo ""
    echo "Recommended settings:"
    echo "  - Reusable: Yes"
    echo "  - Ephemeral: Yes (optional, auto-removes device on container delete)"
    exit 1
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

# Run a command with a spinner for visual feedback
run_with_spinner() {
    local msg="$1"
    local cmd="$2"
    local spinstr='|/-\'
    local delay=0.1

    echo -n "  $msg..."

    # Run command in background, capture PID
    eval "$cmd" &>/dev/null &
    local pid=$!

    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r  [%c] %s" "$spinstr" "$msg"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done

    wait $pid
    local status=$?
    printf "\r\033[K"  # Clear line

    if [[ $status -eq 0 ]]; then
        log_info "$msg - done"
    else
        log_error "$msg - failed"
        return $status
    fi
}

# Placeholder for main execution (to be added in subsequent tasks)
# install_tailscale
# install_postgresql
# install_node
# install_playwright
# install_claude_code
# configure_shell
# print_status_summary
