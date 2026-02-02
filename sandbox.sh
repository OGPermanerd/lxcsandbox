#!/bin/bash
#
# sandbox.sh
# Helper script for common sandbox operations
#
# Usage: ./sandbox.sh <command> [args]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config if exists (for TAILSCALE_AUTHKEY, etc.)
if [[ -f "$SCRIPT_DIR/.sandbox.conf" ]]; then
    source "$SCRIPT_DIR/.sandbox.conf"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helper function to validate container existence
validate_container_exists() {
    local name="$1"
    if ! lxc info "$name" &>/dev/null; then
        echo "Error: Container '$name' does not exist"
        exit 1
    fi
}

show_help() {
    echo "Dev Sandbox Management"
    echo ""
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  create <name> <tailscale-key>  Create and provision new sandbox"
    echo "  migrate <name> <source>        Migrate project into sandbox (creates snapshot first)"
    echo "  shell <name>                   Open bash shell in container"
    echo "  list                           List all sandboxes with status"
    echo "  snapshot <name> [label]        Create named snapshot (default: auto-timestamp)"
    echo "  restore <name> <label>         Restore from snapshot (auto-backups current state)"
    echo "  delete <name>                  Delete container (prompts for confirmation)"
    echo "  info <name>                    Show container details and Tailscale IP"
    echo ""
    echo "Exit codes:"
    echo "  0  Success"
    echo "  1  Error (invalid arguments, command failed)"
    echo "  2  User cancelled"
    echo ""
    echo "Examples:"
    echo "  $0 create relay-dev tskey-auth-xxxxx"
    echo "  sudo $0 migrate relay-dev https://github.com/user/project.git"
    echo "  $0 shell relay-dev"
    echo "  $0 snapshot relay-dev before-migration"
    echo "  $0 restore relay-dev before-migration"
    echo "  $0 delete relay-dev"
    echo ""
}

cmd_list() {
    echo -e "${CYAN}Dev Sandboxes:${NC}"
    echo ""
    lxc list --format table -c ns4tS
}

cmd_create() {
    local name="${1:-}"
    local ts_key="${2:-${TAILSCALE_AUTHKEY:-}}"

    if [[ -z "$name" ]]; then
        echo "Usage: $0 create <name> [tailscale-key]"
        echo "       $0 create <name> --no-tailscale"
        echo ""
        echo "Options:"
        echo "  --no-tailscale    Skip Tailscale setup (local development only)"
        echo ""
        echo "If no key provided, uses TAILSCALE_AUTHKEY from .sandbox.conf"
        exit 1
    fi

    # Create the container
    "$SCRIPT_DIR/02-create-container.sh" "$name"

    # Provision based on options
    if [[ "$ts_key" == "--no-tailscale" ]]; then
        echo -e "${CYAN}Provisioning without Tailscale...${NC}"
        "$SCRIPT_DIR/03-provision-container.sh" "$name" "--no-tailscale"
    elif [[ -n "$ts_key" ]]; then
        echo -e "${CYAN}Using Tailscale auth key from ${2:+command line}${2:-config}${NC}"
        "$SCRIPT_DIR/03-provision-container.sh" "$name" "$ts_key"
    else
        echo "Error: No Tailscale auth key provided"
        echo ""
        echo "Either:"
        echo "  1. Pass key as argument: $0 create $name tskey-auth-xxx"
        echo "  2. Add to .sandbox.conf: TAILSCALE_AUTHKEY=\"tskey-auth-xxx\""
        echo "  3. Skip Tailscale: $0 create $name --no-tailscale"
        exit 1
    fi
}

cmd_delete() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        echo "Usage: $0 delete <name>"
        exit 1
    fi

    validate_container_exists "$name"

    # Prompt for safety snapshot
    read -p "Create snapshot before deleting? [Y/n]: " create_snap
    if [[ ! "$create_snap" =~ ^[Nn]$ ]]; then
        local snapshot_label="pre-delete-$(date +%Y%m%d-%H%M%S)"
        lxc snapshot "$name" "$snapshot_label"
        echo "Created snapshot: $snapshot_label"
    fi

    # Confirm deletion
    read -p "Delete container '$name'? This cannot be undone. [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        lxc delete "$name" --force
        echo "Sandbox '$name' deleted"
    else
        echo "Cancelled"
        exit 2
    fi
}

cmd_shell() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        echo "Usage: $0 shell <name>"
        exit 1
    fi

    validate_container_exists "$name"

    lxc exec "$name" -- bash -l
}

cmd_snapshot() {
    local name="${1:-}"
    local label="${2:-}"

    if [[ -z "$name" ]]; then
        echo "Usage: $0 snapshot <name> [label]"
        exit 1
    fi

    validate_container_exists "$name"

    # Generate default label if not provided
    if [[ -z "$label" ]]; then
        label="manual-$(date +%Y%m%d-%H%M%S)"
    fi

    lxc snapshot "$name" "$label"
    echo "Snapshot '$label' created for '$name'"
    echo ""
    echo "Snapshots for $name:"
    lxc info "$name" | grep -A 100 "Snapshots:" | head -20
}

