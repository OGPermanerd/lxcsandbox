#!/bin/bash
#
# 04-migrate-project.sh
# Transfers project source code into LXC containers via git clone or local copy
# Run as root or with sudo
#
# Usage: ./04-migrate-project.sh <container-name> <source> [--branch <branch>]
#
# Examples:
#   ./04-migrate-project.sh relay-dev https://github.com/user/project.git
#   ./04-migrate-project.sh relay-dev https://github.com/user/project.git --branch main
#   ./04-migrate-project.sh relay-dev git@github.com:user/project.git --branch v1.0.0
#   ./04-migrate-project.sh relay-dev /path/to/local/project
#
# Features:
# - Auto-detects source type (git URL vs local directory)
# - Clones git repos directly inside container with optional --branch
# - Copies local directories via tar pipe, excluding node_modules and .git
# - Copies .env file separately (may be gitignored)
# - Destination is always /root/projects/<project-name>
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
    echo "Usage: ./04-migrate-project.sh <container-name> <source> [--branch <branch>]"
    echo ""
    echo "Arguments:"
    echo "  container-name    Name of existing LXC container"
    echo "  source            Git URL (https:// or git@) or local directory path"
    echo "  --branch <branch> Optional: branch or tag to clone (git sources only)"
    echo ""
    echo "Examples:"
    echo "  # Clone from GitHub (default branch)"
    echo "  ./04-migrate-project.sh relay-dev https://github.com/user/project.git"
    echo ""
    echo "  # Clone specific branch"
    echo "  ./04-migrate-project.sh relay-dev https://github.com/user/project.git --branch main"
    echo ""
    echo "  # Clone specific tag"
    echo "  ./04-migrate-project.sh relay-dev git@github.com:user/project.git --branch v1.0.0"
    echo ""
    echo "  # Copy local directory"
    echo "  ./04-migrate-project.sh relay-dev /path/to/local/project"
    echo ""
    echo "Destination: /root/projects/<project-name> inside container"
    exit 1
fi

CONTAINER_NAME="$1"
SOURCE="$2"
shift 2

# Parse optional --branch flag
BRANCH=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)
            if [[ -n "${2:-}" ]]; then
                BRANCH="$2"
                shift 2
            else
                log_error "--branch requires a value"
                exit 1
            fi
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

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
# Validate Source
# -------------------------------------------
if [[ -z "$SOURCE" ]]; then
    log_error "Source cannot be empty"
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

# Detect if source is a git URL or local directory
detect_source_type() {
    local source="$1"

    if [[ -z "$source" ]]; then
        echo "unknown"
        return 1
    fi

    # Git URL patterns (HTTPS, SSH, git protocol)
    if [[ "$source" =~ ^https?:// ]] && [[ "$source" =~ (\.git$|github\.com|gitlab\.com|bitbucket\.org) ]]; then
        echo "git"
        return 0
    fi

    if [[ "$source" =~ ^git@ ]] || \
       [[ "$source" =~ ^ssh:// ]] || \
       [[ "$source" =~ ^git:// ]]; then
        echo "git"
        return 0
    fi

    # Local path (must exist as directory)
    if [[ -d "$source" ]]; then
        echo "local"
        return 0
    fi

    # Fallback: HTTPS URL without .git might still be git
    if [[ "$source" =~ ^https?:// ]]; then
        echo "git"
        return 0
    fi

    echo "unknown"
    return 1
}

# Extract project name from git URL or local path
derive_project_name() {
    local source="$1"

    # From git URL with .git suffix
    if [[ "$source" =~ \.git$ ]]; then
        basename "$source" .git
        return 0
    fi

    # From git URL without .git (github/gitlab style)
    if [[ "$source" =~ ^https?:// ]] || [[ "$source" =~ ^git@ ]]; then
        basename "$source"
        return 0
    fi

    # From local path (resolve to absolute first)
    basename "$(cd "$source" && pwd)"
}
