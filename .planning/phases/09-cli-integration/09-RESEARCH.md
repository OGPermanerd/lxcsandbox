# Phase 9: CLI Integration - Research

**Researched:** 2026-02-01
**Domain:** Bash CLI integration, LXC snapshot safety, migration UX patterns
**Confidence:** HIGH

## Summary

Phase 9 integrates the migration backend (04-migrate-project.sh) into the unified sandbox.sh CLI. The phase focuses on UX polish: automatic pre-migration snapshots for safety, re-migration detection with user options, clear output formatting, and a final migration summary.

Research confirms the implementation approach:
1. Add `migrate` command to sandbox.sh that delegates to 04-migrate-project.sh
2. Create pre-migration snapshot before calling the backend script
3. Check for existing project directory and offer re-migration options (overwrite, skip, rename)
4. Capture and format the backend script output with clear success/error messages
5. Generate a migration summary showing what was detected and what actions were taken

**Primary recommendation:** Use the existing sandbox.sh patterns (cmd_* functions, validate_container_exists, confirmation prompts) and extend 04-migrate-project.sh to support project existence detection and summary output.

## Standard Stack

The established tools for this domain:

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| sandbox.sh | current | CLI wrapper | Already implements 7 commands with consistent patterns |
| 04-migrate-project.sh | current | Migration backend | Full implementation from Phases 6-8 |
| lxc snapshot | LXD current | Pre-migration backup | Already used in sandbox.sh restore/delete |
| lxc exec test | LXD current | Project existence check | Standard LXC file test pattern |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| lxc info | Container validation | Before any migration operation |
| date +%Y%m%d-%H%M%S | Snapshot naming | Consistent with existing timestamp format |
| read -p | User prompts | Re-migration option selection |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Auto snapshot | Prompt for snapshot | Auto is safer, matches restore pattern |
| Interactive re-migration | Auto-fail on exists | User choice is better UX |
| Summary in sandbox.sh | Summary from 04-migrate | Keep summary logic with migration details |

**No additional packages needed:** All functionality uses existing bash builtins and LXC commands.

## Architecture Patterns

### Recommended Integration Structure
```
sandbox.sh
+-- cmd_migrate()
|     +-- validate_container_exists()  # Existing helper
|     +-- validate_source()            # New helper
|     +-- create_pre_migration_snapshot()
|     +-- check_project_exists()
|     |     +-- prompt_remigration_options() if exists
|     +-- delegate to 04-migrate-project.sh
|     +-- show_migration_summary()
|
04-migrate-project.sh (additions)
+-- detect_existing_project()  # Check if project dir exists
+-- handle_existing_project()  # Overwrite/skip/rename logic
+-- generate_summary()         # Collect what was done for final output
```

### Pattern 1: Pre-Migration Snapshot
**What:** Automatically create snapshot before any migration changes
**When to use:** At the start of migrate command, before any changes
**Example:**
```bash
# Source: Existing sandbox.sh cmd_restore pattern
create_pre_migration_snapshot() {
    local name="$1"
    local snapshot_label="pre-migrate-$(date +%Y%m%d-%H%M%S)"

    log_info "Creating pre-migration snapshot: $snapshot_label"
    lxc snapshot "$name" "$snapshot_label"

    echo "$snapshot_label"  # Return for potential rollback reference
}
```

### Pattern 2: Project Existence Detection
**What:** Check if project already exists at `/root/projects/<name>` in container
**When to use:** Before calling migration backend
**Example:**
```bash
# Source: LXC exec test pattern from 04-migrate-project.sh
check_project_exists() {
    local container="$1"
    local project_name="$2"
    local dest_dir="/root/projects/$project_name"

    if lxc exec "$container" -- test -d "$dest_dir"; then
        return 0  # Exists
    fi
    return 1  # Does not exist
}
```

