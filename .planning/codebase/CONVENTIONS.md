# Coding Conventions

**Analysis Date:** 2026-02-01

## Project Overview

This is a bash-based infrastructure management project for creating and provisioning isolated LXC containers with full development stacks. All code is written in shell scripts with no JavaScript, TypeScript, or other compiled languages.

## Naming Patterns

**Files:**
- Numbered scripts with clear purpose: `01-setup-host.sh`, `02-create-container.sh`, `03-provision-container.sh`
- Functional utility script: `sandbox.sh` (wrapper for common operations)
- Documentation: README.md, CLAUDE.md (project context), CONTEXT.md
- Pattern: All executable scripts use `.sh` extension

**Functions:**
- Snake_case with `cmd_` prefix for subcommand handlers: `cmd_list()`, `cmd_create()`, `cmd_delete()`, `cmd_shell()`
- Descriptive names reflecting operation: `log_info()`, `log_warn()`, `log_error()`, `log_step()`
- Variables remain snake_case: `CONTAINER_NAME`, `TAILSCALE_KEY`, `UBUNTU_VERSION`

**Variables:**
- All-caps for constants and environment variables: `RED`, `GREEN`, `YELLOW`, `NC`, `CONTAINER_NAME`
- Lower-case in function parameters and local scopes within bash blocks
- Explicit export for environment variables passed to containers: `export NVM_DIR`, `export PGUSER`

**Types:**
- Strings in quotes, variables expanded with `"$VAR"` syntax
- Conditionals use `[[ ]]` (bash preferred) over `[ ]` for reliability
- Regex patterns in conditionals: `[[ ! "$CONTAINER_NAME" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]`

## Code Style

**Formatting:**
- No formal linter configured (bash linting tools like ShellCheck not enforced)
- Consistent indentation: 4 spaces (observed in nested blocks)
- Lines break at logical boundaries, not character limits
- Clear section headers with dashes: `# -------------------------------------------`

**Error Handling:**
- All scripts start with: `set -euo pipefail`
  - `set -e`: Exit on error
  - `set -u`: Error on undefined variables
  - `set -o pipefail`: Fail if any command in pipeline fails
- Root/sudo checks enforced early:
  ```bash
  if [[ $EUID -ne 0 ]]; then
     log_error "This script must be run as root (or with sudo)"
     exit 1
  fi
  ```
- Validation happens before operations: Check if container exists before provisioning
- Error messages logged with context: `log_error "Container '$CONTAINER_NAME' already exists"`

**Logging:**
- Color-coded output functions for clarity:
  - `log_info()`: Green [INFO] - successful operations
  - `log_warn()`: Yellow [WARN] - non-fatal issues
  - `log_error()`: Red [ERROR] - failures
  - `log_step()`: Cyan [STEP] - progress through multi-step operations
- All user-facing output uses these functions, not bare `echo`
- Usage pattern:
  ```bash
  log_info "Container launched"
  log_error "Container failed to start"
  log_step "Installing Tailscale..."
  ```

**Comments:**
- File header comments for all scripts:
  ```bash
  #!/bin/bash
  #
  # 01-setup-host.sh
  # One-time setup for LXD host infrastructure on Hetzner VPS
  # Run as root or with sudo
  #
  ```
- Section separators with dashes and descriptive headers
- Usage comments above main argument parsing
- Inline comments sparingly for non-obvious logic

## Command Line Argument Handling

**Pattern:**
- Check argument count first: `if [[ $# -lt 2 ]]; then ... exit 1; fi`
- Assign to named variables immediately:
  ```bash
  CONTAINER_NAME="$1"
  TAILSCALE_KEY="$2"
  ```
- Validation after assignment (name format, existence checks)
- Usage help with examples before exit:
  ```bash
  echo "Usage: $0 <container-name> <tailscale-authkey>"
  echo "Example: $0 relay-dev tskey-auth-xxxxx"
  exit 1
  ```
- Optional parameters with defaults: `UBUNTU_VERSION="${2:-24.04}"`

## Bash Multiline Commands

**Pattern for inline bash:**
- Use `lxc exec` to run bash blocks inside containers
- Quoted with double quotes when variables need expansion:
  ```bash
  lxc exec "$CONTAINER_NAME" -- bash -c "
      tailscale up --authkey=$TAILSCALE_KEY --hostname=$CONTAINER_NAME
  "
  ```
