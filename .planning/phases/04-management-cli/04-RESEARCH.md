# Phase 4: Management CLI - Research

**Researched:** 2026-02-01
**Domain:** Bash CLI design, argument parsing, user interaction patterns
**Confidence:** HIGH

## Summary

Research focused on bash CLI best practices for building a git-style subcommand interface that wraps existing scripts (02-create-container.sh and 03-provision-container.sh). The domain is mature with well-established patterns for argument parsing, error handling, interactive prompts, and script delegation.

**Key findings:**
- Git-style subcommand pattern is standard for multi-operation CLIs (implemented via case statements calling functions)
- Interactive confirmation prompts use `read -p` with case-insensitive regex matching for Y/y/N/n
- Script delegation via direct execution with `"$@"` argument passing is preferred over sourcing
- Exit codes should follow POSIX convention: 0=success, 1=error, 2=user cancelled
- Existing sandbox.sh already implements basic pattern but needs updates per CONTEXT.md decisions

**Primary recommendation:** Update existing sandbox.sh to match CONTEXT.md decisions - make create accept auth key as argument (not interactive prompt), add auto-snapshot prompts to delete, add pre-restore snapshot with timestamp.

## Standard Stack

The established tools/patterns for bash CLI development:

### Core
| Tool/Pattern | Purpose | Why Standard |
|--------------|---------|--------------|
| bash 4.0+ | Shell scripting | POSIX-compliant, universally available on Linux, rich string manipulation |
| getopts | Flag parsing | Built-in, portable, handles short options (-h, -v) |
| case statements | Subcommand routing | Clean, readable, standard pattern for git-style CLIs |
| read command | Interactive prompts | Built-in, supports prompts, timeouts, single-char input |
| set -euo pipefail | Strict mode | Fail fast, catch unset variables, propagate pipe errors |

### Supporting
| Pattern | Purpose | When to Use |
|---------|---------|-------------|
| trap 'handler' ERR | Error handling | Display context on failures, cleanup resources |
| SCRIPT_DIR resolution | Path handling | Find scripts relative to CLI location, not cwd |
| Color codes (ANSI) | User feedback | Success (green), warnings (yellow), errors (red) |
| Spinner loops | Progress indication | Long-running operations where output isn't useful |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| bash | Python click/typer | Python adds dependency, overkill for simple delegation |
| getopts | getopt (GNU) | getopt supports long options but not portable to BSD/macOS |
| Direct execution | source script | Sourcing pollutes namespace, harder to track exit codes |

**Installation:**
No installation needed - bash is pre-installed on all target systems (Ubuntu 24.04 LXC hosts).

## Architecture Patterns

### Recommended Project Structure
```
dev-sandbox-infra/
├── sandbox.sh              # Main CLI entry point
├── 01-setup-host.sh       # Delegated scripts
├── 02-create-container.sh # (called by sandbox.sh)
└── 03-provision-container.sh
```

### Pattern 1: Git-Style Subcommand Routing
**What:** Main script routes to command-specific functions via case statement
**When to use:** Multiple related operations (create, delete, list, etc.)
**Example:**
```bash
# Source: Existing sandbox.sh + common bash patterns
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Command functions
cmd_create() { ... }
cmd_delete() { ... }

# Main routing
COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    create) cmd_create "$@" ;;
    delete) cmd_delete "$@" ;;
    *)
        echo "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac
```

### Pattern 2: Script Delegation with Argument Passing
**What:** Call external scripts with explicit paths and pass arguments
**When to use:** Reusing existing scripts (02-create, 03-provision)
**Example:**
```bash
# Source: Existing sandbox.sh cmd_create + bash best practices
cmd_create() {
    local name="$1"
    local ts_key="$2"

    # Validate before delegating
    if [[ -z "$name" || -z "$ts_key" ]]; then
        echo "Usage: sandbox.sh create <name> <tailscale-key>"
        exit 1
    fi

    # Delegate to existing scripts with explicit paths
    "$SCRIPT_DIR/02-create-container.sh" "$name"
    "$SCRIPT_DIR/03-provision-container.sh" "$name" "$ts_key"
}
```

### Pattern 3: Interactive Confirmation with Safe Defaults
**What:** Prompt user with yes/no, default to safe option
**When to use:** Destructive operations (delete, restore)
**Example:**
```bash
# Source: Multiple bash confirmation tutorials + existing sandbox.sh
# Safe default: uppercase N in prompt, empty = no
read -p "Delete container '$name'? This cannot be undone. [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Proceed with destructive operation
```

### Pattern 4: Auto-Snapshot Before Destructive Operations
**What:** Create timestamped snapshot before restore/delete
**When to use:** Operations that modify/delete container state
**Example:**
```bash
# Source: Existing 02-create-container.sh handle_existing_container + CONTEXT.md
# Create safety snapshot with timestamp
local snap_name="pre-restore-$(date +%Y%m%d-%H%M%S)"
lxc snapshot "$name" "$snap_name"
echo "Created safety snapshot: $name/$snap_name"

# Proceed with restore
lxc restore "$name" "$target_snapshot"
```