### Pattern 3: Re-Migration Options
**What:** Offer user choices when project already exists
**When to use:** When check_project_exists returns true
**Example:**
```bash
# Source: Existing sandbox.sh confirmation patterns
prompt_remigration_options() {
    local project_name="$1"

    echo ""
    echo "Project '$project_name' already exists in container."
    echo ""
    echo "Options:"
    echo "  1) Overwrite - Delete existing and migrate fresh"
    echo "  2) Skip - Cancel migration, keep existing"
    echo "  3) Rename - Migrate as '$project_name-YYYYMMDD-HHMMSS'"
    echo ""
    read -p "Choose [1/2/3]: " choice

    case "$choice" in
        1) echo "overwrite" ;;
        2) echo "skip" ;;
        3) echo "rename" ;;
        *) echo "invalid" ;;
    esac
}
```

### Pattern 4: Migration Summary Output
**What:** Show what was detected and what actions were taken
**When to use:** At the end of successful migration
**Example:**
```bash
# Source: Existing 04-migrate-project.sh output patterns
show_migration_summary() {
    local container="$1"
    local project_name="$2"
    local dest_dir="/root/projects/$project_name"

    echo ""
    echo "=========================================="
    echo "Migration Summary"
    echo "=========================================="
    echo ""
    echo "Container:        $container"
    echo "Project:          $project_name"
    echo "Location:         $dest_dir"
    echo ""
    echo "Detected:"
    echo "  Package Manager: [npm|yarn|pnpm]"
    echo "  Node Version:    [from .nvmrc or default]"
    echo "  Database:        [created: <db_name>]"
    echo "  Migrations:      [prisma|drizzle|sql|none]"
    echo ""
    echo "Actions Taken:"
    echo "  [x] Pre-migration snapshot created"
    echo "  [x] Project files transferred"
    echo "  [x] Dependencies installed"
    echo "  [x] Database created"
    echo "  [x] Migrations applied"
    echo ""
    echo "Next Steps:"
    echo "  ./sandbox.sh shell $container"
    echo "  cd $dest_dir"
    echo "  npm run dev  # or your start command"
    echo ""
}
```

### Pattern 5: Error Handling with Rollback Hint
**What:** On failure, inform user about snapshot for recovery
**When to use:** When migration fails after snapshot created
**Example:**
```bash
# Source: Existing sandbox.sh error patterns
handle_migration_error() {
    local container="$1"
    local snapshot_label="$2"
    local error_msg="$3"

    log_error "$error_msg"
    echo ""
    echo "Migration failed. To rollback:"
    echo "  ./sandbox.sh restore $container $snapshot_label"
    echo ""
    exit 1
}
```

### Anti-Patterns to Avoid
- **Modifying container before snapshot:** Always snapshot first
- **Silently overwriting projects:** Always ask user when project exists
- **Hiding errors from backend:** Let 04-migrate-project.sh errors bubble up
- **Not validating source before snapshot:** Validate early to avoid unnecessary snapshots
- **Interactive prompts with no timeout:** Provide sensible defaults or document timeout

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Container validation | String parsing | validate_container_exists() | Already in sandbox.sh |
| Snapshot creation | Manual lxc calls | Existing snapshot pattern | Already proven in cmd_snapshot |
| Project name extraction | Regex parsing | derive_project_name() | Already in 04-migrate-project.sh |
| Source validation | Manual checks | detect_source_type() | Already in 04-migrate-project.sh |
| Exit code handling | Custom codes | Existing 0/1/2 pattern | Consistent with sandbox.sh |

**Key insight:** 04-migrate-project.sh already implements source detection, project naming, and all migration logic. The CLI integration should focus on safety (snapshots), UX (prompts), and output formatting (summary).

## Common Pitfalls

### Pitfall 1: Snapshot After Source Validation Fails
**What goes wrong:** Creating snapshot for invalid source wastes time and storage
**Why it happens:** Validating source after snapshot
**How to avoid:** Validate source type and container before creating snapshot
**Warning signs:** Orphan snapshots from failed validations
**Example:**
```bash
# BAD: Snapshot before validation
create_pre_migration_snapshot "$container"
detect_source_type "$source"  # May fail

# GOOD: Validate first
if ! detect_source_type "$source"; then
    log_error "Invalid source"
    exit 1
fi
create_pre_migration_snapshot "$container"
```