- Single quotes for literal bash when no variable substitution:
  ```bash
  lxc exec "$CONTAINER_NAME" -- bash -c '
      apt-get install -y postgresql
      systemctl enable postgresql
  '
  ```

## Function Design

**Size:** Functions are task-focused, 5-30 lines typical
- Example: `cmd_list()` is 4 lines (format and display)
- Example: `cmd_create()` is 15 lines (prompt, validate, call subscripts)

**Parameters:**
- Functions receive positional args from shift: `cmd_create() { local name="$1"; ... }`
- Validation of required args at function start
- Clear error message if args missing

**Return Values:**
- Exit with `exit 0` on success (implicit)
- Exit with `exit 1` on failure with preceding error log
- No return value functions; rely on exit codes and log messages

## Module Design

**Scripts:**
- Each numbered script is a self-contained module with clear lifecycle
- `01-setup-host.sh`: Idempotent setup (checks before installing)
- `02-create-container.sh`: Creates infrastructure
- `03-provision-container.sh`: Installs software
- `sandbox.sh`: Wrapper/orchestrator calling other scripts

**Exports:**
- No exported functions; each script can be run independently
- Information passed via stdout and exit codes
- Shared by convention (all follow same logging pattern)

**Command Structure:**
- `sandbox.sh` implements subcommand pattern:
  ```bash
  case "$COMMAND" in
      list)   cmd_list "$@"     ;;
      create) cmd_create "$@"   ;;
      delete) cmd_delete "$@"   ;;
  esac
  ```
- Help function `show_help()` centralized in `sandbox.sh`

## Status Checking Patterns

**Container existence:**
```bash
if lxc info "$CONTAINER_NAME" &> /dev/null; then
    log_error "Container already exists"
    exit 1
fi
```

**Container running state:**
```bash
STATUS=$(lxc info "$CONTAINER_NAME" | grep 'Status:' | awk '{print $2}')
if [[ "$STATUS" != "RUNNING" ]]; then
    log_error "Container not running"
    exit 1
fi
```

**Network availability (polling):**
```bash
for i in {1..30}; do
    if lxc exec "$CONTAINER_NAME" -- ping -c 1 8.8.8.8 &> /dev/null; then
        log_info "Network ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        log_error "Network failed after 30 seconds"
        exit 1
    fi
    sleep 1
done
```

**Lock file avoidance:**
```bash
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 1
done
```

## Configuration and Defaults

**Environment Variables:**
- `TAILSCALE_AUTHKEY`: Passed from environment or prompted
- `NVM_DIR`: Set inside containers, sourced for node access
- `DATABASE_URL`: Generated during provisioning
- Credentials hardcoded in provisioning: `dev` user with `dev` password (dev-only sandbox)

**Hardcoded Values:**
- Resource limits: 4GB RAM, 2 CPU cores (documented, easy to customize)
- Network subnet: 10.10.10.0/24 (LXD bridge)
- Node version: 22 (via nvm)
- PostgreSQL defaults: user=dev, password=dev, database=dev

## Exit Codes

- `0`: Success
- `1`: General error (wrong args, missing prerequisites, operation failure)
- No distinction between error types; all use exit 1

## Interactive Patterns

**User prompts:**
```bash
read -p "Install Tailscale on host? (y/n) [n]: " INSTALL_TS_HOST
INSTALL_TS_HOST=${INSTALL_TS_HOST:-n}

if [[ "$INSTALL_TS_HOST" =~ ^[Yy]$ ]]; then
    # proceed
fi
```

**Confirmation for destructive operations:**
```bash
read -p "Delete sandbox '$name'? This cannot be undone. (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    lxc delete "$name" --force
else
    echo "Cancelled"
fi
```

## Output Structure

**Standard progression:**
1. Header with dashes: `echo "=========================================="`
2. Steps logged as they execute: `log_step "Installing Node.js..."`
3. Info after completion: `log_info "Node.js installed"`
4. Final summary with key data at end
5. Clear next steps shown to user

**Example:**
```
==========================================
Creating Dev Sandbox: relay-dev
==========================================

[STEP] Launching container...
[INFO] Container launched
[STEP] Configuring for Tailscale...
[INFO] TUN device added

==========================================
Container Created Successfully!
==========================================

Container: relay-dev
Image: ubuntu:24.04
Status: RUNNING
Internal IP: 10.10.10.5

Next step:
  ./03-provision-container.sh relay-dev <tailscale-authkey>
```

---

*Convention analysis: 2026-02-01*
