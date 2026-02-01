#!/bin/bash
#
# 04-migrate-project.sh
# Migrates project source code into LXC containers and installs dependencies
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
# - Detects package manager from lockfile (pnpm > yarn > npm)
# - Installs Node version from .nvmrc if present
# - Runs dependency installation with correct package manager
# - Copies .env.example to .env if .env is missing
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

# -------------------------------------------
# Node.js Setup Functions
# -------------------------------------------

# Detect package manager from lockfile
# Precedence: pnpm > yarn > npm (most specific wins)
detect_package_manager() {
    local project_dir="$1"

    # Check inside container
    if lxc exec "$CONTAINER_NAME" -- test -f "$project_dir/pnpm-lock.yaml"; then
        echo "pnpm"
    elif lxc exec "$CONTAINER_NAME" -- test -f "$project_dir/yarn.lock"; then
        echo "yarn"
    elif lxc exec "$CONTAINER_NAME" -- test -f "$project_dir/package-lock.json"; then
        echo "npm"
    else
        # No lockfile - default to npm
        echo "npm"
    fi
}

# Set up Node version from .nvmrc if present
setup_node_version() {
    local project_dir="$1"

    # Check if .nvmrc exists
    if lxc exec "$CONTAINER_NAME" -- test -f "$project_dir/.nvmrc"; then
        log_info "Found .nvmrc, installing required Node version..."
        container_exec "
            export NVM_DIR=\"\$HOME/.nvm\"
            [ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
            cd '$project_dir'
            nvm install
            nvm use
            echo \"Using Node \$(node --version)\"
        "
    else
        log_info "No .nvmrc found, using default Node version"
        container_exec "
            export NVM_DIR=\"\$HOME/.nvm\"
            [ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
            echo \"Using Node \$(node --version)\"
        "
    fi
}

# Install dependencies with the appropriate package manager
install_dependencies() {
    local project_dir="$1"
    local package_manager="$2"

    container_exec "
        export NVM_DIR=\"\$HOME/.nvm\"
        [ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
        cd '$project_dir'

        case '$package_manager' in
            pnpm)
                pnpm install
                ;;
            yarn)
                yarn install
                ;;
            npm)
                npm install
                ;;
        esac
    "

    # Verify node_modules was created
    if ! lxc exec "$CONTAINER_NAME" -- test -d "$project_dir/node_modules"; then
        log_error "node_modules not created - installation may have failed"
        return 1
    fi

    log_info "Dependencies installed successfully"
}

# Copy .env.example to .env if .env doesn't exist
copy_env_example_if_needed() {
    local project_dir="$1"

    # Check if .env does NOT exist AND .env.example exists
    if ! lxc exec "$CONTAINER_NAME" -- test -f "$project_dir/.env"; then
        if lxc exec "$CONTAINER_NAME" -- test -f "$project_dir/.env.example"; then
            log_info "No .env found, copying from .env.example..."
            container_exec "cp '$project_dir/.env.example' '$project_dir/.env'"
            log_warn ".env created from .env.example - review and update values"
        else
            log_warn "No .env or .env.example found"
        fi
    else
        log_info ".env file exists"
    fi
}

# -------------------------------------------
# Node.js Setup Orchestration
# -------------------------------------------

# Main Node.js setup orchestration
setup_nodejs_dependencies() {
    local project_dir="$1"

    log_info "=== Node.js Setup ==="

    # Step 1: .env.example fallback (before npm install may need env vars)
    copy_env_example_if_needed "$project_dir"

    # Step 2: Detect package manager
    local pm
    pm=$(detect_package_manager "$project_dir")
    log_info "Detected package manager: $pm"

    # Step 3: Handle .nvmrc if present
    setup_node_version "$project_dir"

    # Step 4: Install dependencies
    log_info "Installing dependencies..."
    if ! install_dependencies "$project_dir" "$pm"; then
        log_error "Dependency installation failed"
        return 1
    fi

    log_info "Node.js setup complete"
}

# -------------------------------------------
# Transfer Functions
# -------------------------------------------

# Clone a git repository inside the container
clone_git_repository() {
    local repo_url="$1"
    local dest_dir="$2"
    local branch="${3:-}"

    log_info "Cloning repository into container..."

    if [[ -n "$branch" ]]; then
        log_info "Using branch/tag: $branch"
        container_exec "git clone --branch '$branch' '$repo_url' '$dest_dir'"
    else
        container_exec "git clone '$repo_url' '$dest_dir'"
    fi

    # Verify clone succeeded
    if ! lxc exec "$CONTAINER_NAME" -- test -d "$dest_dir/.git"; then
        log_error "Git clone failed - no .git directory found"
        return 1
    fi

    log_info "Repository cloned to $dest_dir"
}

# Copy local directory to container using tar pipe
copy_local_directory() {
    local source_dir="$1"
    local dest_dir="$2"

    log_info "Copying project files (excluding node_modules, .git)..."

    # Convert to absolute path for tar
    local abs_source
    abs_source="$(cd "$source_dir" && pwd)"

    # Create destination directory
    container_exec "mkdir -p '$dest_dir'"

    # Use tar pipe for reliable transfer with exclusions
    # Key: --exclude before -cf, and use . as source (not path)
    tar -C "$abs_source" \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='.next' \
        --exclude='.nuxt' \
        --exclude='.cache' \
        --exclude='coverage' \
        -cf - . | lxc exec "$CONTAINER_NAME" -- tar -C "$dest_dir" -xf -

    log_info "Project copied to $CONTAINER_NAME:$dest_dir"
}

# Copy .env file separately (may be gitignored)
copy_env_file() {
    local source_dir="$1"
    local dest_dir="$2"

    # Convert to absolute path
    local abs_source
    abs_source="$(cd "$source_dir" && pwd)"

    if [[ -f "$abs_source/.env" ]]; then
        log_info "Copying .env file..."
        lxc file push "$abs_source/.env" "$CONTAINER_NAME$dest_dir/.env"
        log_info ".env copied to container"
    else
        log_warn "No .env file found in source"
        if [[ -f "$abs_source/.env.example" ]]; then
            log_info ".env.example exists - will be copied during Node.js setup"
        fi
    fi
}

# -------------------------------------------
# Main Transfer Orchestration
# -------------------------------------------

transfer_project() {
    local source_type
    source_type=$(detect_source_type "$SOURCE")

    local project_name
    project_name=$(derive_project_name "$SOURCE")
    local dest_dir="/root/projects/$project_name"

    log_info "=== Project Migration ==="
    log_info "Container: $CONTAINER_NAME"
    log_info "Source: $SOURCE"
    log_info "Source type: $source_type"
    log_info "Destination: $dest_dir"
    [[ -n "${BRANCH:-}" ]] && log_info "Branch: $BRANCH"
    echo ""

    # Create projects directory
    container_exec "mkdir -p /root/projects"

    case "$source_type" in
        git)
            clone_git_repository "$SOURCE" "$dest_dir" "${BRANCH:-}"
            ;;
        local)
            copy_local_directory "$SOURCE" "$dest_dir"
            # For local copy, also copy .env if it exists
            copy_env_file "$SOURCE" "$dest_dir"
            ;;
        *)
            log_error "Unknown source type: $SOURCE"
            log_error "Source must be a git URL or existing local directory"
            exit 1
            ;;
    esac

    # Verify transfer succeeded
    if ! lxc exec "$CONTAINER_NAME" -- test -d "$dest_dir"; then
        log_error "Transfer failed - destination directory not created"
        exit 1
    fi

    # Show what was transferred
    echo ""
    log_info "=== Transfer Complete ==="
    log_info "Project location: $CONTAINER_NAME:$dest_dir"
    echo ""
    echo "Files in project root:"
    lxc exec "$CONTAINER_NAME" -- ls -la "$dest_dir" | head -15
    echo ""

    # Install Node.js dependencies
    setup_nodejs_dependencies "$dest_dir"

    echo ""
    log_info "=== Migration Complete ==="
    log_info "Project is ready at: $CONTAINER_NAME:$dest_dir"
    echo ""
    log_info "To access the project:"
    echo "  lxc exec $CONTAINER_NAME -- bash"
    echo "  cd $dest_dir"
}

# -------------------------------------------
# Main Execution
# -------------------------------------------

log_info "Starting project migration..."
transfer_project
log_info "Migration complete!"