cmd_restore() {
    local name="${1:-}"
    local label="${2:-}"

    if [[ -z "$name" || -z "$label" ]]; then
        echo "Usage: $0 restore <name> <label>"
        exit 1
    fi

    validate_container_exists "$name"

    # Verify snapshot exists
    if ! lxc info "$name" | grep -q "^ *$label "; then
        echo "Error: Snapshot '$label' does not exist for container '$name'"
        exit 1
    fi

    # Create automatic backup before restore
    local backup_label="pre-restore-$(date +%Y%m%d-%H%M%S)"
    echo "Creating automatic backup: $backup_label"
    lxc snapshot "$name" "$backup_label"

    # Stop container before restore
    echo "Stopping container..."
    lxc stop "$name" --timeout 30 2>/dev/null || true

    # Restore from specified snapshot
    echo "Restoring from snapshot '$label'..."
    lxc restore "$name" "$label"

    # Optionally restart container
    read -p "Restart container now? [Y/n]: " restart
    if [[ ! "$restart" =~ ^[Nn]$ ]]; then
        lxc start "$name"
        echo "Container restarted"
    fi

    echo "Restored '$name' to '$label'"
    echo "Backup created: $backup_label"
}

cmd_info() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        echo "Usage: $0 info <name>"
        exit 1
    fi

    validate_container_exists "$name"

    echo -e "${CYAN}Sandbox: $name${NC}"
    echo ""

    # Basic info
    lxc list "$name" --format table -c ns4tS

    echo ""
    echo "Tailscale IP: $(lxc exec "$name" -- tailscale ip -4 2>/dev/null || echo 'not connected')"
    echo ""

    # Snapshots
    echo "Snapshots:"
    lxc info "$name" | grep -A 100 "Snapshots:" | tail -n +2 | head -10 || echo "  (none)"
}

cmd_migrate() {
    local container="${1:-}"
    local source="${2:-}"

    # Validate arguments
    if [[ -z "$container" || -z "$source" ]]; then
        echo "Usage: $0 migrate <container> <source> [--branch <branch>] [--force]"
        echo ""
        echo "Migrate a project into a sandbox container."
        echo ""
        echo "Arguments:"
        echo "  container    Name of existing LXC container"
        echo "  source       Git URL or local directory path"
        echo ""
        echo "Options:"
        echo "  --branch <branch>   Clone specific branch or tag (git sources only)"
        echo "  --force             Force re-migration if project already exists"
        echo ""
        echo "Examples:"
        echo "  sudo $0 migrate relay-dev https://github.com/user/project.git"
        echo "  sudo $0 migrate relay-dev /home/user/myproject"
        echo "  sudo $0 migrate relay-dev https://github.com/user/repo.git --branch main"
        echo "  sudo $0 migrate relay-dev https://github.com/user/repo.git --force"
        exit 1
    fi

    # Root check (04-migrate-project.sh requires root)
    if [[ $EUID -ne 0 ]]; then
        echo "Error: migrate command requires root (or sudo)"
        echo "Usage: sudo $0 migrate <container> <source>"
        exit 1
    fi

    # Validate container exists
    validate_container_exists "$container"

    shift 2  # Remove container and source from args

    # Create pre-migration snapshot
    local snapshot_label="pre-migrate-$(date +%Y%m%d-%H%M%S)"
    echo -e "${CYAN}Creating pre-migration snapshot: $snapshot_label${NC}"
    lxc snapshot "$container" "$snapshot_label"

    # Delegate to migration script (handles file transfer, deps, database)
    # Pass remaining args for --branch and --force support
    if ! "$SCRIPT_DIR/04-migrate-project.sh" "$container" "$source" "$@"; then
        echo ""
        echo -e "${RED}[ERROR]${NC} Migration failed"
        echo ""
        echo "To rollback to pre-migration state:"
        echo "  $0 restore $container $snapshot_label"
        exit 1
    fi

    # Success - show snapshot info
    echo ""
    echo -e "${GREEN}Pre-migration snapshot available:${NC} $snapshot_label"
    echo "To rollback if needed: $0 restore $container $snapshot_label"
}

# -------------------------------------------
# Main
# -------------------------------------------

if [[ $# -lt 1 ]]; then
    show_help
    exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in
    list)
        cmd_list "$@"
        ;;
    create)
        cmd_create "$@"
        ;;
    migrate)
        cmd_migrate "$@"
        ;;
    delete)
        cmd_delete "$@"
        ;;
    shell)
        cmd_shell "$@"
        ;;
    snapshot)
        cmd_snapshot "$@"
        ;;
    restore)
        cmd_restore "$@"
        ;;
    info)
        cmd_info "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac
