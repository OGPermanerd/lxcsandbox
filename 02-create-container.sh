#!/bin/bash
#
# 02-create-container.sh
# Creates a new LXC container for development sandbox
# Run as root or with sudo
#
# Usage: ./02-create-container.sh <container-name>
# Example: ./02-create-container.sh relay-dev
#
# Features:
# - Ubuntu 24.04 base image
# - TUN device for Tailscale VPN
# - Soft memory limit (4GB, can burst)
# - CPU limit matching host cores
# - Basic packages (curl, git, ssh)
# - Auto-snapshot before replacing existing container
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
if [[ $# -ne 1 ]]; then
    echo "Usage: ./02-create-container.sh <container-name>"
    echo ""
    echo "Example: ./02-create-container.sh relay-dev"
    echo ""
    echo "Container names must:"
    echo "  - Be 2-30 characters long"
    echo "  - Start with a lowercase letter"
    echo "  - Contain only lowercase letters, numbers, and hyphens"
    echo "  - Not end with a hyphen"
    exit 1
fi

CONTAINER_NAME="$1"

# -------------------------------------------
# LXD Availability Check
# -------------------------------------------
if ! command -v lxc &>/dev/null; then
    log_error "LXD is not installed"
    echo ""
    echo "Install LXD first:"
    echo "  sudo snap install lxd"
    echo "  sudo lxd init"
    echo ""
    echo "Or run the host setup script:"
    echo "  ./01-setup-host.sh"
    exit 1
fi

# Check if LXD is properly initialized (has storage pool and profile with root disk)
if ! lxc profile show default 2>/dev/null | grep -q "pool:"; then
    log_error "LXD is not properly initialized (default profile missing root disk)"
    echo ""
    echo "Run the host setup script to fix this:"
    echo "  sudo ./01-setup-host.sh"
    echo ""
    echo "Or manually add a root disk to the default profile:"
    echo "  lxc storage create default dir"
    echo "  lxc profile device add default root disk path=/ pool=default"
    exit 1
fi

# -------------------------------------------
# Container Name Validation (before root check - better UX)
# -------------------------------------------
validate_container_name() {
    local name="$1"

    # Check length (2-30 chars)
    if [[ ${#name} -lt 2 ]]; then
        log_error "Container name must be 2-30 characters (got ${#name})"
        echo "Example: relay-dev, my-project, test-sandbox"
        return 1
    fi

    if [[ ${#name} -gt 30 ]]; then
        log_error "Container name must be 2-30 characters (got ${#name})"
        echo "Example: relay-dev, my-project, test-sandbox"
        return 1
    fi

    # Check DNS-style format: lowercase, hyphens, starts with letter
    # For 2-char names: must be [a-z][a-z0-9]
    # For longer names: must start with letter, end with letter/number, middle can have hyphens
    if [[ ${#name} -eq 2 ]]; then
        if [[ ! "$name" =~ ^[a-z][a-z0-9]$ ]]; then
            log_error "Container name must:"
            echo "  - Start with a lowercase letter"
            echo "  - Contain only lowercase letters, numbers, and hyphens"
            echo "  - Not end with a hyphen"
            echo "Example: relay-dev, my-project, test-sandbox"
            return 1
        fi
    else
        if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
            log_error "Container name must:"
            echo "  - Start with a lowercase letter"
            echo "  - Contain only lowercase letters, numbers, and hyphens"
            echo "  - Not end with a hyphen"
            echo "Example: relay-dev, my-project, test-sandbox"
            return 1
        fi
    fi

    # Check for double hyphens (not DNS compliant)
    if [[ "$name" =~ -- ]]; then
        log_error "Container name cannot contain consecutive hyphens (--)"
        echo "Example: relay-dev, my-project, test-sandbox"
        return 1
    fi

    # Check for reserved names
    local reserved=("default" "host" "localhost" "lxdbr0" "none" "self" "all" "container" "lxc" "lxd")
    for r in "${reserved[@]}"; do
        if [[ "$name" == "$r" ]]; then
            log_error "Container name '$name' is reserved"
            echo "Reserved names: ${reserved[*]}"
            return 1
        fi
    done

    return 0
}

# -------------------------------------------
# Existing Container Handling
# -------------------------------------------
handle_existing_container() {
    local name="$1"

    if lxc info "$name" &> /dev/null; then
        echo ""
        read -p "Container '$name' already exists. Delete and create new? (y/N): " confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Cancelled"
            exit 0
        fi

        # Create backup snapshot with timestamp
        local snap_name="backup-$(date +%Y%m%d-%H%M%S)"
        log_info "Creating backup snapshot: $name/$snap_name"

        # Stop container if running (snapshot works on running but cleaner stopped)
        local status
        status=$(lxc info "$name" | grep 'Status:' | awk '{print $2}')
        if [[ "$status" == "RUNNING" ]]; then
            log_info "Stopping container..."
            lxc stop "$name" --timeout 30 || true
        fi

        lxc snapshot "$name" "$snap_name"
        log_info "Snapshot created: $name/$snap_name"
        log_warn "If you need to recover, use: lxc restore $name $snap_name"

        # Now delete
        log_info "Deleting existing container..."
        lxc delete "$name" --force
        log_info "Container deleted"
    fi
}

# -------------------------------------------
# Container Creation with Resource Limits
# -------------------------------------------
create_container() {
    local name="$1"

    log_info "Launching container from ubuntu:24.04..."
    lxc launch ubuntu:24.04 "$name"

    # Get host CPU count
    local host_cpus
    host_cpus=$(nproc)

    log_info "Configuring resource limits..."

    # Soft memory limit (4GB, can burst if available)
    lxc config set "$name" limits.memory=4GB
    lxc config set "$name" limits.memory.enforce=soft
    lxc config set "$name" limits.memory.swap=true

    # Match host CPUs
    lxc config set "$name" limits.cpu="$host_cpus"

    log_info "Resource limits: 4GB soft memory, $host_cpus CPUs"
}

# -------------------------------------------
# TUN Device Configuration for Tailscale
# -------------------------------------------
configure_tun_device() {
    local name="$1"

    log_info "Configuring TUN device for Tailscale..."

    # Enable nesting (needed for some container operations)
    lxc config set "$name" security.nesting=true

    # Add TUN device for Tailscale
    lxc config device add "$name" tun unix-char path=/dev/net/tun

    log_info "TUN device configured"
}

# -------------------------------------------
# Network Connectivity Wait
# -------------------------------------------
wait_for_network() {
    local name="$1"
    local timeout=60
    local elapsed=0
    local spinstr='|/-\'

    echo -n "  Waiting for network connectivity..."

    while [[ $elapsed -lt $timeout ]]; do
        # Check for IP address
        local ip
        ip=$(lxc list "$name" --format csv -c 4 2>/dev/null | cut -d' ' -f1)

        if [[ -n "$ip" && "$ip" != "" ]]; then
            # Has IP, check internet connectivity
            if lxc exec "$name" -- ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
                printf "\r\033[K"  # Clear line
                log_info "Network ready (IP: $ip)"
                return 0
            fi
        fi

        # Spinner
        local temp=${spinstr#?}
        printf "\r  [%c] Waiting for network... (%ds/%ds)" "$spinstr" "$elapsed" "$timeout"
        spinstr=$temp${spinstr%"$temp"}

        sleep 1
        ((elapsed++))
    done

    printf "\r\033[K"  # Clear line
    log_error "Network connectivity failed after ${timeout}s"
    echo "Container left running for debugging:"
    echo "  lxc exec $name -- bash"
    echo "  lxc exec $name -- ip addr"
    echo "  lxc exec $name -- ping 8.8.8.8"
    return 1
}

# -------------------------------------------
# Basic Package Installation
# -------------------------------------------
install_basic_packages() {
    local name="$1"

    log_info "Installing basic packages..."

    lxc exec "$name" -- bash -c '
        # Wait for apt lock (cloud-init may be running)
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
            sleep 1
        done

        apt-get update -qq

        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            ca-certificates \
            curl \
            git \
            mosh \
            openssh-server \
            sudo

        systemctl enable ssh
        systemctl start ssh
    '

    log_info "Basic packages installed"
}

# ============================================
# MAIN SCRIPT
# ============================================

echo "=========================================="
echo "Dev Sandbox - Container Creation"
echo "=========================================="
echo ""

# Validate container name (first - before root check for better UX)
validate_container_name "$CONTAINER_NAME"

# Root check (after validation but before operations)
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (or with sudo)"
    exit 1
fi

# Handle existing container if any
handle_existing_container "$CONTAINER_NAME"

# Create container with resource limits
create_container "$CONTAINER_NAME"

# Configure TUN device for Tailscale
configure_tun_device "$CONTAINER_NAME"

# Restart container to apply TUN device
log_info "Restarting container to apply TUN device..."
lxc restart "$CONTAINER_NAME"
sleep 2  # Allow restart to settle

# Wait for network connectivity
wait_for_network "$CONTAINER_NAME"

# Install basic packages
install_basic_packages "$CONTAINER_NAME"

# Success summary
echo ""
echo "=========================================="
echo "Container '$CONTAINER_NAME' created!"
echo "=========================================="
echo ""
echo "Next step:"
echo "  ./03-provision-container.sh $CONTAINER_NAME <tailscale-authkey>"
echo ""
echo "Quick access:"
echo "  lxc exec $CONTAINER_NAME -- bash"
echo ""
