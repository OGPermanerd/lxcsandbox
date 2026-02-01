# Architecture: Project Migration Integration

**Domain:** Node.js project migration into LXC sandboxes
**Researched:** 2026-02-01
**Confidence:** HIGH (based on codebase analysis)

## Current Script Architecture

```
sandbox.sh (CLI wrapper)
    │
    ├── create <name> <ts-key>
    │       ├─→ 02-create-container.sh <name>    [Container creation]
    │       └─→ 03-provision-container.sh <name> [Dev stack install]
    │
    ├── shell <name>         ─→ lxc exec <name> -- bash -l
    ├── list                 ─→ lxc list
    ├── snapshot <name>      ─→ lxc snapshot
    ├── restore <name>       ─→ lxc restore
    ├── delete <name>        ─→ lxc delete
    └── info <name>          ─→ lxc info + tailscale ip
```

**Key pattern:** `sandbox.sh` is a thin dispatcher; heavy lifting done by numbered scripts.

## Proposed Integration: migrate Command

```
sandbox.sh migrate <name> <source> [options]
    │
    └─→ 04-migrate-project.sh <name> <source>
            │
            ├── validate_container_running()
            ├── resolve_source()          # local path or git URL
            ├── analyze_project()         # detect stack, migrations
            ├── transfer_files()          # rsync or git clone
            ├── detect_node_version()     # .nvmrc or engines
            ├── install_dependencies()    # npm/yarn/pnpm
            ├── setup_database()          # create DB, run migrations
            └── configure_environment()   # .env updates
```

## Execution Flow Diagram

```
User Machine                Host VPS                     LXC Container
     │                          │                              │
     │ ssh/tailscale            │                              │
     │ ─────────────────────────│                              │
     │                          │                              │
     │                  sandbox.sh migrate                     │
     │                     relay-dev                           │
     │                   /path/to/project                      │
     │                          │                              │
     │                          │ validate container exists    │
     │                          │ and is running               │
     │                          │ ◄────────────────────────────│
     │                          │                              │
     │                          │ resolve source type          │
     │                          │ (local path vs git URL)      │
     │                          │                              │
     │                          │ analyze project structure    │
     │                          │ on HOST before transfer      │
     │                          │                              │
     │                          │ rsync files to container ────│
     │                          │ or lxc file push             │
     │                          │                              │
     │                          │ lxc exec: detect node ver ───│
     │                          │                              │
     │                          │ lxc exec: npm install ───────│
     │                          │                              │
     │                          │ lxc exec: setup database ────│
     │                          │                              │
     │                          │ lxc exec: run migrations ────│
     │                          │                              │
     │                          │ display summary              │
     │                          │                              │
```

## Data Flow: Files

**Path transformation during migration:**

```
SOURCE (local or git)          HOST (staging)              CONTAINER (destination)
       │                            │                              │
       │                            │                              │
  /home/user/                       │                              │
    my-project/         [if git URL: clone to temp]                │
       │                            │                              │
       │    rsync -avz              │    lxc file push             │
       │ ──────────────────────────>│ ─────────────────────────────│
       │    (if local)              │    or                        │
       │                            │    lxc exec rsync            │
       │                            │                              │
       │                            │                       /root/project/
       │                            │                          my-project/
       │                            │                              │
```

**Recommended approach:** Use `lxc file push` for directories, which handles the transfer atomically:

```bash
# For local path
lxc file push -r /source/path container/root/project/

# For git URL (clone inside container)
lxc exec container -- git clone <url> /root/project/<name>
```

## Data Flow: Environment Variables

**.env file handling:**

```
SOURCE .env                    CONTAINER .env
───────────                    ──────────────
DATABASE_URL=postgres://       DATABASE_URL=postgres://
  localhost:5432/mydb    ───>    localhost:5432/dev
                                 (or preserve original)

NODE_ENV=development     ───>  NODE_ENV=development
                                 (preserve)

CLERK_SECRET=sk_test_xxx ───>  CLERK_SECRET=sk_test_xxx
                                 (preserve secrets!)
```

**Strategy:**
1. Copy .env verbatim initially
2. Optionally update DATABASE_URL to container's dev/dev/dev
3. Never prompt for secrets - preserve what's there

## Component Boundaries