### Pitfall 2: Missing --force or --branch Pass-through
**What goes wrong:** User can't pass flags through sandbox.sh migrate
**Why it happens:** Not forwarding optional arguments to backend
**How to avoid:** Parse and forward optional flags like --branch
**Warning signs:** User has to call 04-migrate-project.sh directly
**Example:**
```bash
# Support --branch flag
# ./sandbox.sh migrate relay-dev https://github.com/... --branch main
cmd_migrate() {
    local container="${1:-}"
    local source="${2:-}"
    shift 2 || true

    # Pass remaining args (--branch etc) to backend
    "$SCRIPT_DIR/04-migrate-project.sh" "$container" "$source" "$@"
}
```

### Pitfall 3: Project Existence Check Race Condition
**What goes wrong:** Project created between check and migration
**Why it happens:** Time gap between check and actual migration
**How to avoid:** Have backend handle existence check atomically
**Warning signs:** Duplicate projects, partial overwrites
**Recommendation:** Move existence check into 04-migrate-project.sh, pass --overwrite flag

### Pitfall 4: Silent Failure on Sudo Requirement
**What goes wrong:** sandbox.sh works but 04-migrate-project.sh fails without sudo
**Why it happens:** sandbox.sh doesn't require sudo but backend does
**How to avoid:** Check for root/sudo at CLI level before delegating
**Warning signs:** "This script must be run as root" after snapshot created
**Example:**
```bash
cmd_migrate() {
    # Root check before any operations
    if [[ $EUID -ne 0 ]]; then
        log_error "migrate command requires root (or sudo)"
        echo "Usage: sudo ./sandbox.sh migrate <container> <source>"
        exit 1
    fi
    # ...
}
```

### Pitfall 5: Missing Summary on Partial Success
**What goes wrong:** Dependencies install but database fails, no summary of what worked
**Why it happens:** All-or-nothing output approach
**How to avoid:** Track progress, show partial summary on failure
**Warning signs:** User doesn't know what succeeded before failure

## Code Examples

Verified patterns from existing implementation:

### Complete cmd_migrate Function
```bash
# Source: sandbox.sh patterns + new integration
cmd_migrate() {
    local container="${1:-}"
    local source="${2:-}"

    # Validate arguments
    if [[ -z "$container" || -z "$source" ]]; then
        echo "Usage: $0 migrate <container> <source> [--branch <branch>]"
        echo ""
        echo "Examples:"
        echo "  $0 migrate relay-dev https://github.com/user/project.git"
        echo "  $0 migrate relay-dev /path/to/local/project"
        echo "  $0 migrate relay-dev https://github.com/user/repo.git --branch main"
        exit 1
    fi

    # Root check (04-migrate-project.sh requires root)
    if [[ $EUID -ne 0 ]]; then
        log_error "migrate command requires root (or sudo)"
        echo "Usage: sudo ./sandbox.sh migrate <container> <source>"
        exit 1
    fi

    # Validate container exists
    validate_container_exists "$container"

    shift 2  # Remove container and source from args

    # Create pre-migration snapshot
    local snapshot_label="pre-migrate-$(date +%Y%m%d-%H%M%S)"
    echo -e "${CYAN}Creating pre-migration snapshot: $snapshot_label${NC}"
    lxc snapshot "$container" "$snapshot_label"

    # Delegate to migration script (handles everything else)
    # Pass remaining args for --branch support
    if ! "$SCRIPT_DIR/04-migrate-project.sh" "$container" "$source" "$@"; then
        echo ""
        log_error "Migration failed"
        echo ""
        echo "To rollback to pre-migration state:"
        echo "  ./sandbox.sh restore $container $snapshot_label"
        exit 1
    fi

    # Success already printed by 04-migrate-project.sh
    echo ""
    echo "Pre-migration snapshot available: $snapshot_label"
    echo "To rollback if needed: ./sandbox.sh restore $container $snapshot_label"
}
```