### Anti-Patterns to Avoid
- **Sourcing scripts instead of executing:** Pollutes namespace, makes exit codes unreliable
- **Interactive prompts in create command:** Breaks scriptability (CONTEXT.md decision: use arguments)
- **Using getopts for subcommands:** getopts is for flags, not subcommands (use case statement)
- **Forgetting shift after case:** Causes "$@" to include the command name

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Argument validation | String parsing | Existing validation functions | 02-create has DNS-compatible name validator |
| Wait for container ready | Sleep loops | Existing wait functions | 02-create has network wait, 03-provision has Tailscale wait |
| Container existence check | Parse lxc list | `lxc info "$name" &>/dev/null` | Built-in, reliable, handles edge cases |
| Progress indication | Complex spinners | Existing spinner pattern | 02-create and 03-provision have working implementations |

**Key insight:** The 02-create and 03-provision scripts already handle complexity (validation, waiting, error recovery). The CLI should delegate, not duplicate.

## Common Pitfalls

### Pitfall 1: Interactive Prompts Breaking Scriptability
**What goes wrong:** Using `read -p` for required inputs makes automation impossible
**Why it happens:** Developer prioritizes UX over automation in create command
**How to avoid:** Accept required arguments on command line (per CONTEXT.md decision)
**Warning signs:** Cannot use in cron, CI/CD, or other scripts
**Example:**
```bash
# BAD: Current sandbox.sh create (breaks automation)
read -p "Tailscale auth key: " ts_key

# GOOD: Accept as argument (CONTEXT.md decision)
cmd_create() {
    local name="$1"
    local ts_key="$2"
    # ... validate and delegate
}
```

### Pitfall 2: Forgetting to Handle Empty Arguments
**What goes wrong:** `shift` fails if no arguments, causing script to exit
**Why it happens:** `set -e` exits on any non-zero return, shift on empty array returns 1
**How to avoid:** Use `shift || true` or check $# before shifting
**Warning signs:** Script fails with "shift: can't shift that many" or exits silently
**Example:**
```bash
# BAD: Fails if no arguments
COMMAND="$1"
shift

# GOOD: Safe for empty argument list
COMMAND="${1:-}"
shift || true
```

### Pitfall 3: Not Stopping Container Before Restore
**What goes wrong:** Restoring running container can cause data corruption
**Why it happens:** LXC allows restore on running containers but it's unsafe
**How to avoid:** Stop container before restore (per LXC best practices research)
**Warning signs:** Inconsistent state after restore, file corruption
**Example:**
```bash
# GOOD: Stop before restore (from LXC best practices)
local status
status=$(lxc info "$name" | grep 'Status:' | awk '{print $2}')
if [[ "$status" == "RUNNING" ]]; then
    lxc stop "$name" --timeout 30
fi
lxc restore "$name" "$snapshot"
```

### Pitfall 4: Exit Code Confusion
**What goes wrong:** Using exit 1 for user cancellation same as errors
**Why it happens:** Not distinguishing between error types
**How to avoid:** Use 0=success, 1=error, 2=user cancelled
**Warning signs:** Can't distinguish user choice from failures in automation
**Example:**
```bash
# GOOD: Different exit codes (CONTEXT.md decision)
read -p "Continue? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 2  # User cancelled, not error
fi
```

### Pitfall 5: Not Validating Container Exists Before Operations
**What goes wrong:** Operations fail with cryptic LXC errors
**Why it happens:** Assuming container exists without checking
**How to avoid:** Validate with `lxc info "$name" &>/dev/null` before operations
**Warning signs:** Confusing error messages like "Error: not found"
**Example:**
```bash
# GOOD: Validate before operating
validate_container_exists() {
    local name="$1"
    if ! lxc info "$name" &>/dev/null; then
        echo "Error: Container '$name' does not exist"
        exit 1
    fi
}
```

## Code Examples

Verified patterns from official sources and existing implementation:

### Interactive Yes/No Prompt (Safe Default)
```bash
# Source: 02-create-container.sh + bash prompt best practices
# Safe default: No (uppercase N, empty response = no)
read -p "Delete container '$name'? This cannot be undone. [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 2  # User cancelled
fi

# Proceed with destructive action
```

### LXC Container Operations
```bash
# Source: Existing scripts + LXC documentation

# Check if container exists
if ! lxc info "$name" &>/dev/null; then
    echo "Error: Container '$name' does not exist"
    exit 1
fi

# Get container status
status=$(lxc info "$name" | grep 'Status:' | awk '{print $2}')

# Stop container safely
if [[ "$status" == "RUNNING" ]]; then
    lxc stop "$name" --timeout 30
fi

# Create snapshot with timestamp
snap_name="backup-$(date +%Y%m%d-%H%M%S)"
lxc snapshot "$name" "$snap_name"

# Restore from snapshot (stop first per best practices)
lxc stop "$name" --timeout 30 || true
lxc restore "$name" "$snap_name"

# Delete with force (handles running containers)
lxc delete "$name" --force
```