| Component | Location | Responsibility |
|-----------|----------|----------------|
| `sandbox.sh` | Host | CLI dispatcher, argument parsing |
| `04-migrate-project.sh` | Host | Orchestrates migration phases |
| Project analyzer | Host | Detect stack before transfer |
| File transfer | Host→Container | rsync or lxc file push |
| Dependency installer | Container | npm/yarn/pnpm install |
| DB setup | Container | Create DB, run migrations |
| Env configurator | Container | Update .env if needed |

## Function Structure for 04-migrate-project.sh

```bash
#!/bin/bash
# 04-migrate-project.sh

# ─────────────────────────────────────────────────
# SHARED INFRASTRUCTURE (from existing scripts)
# ─────────────────────────────────────────────────

# Colors and logging (copy from 02/03)
log_info() { ... }
log_warn() { ... }
log_error() { ... }

# Container exec helper (from 03)
container_exec() { lxc exec "$CONTAINER_NAME" -- bash -c "$1"; }

# ─────────────────────────────────────────────────
# SOURCE RESOLUTION
# ─────────────────────────────────────────────────

resolve_source_type() {
    # Returns: "local" | "git"
    # Validates path exists or URL is reachable
}

clone_git_repo() {
    # Clone inside container to avoid host git dependency
    # Handle branch/tag selection
}

validate_local_path() {
    # Check path exists and is a directory
    # Check read permissions
}

# ─────────────────────────────────────────────────
# PROJECT ANALYSIS (runs on HOST or early in container)
# ─────────────────────────────────────────────────

analyze_project() {
    # Detect: package.json, .nvmrc, prisma/, migrations/
    # Returns structured analysis result
}

detect_package_manager() {
    # Check lockfiles: package-lock.json, yarn.lock, pnpm-lock.yaml
}

detect_migration_tool() {
    # Check: prisma/, drizzle/, migrations/*.sql
}

detect_node_version() {
    # Check: .nvmrc, .node-version, package.json engines
}

# ─────────────────────────────────────────────────
# FILE TRANSFER
# ─────────────────────────────────────────────────

transfer_files() {
    # For local: lxc file push -r
    # For git: already cloned in container
}

# ─────────────────────────────────────────────────
# CONTAINER SETUP (via lxc exec)
# ─────────────────────────────────────────────────

switch_node_version() {
    # If .nvmrc detected, run: nvm install && nvm use
}

install_dependencies() {
    # npm install / yarn install / pnpm install
    # Based on detected package manager
}

setup_database() {
    # Create database for project
    # Update DATABASE_URL in .env
}

run_migrations() {
    # npx prisma migrate deploy
    # or npx drizzle-kit push
    # or psql < migrations/*.sql
}

configure_environment() {
    # Copy .env, optionally update paths
}

# ─────────────────────────────────────────────────
# MAIN FLOW
# ─────────────────────────────────────────────────

main() {
    validate_args
    validate_container_exists
    validate_container_running

    resolve_source_type

    if [[ $SOURCE_TYPE == "git" ]]; then
        clone_git_repo
    else
        transfer_files
    fi

    analyze_project  # in container after transfer
    switch_node_version
    install_dependencies
    setup_database
    run_migrations
    configure_environment

    print_summary
}
```

## Integration with sandbox.sh

Add to `sandbox.sh`:

```bash
cmd_migrate() {
    local name="${1:-}"
    local source="${2:-}"

    if [[ -z "$name" || -z "$source" ]]; then
        echo "Usage: $0 migrate <container-name> <source-path-or-git-url>"
        echo ""
        echo "Examples:"
        echo "  $0 migrate relay-dev /home/user/my-project"
        echo "  $0 migrate relay-dev https://github.com/user/repo.git"
        exit 1
    fi

    validate_container_exists "$name"

    "$SCRIPT_DIR/04-migrate-project.sh" "$name" "$source"
}

# In case statement:
case "$COMMAND" in
    # ... existing commands ...
    migrate)
        cmd_migrate "$@"
        ;;
```

## Error Handling Strategy

**Fail-fast with clear recovery:**

```bash
# Trap for clean error messages
trap 'log_error "Migration failed at line $LINENO. Container state may be partial."' ERR

# Each phase validates preconditions
validate_container_running() {
    local status
    status=$(lxc info "$CONTAINER_NAME" | grep 'Status:' | awk '{print $2}')
    if [[ "$status" != "RUNNING" ]]; then
        log_error "Container '$CONTAINER_NAME' is not running (status: $status)"
        echo ""
        echo "Start it with:"
        echo "  lxc start $CONTAINER_NAME"
        exit 1
    fi
}

# Suggest snapshot before migration
suggest_snapshot() {
    echo ""
    log_warn "Migration modifies container state."
    read -p "Create snapshot before proceeding? [Y/n]: " create_snap
    if [[ ! "$create_snap" =~ ^[Nn]$ ]]; then
        local snap_name="pre-migrate-$(date +%Y%m%d-%H%M%S)"
        lxc snapshot "$CONTAINER_NAME" "$snap_name"
        log_info "Snapshot created: $snap_name"
        log_info "Restore with: sandbox.sh restore $CONTAINER_NAME $snap_name"
    fi
}
```