### LXC Snapshot Command (Verified)
```bash
# Source: LXD documentation + existing sandbox.sh
# Create named snapshot
lxc snapshot <container> <snapshot-name>

# List snapshots
lxc info <container> | grep -A 100 "Snapshots:"

# Restore from snapshot
lxc restore <container> <snapshot-name>

# Delete snapshot
lxc delete <container>/<snapshot-name>
```

### Project Existence Check in Container
```bash
# Source: 04-migrate-project.sh patterns
# Check if directory exists inside container
lxc exec "$container" -- test -d "/root/projects/$project_name"

# Return code: 0 = exists, 1 = does not exist
if lxc exec "$container" -- test -d "/root/projects/$project_name"; then
    echo "Project already exists"
fi
```

### Source Type Detection (Already Implemented)
```bash
# Source: 04-migrate-project.sh detect_source_type()
# Git URL patterns
[[ "$source" =~ ^https?:// ]] && [[ "$source" =~ \.git$ ]]  # HTTPS with .git
[[ "$source" =~ ^git@ ]]  # SSH style
[[ "$source" =~ github\.com|gitlab\.com|bitbucket\.org ]]  # Known hosts

# Local path
[[ -d "$source" ]]  # Directory exists on host
```

### Project Name Derivation (Already Implemented)
```bash
# Source: 04-migrate-project.sh derive_project_name()
# From git URL with .git suffix
basename "$source" .git  # "project.git" -> "project"

# From git URL without .git
basename "$source"  # "github.com/user/project" -> "project"

# From local path
basename "$(cd "$source" && pwd)"  # "/path/to/myproject" -> "myproject"
```

