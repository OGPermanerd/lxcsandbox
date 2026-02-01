#!/bin/bash
#
# 01-setup-host.sh
# One-time setup for LXD host infrastructure on Ubuntu VPS
# Run as root or with sudo
#
# Requirements: Ubuntu 22.04 or 24.04
# Purpose: Install LXD, configure bridge networking (lxdbr0), enable NAT, configure firewall
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

echo "=========================================="
echo "Dev Sandbox Infrastructure - Host Setup"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (or with sudo)"
   exit 1
fi

# -------------------------------------------
# Step 1: Ubuntu Version Detection (HOST-01)
# -------------------------------------------
log_info "Detecting Ubuntu version..."

if [[ ! -f /etc/os-release ]]; then
    log_error "Cannot detect OS - /etc/os-release not found"
    exit 1
fi

# Parse VERSION_ID from os-release
source /etc/os-release

if [[ "$ID" != "ubuntu" ]]; then
    log_error "Unsupported OS: $ID"
    log_error "This script requires Ubuntu 22.04 or 24.04"
    exit 1
fi

# Check version
if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "24.04" ]]; then
    log_error "Unsupported Ubuntu version: $VERSION_ID"
    log_error "This script requires Ubuntu 22.04 or 24.04"
    exit 1
fi

log_info "Detected: Ubuntu $VERSION_ID ✓"

# -------------------------------------------
# Step 2: SSH Safety Verification
# -------------------------------------------
log_info "Verifying connectivity safety..."

if [[ -n "${SSH_CONNECTION:-}" ]]; then
    log_info "Running via SSH - connectivity verified ✓"
else
    log_warn "Running locally/console - proceeding (not via SSH)"
fi

# -------------------------------------------
# Step 3: Install Prerequisites
# -------------------------------------------
log_info "Checking prerequisites..."

# Install snapd if not present
if ! command -v snap &>/dev/null; then
    log_info "Installing snapd..."
    apt-get update
    apt-get install -y snapd
    # Snap needs a moment after install
    sleep 5
else
    log_info "snapd already installed ✓"
fi

# Install btrfs-progs if not present (required before preseed)
if ! command -v mkfs.btrfs &>/dev/null; then
    log_info "Installing btrfs-progs..."
    apt-get install -y btrfs-progs
else
    log_info "btrfs-progs already installed ✓"
fi

# -------------------------------------------
# Step 4: LXD Installation (HOST-02)
# -------------------------------------------
log_info "Checking LXD installation..."

if snap list lxd 2>/dev/null | grep -q "^lxd"; then
    CURRENT_VERSION=$(snap list lxd | awk 'NR==2 {print $2}')
    log_info "LXD already installed: $CURRENT_VERSION"

    # Optionally refresh to latest
    log_info "Checking for LXD updates..."
    snap refresh lxd 2>/dev/null || log_info "LXD is up to date"
else
    log_info "Installing LXD..."
    snap install lxd
    log_info "LXD installed successfully"
fi

# Add current user to lxd group if not already member
ORIGINAL_USER="${SUDO_USER:-$USER}"
if [[ "$ORIGINAL_USER" != "root" ]]; then
    if ! getent group lxd | grep -qwF "$ORIGINAL_USER"; then
        log_info "Adding $ORIGINAL_USER to lxd group..."
        usermod -aG lxd "$ORIGINAL_USER"
        log_warn "User $ORIGINAL_USER added to lxd group - logout/login required for group to take effect"
    else
        log_info "User $ORIGINAL_USER already in lxd group ✓"
    fi
fi

# -------------------------------------------
# Step 5: LXD Initialization (HOST-03, HOST-04, HOST-05)
# -------------------------------------------
log_info "Checking LXD initialization state..."

# Check if storage pool exists
STORAGE_EXISTS=false
if lxc storage list --format csv 2>/dev/null | grep -q "^default,"; then
    STORAGE_EXISTS=true
    log_info "Storage pool 'default' already exists ✓"
fi

# Check if network exists
NETWORK_EXISTS=false
if lxc network list --format csv 2>/dev/null | grep -q "^lxdbr0,"; then
    NETWORK_EXISTS=true
    log_info "Network 'lxdbr0' already exists ✓"
fi

# Check if default profile has root disk device
PROFILE_HAS_ROOT=false
if lxc profile device list default 2>/dev/null | grep -q "^root:"; then
    PROFILE_HAS_ROOT=true
    log_info "Default profile has root disk ✓"
fi

# If all exist, skip preseed
if [[ "$STORAGE_EXISTS" == true && "$NETWORK_EXISTS" == true && "$PROFILE_HAS_ROOT" == true ]]; then
    log_info "LXD already initialized, skipping preseed ✓"
elif [[ "$STORAGE_EXISTS" == true && "$NETWORK_EXISTS" == true && "$PROFILE_HAS_ROOT" == false ]]; then
    # Storage and network exist but profile missing root disk - fix profile only
    log_warn "Default profile missing root disk device - adding it now..."

    # Get the storage pool name (use 'default' if it exists, otherwise first available)
    POOL_NAME="default"
    if ! lxc storage list --format csv 2>/dev/null | grep -q "^default,"; then
        POOL_NAME=$(lxc storage list --format csv 2>/dev/null | head -1 | cut -d',' -f1)
    fi

    if [[ -n "$POOL_NAME" ]]; then
        lxc profile device add default root disk path=/ pool="$POOL_NAME" 2>/dev/null || \
            log_warn "Root device may already exist with different config"
        log_info "Added root disk device to default profile (pool: $POOL_NAME) ✓"
    else
        log_error "No storage pool found - cannot add root disk"
        exit 1
    fi

    # Also ensure eth0 network device exists
    if ! lxc profile device list default 2>/dev/null | grep -q "^eth0:"; then
        lxc profile device add default eth0 nic network=lxdbr0 name=eth0 2>/dev/null || true
        log_info "Added eth0 network device to default profile ✓"
    fi