### Timestamp Generation
```bash
# Source: bash date command documentation
# ISO 8601-style compact timestamp for snapshot names
date +%Y%m%d-%H%M%S  # Output: 20260201-143022

# Full ISO 8601 with timezone
date -I'seconds'  # Output: 2026-02-01T14:30:22-05:00
```

### Script Directory Resolution
```bash
# Source: Existing sandbox.sh + bash best practices
# Resolve script directory (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call sibling scripts with absolute path
"$SCRIPT_DIR/02-create-container.sh" "$name"
```

### Container Name Validation
```bash
# Source: 02-create-container.sh validate_container_name
# DNS-compatible: 2-30 chars, lowercase, start with letter, no double-hyphens
validate_container_name() {
    local name="$1"

    # Length check
    if [[ ${#name} -lt 2 || ${#name} -gt 30 ]]; then
        echo "Error: Name must be 2-30 characters"
        return 1
    fi

    # DNS-style format
    if ! [[ "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
        echo "Error: Must start with letter, contain only lowercase/numbers/hyphens"
        return 1
    fi

    # No consecutive hyphens
    if [[ "$name" =~ -- ]]; then
        echo "Error: Cannot contain consecutive hyphens"
        return 1
    fi

    return 0
}
```

### Help/Usage Display
```bash
# Source: Existing sandbox.sh + CLI guidelines
show_usage() {
    cat << 'EOF'
Dev Sandbox Management

Usage: sandbox.sh <command> [arguments]

Commands:
  create <name> <tailscale-key>  Create and provision new sandbox
  shell <name>                   Open bash shell in container
  list                           List all sandboxes
  snapshot <name> [snapshot-name] Create named snapshot
  restore <name> <snapshot-name> Restore from snapshot
  delete <name>                  Delete container with confirmation
  info <name>                    Show container details and IPs

Examples:
  sandbox.sh create relay-dev tskey-auth-xxxxx
  sandbox.sh shell relay-dev
  sandbox.sh snapshot relay-dev before-migration
  sandbox.sh restore relay-dev before-migration
  sandbox.sh delete relay-dev

EOF
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual script calls | Unified CLI wrapper | 2020s (git popularized) | Single entry point, consistent UX |
| Interactive create | Argument-based create | 2026 (CONTEXT.md) | Enables automation, scriptability |
| No safety snapshots | Auto-snapshot on destructive ops | 2026 (CONTEXT.md) | Prevents accidental data loss |
| set -e only | set -euo pipefail | ~2015 | Catches more errors (unset vars, pipe failures) |

**Deprecated/outdated:**
- `getopt` (GNU version): Non-portable, use getopts for short flags or manual parsing for long flags
- Sourcing scripts: Use execution with "$@" for delegation instead
- `function` keyword: Optional in bash, omit for POSIX compatibility

## Open Questions

None - the domain is mature and well-documented. All requirements can be implemented using established patterns.

## Sources

### Primary (HIGH confidence)
- Existing sandbox.sh implementation - Current working patterns for subcommand routing
- 02-create-container.sh - Container name validation, snapshot patterns, confirmation prompts
- 03-provision-container.sh - Script delegation, argument validation, wait patterns
- [Command Line Interface Guidelines](https://clig.dev/) - Modern CLI design principles
- [BashGuide/Practices](https://mywiki.wooledge.org/BashGuide/Practices) - Greg's Wiki authoritative bash guide
- [Shell Script Best Practices](https://sharats.me/posts/shell-script-best-practices/) - Comprehensive bash scripting guide
- [LXC snapshot documentation](https://www.cyberciti.biz/faq/create-snapshots-with-lxc-command-lxd/) - Official LXC snapshot commands
- [Linux date manual page](https://man7.org/linux/man-pages/man1/date.1.html) - Timestamp generation

### Secondary (MEDIUM confidence)
- [Bash Getopts Examples](https://kodekloud.com/blog/bash-getopts/) - Argument parsing patterns verified with official docs
- [Bash Interactive Prompts](https://www.baeldung.com/linux/bash-interactive-prompts) - Confirmation prompt patterns (March 2025)
- [Bash Exit Codes Best Practices](https://www.geeksforgeeks.org/linux-unix/how-to-exit-when-errors-occur-in-bash-scripts/) - Error handling verified with existing scripts
- [LXC Restore Best Practices](https://bobcares.com/blog/lxc-restore-snapshot/) - Stop before restore recommendation
- [Bash Spinner Implementations](https://www.baeldung.com/linux/bash-show-spinner-long-tasks) - Progress indication patterns

### Tertiary (LOW confidence)
None - all findings verified with authoritative sources or existing working code

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - bash, getopts, case statements are established, universal tools
- Architecture: HIGH - git-style subcommand pattern is industry standard, existing sandbox.sh proves viability
- Pitfalls: HIGH - identified from existing code review and official LXC documentation
- Code examples: HIGH - all examples from existing working scripts or official documentation

**Research date:** 2026-02-01
**Valid until:** 2026-09-01 (6 months - bash tooling is stable, no major changes expected)