### Updated Help Text
```bash
# Source: Existing sandbox.sh show_help() + new migrate command
show_help() {
    echo "Dev Sandbox Management"
    echo ""
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  create <name> <tailscale-key>  Create and provision new sandbox"
    echo "  migrate <name> <source>        Migrate project into sandbox"
    echo "  shell <name>                   Open bash shell in container"
    echo "  list                           List all sandboxes with status"
    echo "  snapshot <name> [label]        Create named snapshot"
    echo "  restore <name> <label>         Restore from snapshot"
    echo "  delete <name>                  Delete container"
    echo "  info <name>                    Show container details"
    echo ""
    echo "Migrate sources:"
    echo "  Git URL:  https://github.com/user/project.git"
    echo "  Git SSH:  git@github.com:user/project.git"
    echo "  Local:    /path/to/local/project"
    echo ""
    echo "Migrate options:"
    echo "  --branch <branch>  Clone specific branch or tag"
    echo ""
    echo "Examples:"
    echo "  sudo $0 migrate relay-dev https://github.com/user/project.git"
    echo "  sudo $0 migrate relay-dev /home/user/myproject --branch main"
    echo ""
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No safety snapshot | Auto pre-migration snapshot | This phase | Enables easy rollback |
| Overwrite without asking | Prompt for re-migration options | This phase | Prevents accidental data loss |
| No migration summary | Detailed summary output | This phase | Better user understanding |
| Separate migration script | Integrated CLI command | This phase | Consistent UX |

**Deprecated/outdated:**
- Calling 04-migrate-project.sh directly: Now use `sandbox.sh migrate` for safety features
- Manual snapshots before migration: Now automatic

## Open Questions

Things that couldn't be fully resolved:

1. **Re-migration handling location**
   - What we know: Can detect existing project, can prompt user
   - What's unclear: Should logic be in sandbox.sh or 04-migrate-project.sh?
   - Recommendation: Add SRC-06 check to 04-migrate-project.sh with --force flag, sandbox.sh prompts and passes flag

2. **Summary output format**
   - What we know: 04-migrate-project.sh already logs each step
   - What's unclear: Should summary be generated by sandbox.sh or 04-migrate-project.sh?
   - Recommendation: Let 04-migrate-project.sh output its current logs, sandbox.sh adds snapshot info

3. **Branch pass-through complexity**
   - What we know: --branch is optional argument after source
   - What's unclear: Any other flags needed?
   - Recommendation: Pass all remaining args "$@" to backend for future extensibility

## Sources

### Primary (HIGH confidence)
- sandbox.sh - Existing CLI patterns, cmd_* functions, validation helpers
- 04-migrate-project.sh - Migration implementation, source detection, project naming
- 02-create-container.sh - Snapshot patterns, confirmation prompts, output formatting
- LXD documentation - lxc snapshot, lxc exec test commands

### Secondary (MEDIUM confidence)
- Phase 4 RESEARCH.md - CLI design patterns, exit codes, help text formatting
- Phase 8 RESEARCH.md - Database setup patterns (for summary output)

### Tertiary (LOW confidence)
- None - all patterns verified from existing implementation

## Metadata

**Confidence breakdown:**
- CLI integration: HIGH - Extends existing sandbox.sh patterns
- Snapshot safety: HIGH - Reuses existing snapshot commands
- Re-migration detection: HIGH - Simple lxc exec test
- Output formatting: HIGH - Follows existing log_info/log_error patterns
- Summary generation: MEDIUM - New pattern but follows existing output style

**Research date:** 2026-02-01
**Valid until:** 2026-04-01 (stable domain, 60 days)

---

## Appendix: Requirements Mapping

| Requirement | Technical Approach | Verified |
|-------------|-------------------|----------|
| SRC-06: Detect if project exists and offer re-migration options | lxc exec test -d + prompt_remigration_options() | Yes |
| CLI-01: sandbox.sh migrate command accepts container and source | cmd_migrate() with argument validation | Yes |
| CLI-02: sandbox.sh migrate calls 04-migrate-project.sh backend | "$SCRIPT_DIR/04-migrate-project.sh" "$@" | Yes |
| CLI-03: Script creates pre-migration snapshot automatically | lxc snapshot pre-migrate-TIMESTAMP | Yes |
| CLI-04: Script outputs clear success/error messages | log_info/log_error + rollback hint | Yes |
| CLI-05: Script provides migration summary | Summary block showing detected tools and actions | Yes |

All Phase 9 requirements have clear technical implementations identified.

---

## Appendix: Implementation Strategy

### Recommended Approach

1. **Update sandbox.sh** with cmd_migrate() function:
   - Add root check (04-migrate-project.sh requires root)
   - Validate container exists
   - Create pre-migration snapshot
   - Delegate to 04-migrate-project.sh
   - Show rollback hint on success/failure

2. **Update 04-migrate-project.sh** for SRC-06:
   - Add check_existing_project() function
   - Check before creating /root/projects/<name>
   - If exists, log warning and exit 1 (let sandbox.sh handle prompts)
   - Add --force flag to bypass existence check (for re-migration overwrite)

3. **Update sandbox.sh help text**:
   - Add migrate command to help
   - Document source types and --branch option
   - Note sudo requirement

### Files Modified

| File | Changes |
|------|---------|
| sandbox.sh | Add cmd_migrate(), update show_help(), add to case statement |
| 04-migrate-project.sh | Add check_existing_project(), --force flag, minor summary improvements |

### Integration Testing Checklist

- [ ] `./sandbox.sh migrate` shows usage
- [ ] `sudo ./sandbox.sh migrate relay-dev https://github.com/...` creates snapshot first
- [ ] Pre-migration snapshot visible in `lxc info relay-dev`
- [ ] Migration to existing project prompts user (or fails with hint)
- [ ] `--branch` flag passes through correctly
- [ ] Failed migration shows rollback hint with snapshot name
- [ ] Success shows next steps with container and project path