else
    log_info "Initializing LXD with preseed configuration..."

    # Try btrfs first, fall back to dir if it fails
    PRESEED_SUCCESS=false

    # Apply preseed configuration with btrfs
    if cat <<'EOF' | lxd init --preseed 2>/dev/null; then
config: {}
networks:
- name: lxdbr0
  type: bridge
  config:
    ipv4.address: 10.10.10.1/24
    ipv4.nat: "true"
    ipv6.address: none
storage_pools:
- name: default
  driver: btrfs
  config:
    size: 20GB
profiles:
- name: default
  config: {}
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
EOF
        PRESEED_SUCCESS=true
        log_info "LXD initialized with btrfs storage ✓"
    else
        log_warn "btrfs storage failed, trying dir backend..."

        # Fallback to dir driver (works everywhere but slower)
        if cat <<'EOF' | lxd init --preseed; then
config: {}
networks:
- name: lxdbr0
  type: bridge
  config:
    ipv4.address: 10.10.10.1/24
    ipv4.nat: "true"
    ipv6.address: none
storage_pools:
- name: default
  driver: dir
profiles:
- name: default
  config: {}
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
EOF
            PRESEED_SUCCESS=true
            log_info "LXD initialized with dir storage ✓"
        else
            log_error "LXD initialization failed with both btrfs and dir backends"
            exit 1
        fi
    fi
fi

# -------------------------------------------
# Step 6: iptables FORWARD rules for LXD bridge
# -------------------------------------------
# Docker's nftables rules set FORWARD policy to DROP, blocking LXD traffic.
# We need to explicitly allow forwarding for lxdbr0.
log_info "Configuring iptables FORWARD rules for lxdbr0..."

# Check if rules already exist (idempotent)
if ! iptables -C FORWARD -i lxdbr0 -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -i lxdbr0 -j ACCEPT
    log_info "Added FORWARD rule for lxdbr0 incoming ✓"
else
    log_info "FORWARD rule for lxdbr0 incoming already exists ✓"
fi

if ! iptables -C FORWARD -o lxdbr0 -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -o lxdbr0 -j ACCEPT
    log_info "Added FORWARD rule for lxdbr0 outgoing ✓"
else
    log_info "FORWARD rule for lxdbr0 outgoing already exists ✓"
fi

# Make rules persistent (if iptables-persistent is available)
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save 2>/dev/null || true
    log_info "iptables rules saved persistently ✓"
else
    log_warn "netfilter-persistent not installed - iptables rules won't persist across reboot"
    log_warn "Install with: apt install iptables-persistent"
fi

# -------------------------------------------
# Step 7: UFW Configuration (HOST-06)
# -------------------------------------------
log_info "Configuring firewall..."

if command -v ufw &>/dev/null; then
    # Check if UFW is active
    if ufw status | grep -q "Status: active"; then
        log_info "UFW is active, adding rules for lxdbr0..."

        # Add rules (idempotent - ufw skips duplicates)
        ufw allow in on lxdbr0 comment 'LXD bridge incoming'
        ufw route allow in on lxdbr0 comment 'LXD bridge routing in'
        ufw route allow out on lxdbr0 comment 'LXD bridge routing out'

        log_info "UFW rules added for lxdbr0 ✓"
    else
        log_info "UFW not active, skipping firewall rules"
    fi
else
    log_info "UFW not installed, skipping firewall configuration"
fi

# -------------------------------------------
# Step 8: Verification
# -------------------------------------------
echo ""
echo "=========================================="
echo "Verifying Installation"
echo "=========================================="

VERIFICATION_FAILED=false

# Check LXD is running
if snap services lxd | grep -q "active"; then
    log_info "✓ LXD service is active"
else
    log_error "✗ LXD service is not active"
    VERIFICATION_FAILED=true
fi

# Check storage pool
if lxc storage list --format csv 2>/dev/null | grep -q "^default,"; then
    STORAGE_DRIVER=$(lxc storage show default | grep "driver:" | awk '{print $2}')
    log_info "✓ Storage pool 'default' exists (driver: $STORAGE_DRIVER)"
else
    log_error "✗ Storage pool 'default' not found"
    VERIFICATION_FAILED=true
fi

# Check network
if lxc network show lxdbr0 &>/dev/null; then
    IPV4_ADDR=$(lxc network get lxdbr0 ipv4.address)
    log_info "✓ Network 'lxdbr0' exists (subnet: $IPV4_ADDR)"
else
    log_error "✗ Network 'lxdbr0' not found"
    VERIFICATION_FAILED=true
fi

# Check NAT is enabled
NAT_ENABLED=$(lxc network get lxdbr0 ipv4.nat 2>/dev/null || echo "false")
if [[ "$NAT_ENABLED" == "true" ]]; then
    log_info "✓ NAT enabled on lxdbr0"
else
    log_error "✗ NAT not enabled on lxdbr0"
    VERIFICATION_FAILED=true
fi

# Summary
echo ""
if [[ "$VERIFICATION_FAILED" == false ]]; then
    echo "=========================================="
    echo "Host Setup Complete!"
    echo "=========================================="
    echo ""
    log_info "LXD version: $(lxd --version)"
    echo ""
    echo "Next steps:"
    echo "  1. Run ./02-create-container.sh <name> to create a sandbox"
    echo "  2. Run ./03-provision-container.sh <name> <tailscale-key> to provision it"
    echo ""
    exit 0
else
    echo "=========================================="
    echo "Host Setup Completed with Warnings"
    echo "=========================================="
    log_warn "Some verification checks failed - please review above"
    exit 1
fi