**Recovery paths:**

| Failure Point | Recovery Action |
|---------------|-----------------|
| File transfer fails | Re-run migrate (idempotent transfer) |
| npm install fails | Fix package.json, re-run migrate |
| Migration fails | Fix migration, run manually in container |
| DB creation fails | Check PostgreSQL, run setup_database manually |

## Build Order Recommendation

**Phase 1: Core Transfer**
1. Source resolution (local vs git)
2. Container validation
3. File transfer mechanism
4. Basic error handling

**Phase 2: Node.js Setup**
1. Project analysis (package.json detection)
2. Package manager detection
3. Node version detection/switching
4. Dependency installation

**Phase 3: Database Integration**
1. Migration tool detection
2. Database creation
3. Migration execution
4. .env configuration

**Phase 4: Polish**
1. Snapshot suggestion
2. Summary output
3. sandbox.sh integration
4. Help text and documentation

## Dependencies Between Components

```
                    ┌──────────────────┐
                    │ Source Resolution │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌────────────┐ ┌────────────┐ ┌────────────┐
       │ Local Path │ │  Git Clone │ │ Validation │
       │  Transfer  │ │ (in cont.) │ │   Checks   │
       └─────┬──────┘ └─────┬──────┘ └────────────┘
             │              │
             └──────┬───────┘
                    ▼
           ┌───────────────┐
           │ Project       │
           │ Analysis      │ (detect package manager, migrations)
           └───────┬───────┘
                   │
        ┌──────────┼──────────┐
        ▼          ▼          ▼
   ┌─────────┐ ┌─────────┐ ┌─────────┐
   │ Node    │ │ Deps    │ │ .env    │
   │ Version │ │ Install │ │ Setup   │
   └────┬────┘ └────┬────┘ └────┬────┘
        │          │          │
        └──────────┼──────────┘
                   ▼
           ┌───────────────┐
           │ Database      │
           │ Setup         │ (requires deps for ORM tools)
           └───────┬───────┘
                   │
                   ▼
           ┌───────────────┐
           │ Run           │
           │ Migrations    │
           └───────────────┘
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Prompting for Secrets
**Bad:** "Enter your CLERK_SECRET_KEY:"
**Why:** Breaks non-interactive use, security risk
**Instead:** Copy .env verbatim, let user update manually

### Anti-Pattern 2: Modifying Source Directory
**Bad:** Writing analysis results to source project
**Why:** Unexpected side effects, permission issues
**Instead:** All analysis stored in memory or container

### Anti-Pattern 3: Assuming Package Manager
**Bad:** Always running `npm install`
**Why:** Breaks yarn/pnpm projects, wrong lockfile
**Instead:** Detect from lockfile, use detected manager

### Anti-Pattern 4: Running Migrations Without DB
**Bad:** Running `prisma migrate deploy` before creating database
**Why:** Migration will fail
**Instead:** Create database first, then run migrations

### Anti-Pattern 5: Destroying Existing Project
**Bad:** `rm -rf /root/project/*` before transfer
**Why:** Loses any container-side customizations
**Instead:** Suggest snapshot, use rsync with --delete flag (preserves intentional deletions)

## Scalability Considerations

| Concern | Current Approach | Future Enhancement |
|---------|-----------------|-------------------|
| Large projects | lxc file push (single transfer) | rsync with compression |
| Slow npm install | Fresh install each time | npm cache preservation |
| Multiple projects | One project per container | Multiple projects (not recommended) |
| Repeated migrations | Full reinstall | Incremental update mode |

## Sources

- Codebase analysis: `/home/claude/projects/lxcsandbox/*.sh`
- Project documentation: `/home/claude/projects/lxcsandbox/CLAUDE.md`
- Planning context: `/home/claude/projects/lxcsandbox/.planning/PROJECT.md`

---

**Confidence:** HIGH - Based on direct codebase analysis of existing scripts and established patterns.
