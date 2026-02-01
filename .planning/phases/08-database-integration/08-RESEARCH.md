# Phase 8: Database Integration - Research

**Researched:** 2026-02-01
**Domain:** PostgreSQL database creation, ORM migrations (Prisma, Drizzle), raw SQL migrations
**Confidence:** HIGH

## Summary

Phase 8 extends the migration script (04-migrate-project.sh) to handle database setup after Node.js dependencies are installed. The phase must create a PostgreSQL database with a sanitized project name, detect which migration tool the project uses (Prisma, Drizzle, or raw SQL), run the appropriate migration command, and ensure DATABASE_URL is configured in the .env file.

Research confirms the standard approach:
1. Sanitize project name for PostgreSQL (replace hyphens/special chars with underscores, lowercase)
2. Create database using `createdb` command with the sanitized name
3. Detect migration tool by checking for indicator files (`prisma/`, `drizzle.config.*`, `migrations/`)
4. Run the appropriate migration command (`prisma migrate deploy`, `drizzle-kit push`, or `psql -f`)
5. Generate DATABASE_URL and append to .env if not already present

**Primary recommendation:** Use simple file existence checks to detect migration tools (same pattern as package manager detection in Phase 7). Leverage PostgreSQL trust auth already configured in containers for password-less connections.

## Standard Stack

The established tools for this domain:

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| PostgreSQL | 15/16 (container) | Database server | Already provisioned in Phase 3 |
| createdb | with PostgreSQL | Database creation | Standard PostgreSQL CLI tool |
| psql | with PostgreSQL | SQL execution | Standard PostgreSQL CLI tool |
| npx prisma | project-local | Prisma migrations | Uses project's prisma version |
| npx drizzle-kit | project-local | Drizzle migrations | Uses project's drizzle-kit version |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| grep -qF | system | Check .env for existing vars | Avoid duplicate DATABASE_URL entries |
| tr | system | String sanitization | Convert project name to valid DB name |
| sort | system | Migration ordering | Alphabetical raw SQL execution |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| createdb | CREATE DATABASE SQL | createdb is simpler, handles defaults |
| prisma migrate deploy | prisma migrate dev | deploy is non-interactive, appropriate for automation |
| drizzle-kit push | drizzle-kit migrate | push is simpler for dev environments |
| psql -f per file | Combined SQL file | Per-file allows partial progress visibility |

**No additional packages needed:** All required tools are already installed from Phase 3 (PostgreSQL, psql, createdb) or are project dependencies (prisma, drizzle-kit).

## Architecture Patterns

### Recommended Script Structure
```
# Addition to 04-migrate-project.sh
setup_database() {
    |
    +-- Database Creation
    |     +-- sanitize_db_name() -> valid PostgreSQL identifier
    |     +-- create_database() -> createdb command
    |
    +-- Migration Tool Detection
    |     +-- detect_migration_tool() -> "prisma" | "drizzle" | "sql" | "none"
    |
    +-- Migration Execution
    |     +-- run_prisma_migrations()
    |     +-- run_drizzle_migrations()
    |     +-- run_sql_migrations()
    |
    +-- Environment Configuration
          +-- generate_database_url()
          +-- append_env_if_missing()
}
```

### Pattern 1: Database Name Sanitization
**What:** Convert project name to valid PostgreSQL identifier
**When to use:** Before creating database
**Example:**
```bash
# Source: PostgreSQL documentation on identifiers
# https://www.postgresql.org/docs/current/sql-syntax-lexical.html
sanitize_db_name() {
    local project_name="$1"

    # Convert to lowercase, replace hyphens and dots with underscores
    # Remove any character that's not alphanumeric or underscore
    # Ensure starts with letter or underscore (prefix 'db_' if starts with number)
    local sanitized
    sanitized=$(echo "$project_name" | tr '[:upper:]' '[:lower:]' | tr '.-' '_' | tr -cd 'a-z0-9_')

    # If starts with digit, prefix with 'db_'
    if [[ "$sanitized" =~ ^[0-9] ]]; then
        sanitized="db_${sanitized}"
    fi

    # Truncate to 63 chars (PostgreSQL limit)
    echo "${sanitized:0:63}"
}

# Examples:
# "my-project" -> "my_project"
# "Project.Name" -> "project_name"
# "123app" -> "db_123app"
```

### Pattern 2: Database Creation with Idempotency
**What:** Create PostgreSQL database if it doesn't exist
**When to use:** After name sanitization
**Example:**
```bash
# Source: PostgreSQL createdb documentation
# https://www.postgresql.org/docs/current/app-createdb.html
create_project_database() {
    local db_name="$1"

    # Check if database already exists
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'" | grep -q 1; then
        log_info "Database '$db_name' already exists"
        return 0
    fi

    # Create database owned by dev user
    sudo -u postgres createdb -O dev "$db_name"

    # Install common extensions
    sudo -u postgres psql -d "$db_name" -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto;'

    log_info "Database '$db_name' created"
}
```

### Pattern 3: Migration Tool Detection
**What:** Determine which migration tool the project uses
**When to use:** After database creation, before running migrations
**Example:**
```bash
# Detection order: Prisma > Drizzle > Raw SQL (most specific first)
detect_migration_tool() {
    local project_dir="$1"

    # Prisma: check for prisma/ directory with schema.prisma
    if [[ -d "$project_dir/prisma" ]] && [[ -f "$project_dir/prisma/schema.prisma" ]]; then
        echo "prisma"
        return 0
    fi

    # Drizzle: check for drizzle.config.* file
    if [[ -f "$project_dir/drizzle.config.ts" ]] || \
       [[ -f "$project_dir/drizzle.config.js" ]] || \
       [[ -f "$project_dir/drizzle.config.mjs" ]]; then
        echo "drizzle"
        return 0
    fi

    # Also check for drizzle/ directory (output directory)
    if [[ -d "$project_dir/drizzle" ]]; then
        echo "drizzle"
        return 0
    fi

    # Raw SQL: check for migrations/ directory with .sql files
    if [[ -d "$project_dir/migrations" ]]; then
        local sql_count
        sql_count=$(find "$project_dir/migrations" -maxdepth 1 -name "*.sql" 2>/dev/null | wc -l)
        if [[ "$sql_count" -gt 0 ]]; then
            echo "sql"
            return 0
        fi
    fi

    echo "none"
}
```

### Pattern 4: Prisma Migration Execution
**What:** Run Prisma migrations non-interactively
**When to use:** When Prisma detected
**Example:**
```bash
# Source: Prisma migrate deploy documentation
# https://www.prisma.io/docs/orm/prisma-migrate/workflows/development-and-production
run_prisma_migrations() {
    local project_dir="$1"
    local database_url="$2"

    log_info "Running Prisma migrations..."

    # Source nvm for npx access
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    cd "$project_dir"

    # prisma migrate deploy:
    # - Applies all pending migrations
    # - Creates database if it doesn't exist (but we already did)
    # - Non-interactive, suitable for automation
    # - Does NOT generate new migrations (unlike migrate dev)
    DATABASE_URL="$database_url" npx prisma migrate deploy

    log_info "Prisma migrations complete"
}
```

### Pattern 5: Drizzle Migration Execution
**What:** Push Drizzle schema to database
**When to use:** When Drizzle detected
**Example:**
```bash
# Source: Drizzle-kit push documentation
# https://orm.drizzle.team/docs/drizzle-kit-push
run_drizzle_migrations() {
    local project_dir="$1"
    local database_url="$2"

    log_info "Running Drizzle schema push..."

    # Source nvm for npx access
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    cd "$project_dir"

    # drizzle-kit push:
    # - Compares schema to database
    # - Applies changes directly (no migration files)
    # - --force auto-accepts data-loss statements (dev environment)
    DATABASE_URL="$database_url" npx drizzle-kit push --force

    log_info "Drizzle schema push complete"
}
```

### Pattern 6: Raw SQL Migration Execution
**What:** Execute .sql files in alphabetical order
**When to use:** When migrations/ directory with .sql files detected
**Example:**
```bash
# Source: PostgreSQL psql documentation
# https://www.postgresql.org/docs/current/app-psql.html
run_sql_migrations() {
    local project_dir="$1"
    local db_name="$2"

    log_info "Running raw SQL migrations..."

    local migrations_dir="$project_dir/migrations"

    # Find and sort .sql files alphabetically
    # This ensures 001_init.sql runs before 002_users.sql
    find "$migrations_dir" -maxdepth 1 -name "*.sql" -type f | sort | while read -r sql_file; do
        local filename
        filename=$(basename "$sql_file")
        log_info "Applying: $filename"

        # Run with ON_ERROR_STOP to fail fast on errors
        # -1 wraps in transaction for atomicity
        sudo -u postgres psql -d "$db_name" -v ON_ERROR_STOP=1 -1 -f "$sql_file"
    done

    log_info "SQL migrations complete"
}
```

### Pattern 7: DATABASE_URL Generation and .env Update
**What:** Generate DATABASE_URL and append to .env if missing
**When to use:** After database creation
**Example:**
```bash
# Source: PostgreSQL connection string format
# https://www.postgresql.org/docs/current/libpq-connect.html
generate_database_url() {
    local db_name="$1"

    # Format: postgresql://user:password@host:port/database
    # With trust auth (configured in Phase 3), password can be empty or 'dev'
    echo "postgresql://dev:dev@localhost:5432/${db_name}"
}

append_database_url_to_env() {
    local project_dir="$1"
    local database_url="$2"
    local env_file="$project_dir/.env"

    # Create .env if it doesn't exist
    touch "$env_file"

    # Check if DATABASE_URL already exists (avoid duplicates)
    if grep -qF 'DATABASE_URL=' "$env_file"; then
        log_info "DATABASE_URL already exists in .env, skipping"
        return 0
    fi

    # Append DATABASE_URL
    echo "" >> "$env_file"  # Ensure newline before
    echo "DATABASE_URL=\"${database_url}\"" >> "$env_file"

    log_info "DATABASE_URL appended to .env"
}
```

### Anti-Patterns to Avoid
- **Using `prisma migrate dev` in automation:** Interactive, may prompt for migration names
- **Not sanitizing database names:** Hyphens in project names cause PostgreSQL errors
- **Running migrations before npm install:** ORM packages must be installed first
- **Overwriting existing DATABASE_URL:** User may have custom configuration
- **Not handling missing migrations directory:** Some SQL projects use different locations
- **Using password auth when trust configured:** Simpler with trust, but include password for compatibility

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Database creation | SQL string concatenation | createdb CLI | Handles encoding, template, owner |
| Migration ordering | Custom sorting logic | `find | sort` | Standard UNIX pattern |
| Connection string | Manual formatting | Standard format | postgresql://user:pass@host:port/db |
| ORM detection | package.json parsing | File existence checks | Simpler, no JSON parsing needed |
| Transaction handling | Manual BEGIN/COMMIT | psql -1 flag | Built-in single transaction mode |
| Error handling in SQL | Continue on error | ON_ERROR_STOP=1 | Stops on first error, returns exit code 3 |

**Key insight:** PostgreSQL CLI tools (createdb, psql) handle complexity. ORM CLIs (prisma, drizzle-kit) handle schema diffing. Let them do their jobs.

## Common Pitfalls

### Pitfall 1: Invalid Database Names
**What goes wrong:** `createdb my-project` fails with syntax error
**Why it happens:** PostgreSQL identifiers can't contain hyphens unquoted
**How to avoid:** Sanitize project names: `my-project` -> `my_project`
**Warning signs:** "syntax error at or near" errors from createdb

### Pitfall 2: Prisma Prompting for Input
**What goes wrong:** `prisma migrate dev` hangs waiting for user input
**Why it happens:** Using `dev` instead of `deploy` in non-interactive context
**How to avoid:** Always use `prisma migrate deploy` for automation
**Warning signs:** Script hangs, no progress

### Pitfall 3: Drizzle Prompting for Data Loss
**What goes wrong:** `drizzle-kit push` prompts for confirmation on destructive changes
**Why it happens:** Default behavior asks before dropping columns/tables
**How to avoid:** Use `--force` flag for dev environments
**Warning signs:** Script hangs waiting for y/n

### Pitfall 4: SQL Migration Order
**What goes wrong:** Migrations run out of order, foreign key errors
**Why it happens:** Using unsorted file listing
**How to avoid:** Always `sort` migration files before executing
**Warning signs:** "relation does not exist" errors

### Pitfall 5: DATABASE_URL Duplication
**What goes wrong:** Multiple DATABASE_URL lines in .env
**Why it happens:** Script runs multiple times without checking
**How to avoid:** `grep -qF 'DATABASE_URL='` before appending
**Warning signs:** Confusing behavior, wrong connection used

### Pitfall 6: Prisma Not Finding Schema
**What goes wrong:** "Could not find a Prisma Schema" error
**Why it happens:** Running from wrong directory, or schema in non-standard location
**How to avoid:** `cd "$project_dir"` before running prisma commands
**Warning signs:** Error mentions schema not found

### Pitfall 7: NVM Not Loaded
**What goes wrong:** "npx: command not found"
**Why it happens:** Non-interactive shell doesn't source .bashrc
**How to avoid:** Source nvm.sh before running npx commands
**Warning signs:** "command not found" for npm/npx/node

### Pitfall 8: Database Already Exists
**What goes wrong:** createdb fails with "database already exists"
**Why it happens:** Re-running migration script
**How to avoid:** Check database existence first with pg_database query
**Warning signs:** Error on second run of script

## Code Examples

Verified patterns from official sources:

### Complete Database Setup Function (lxc exec compatible)
```bash
# Full orchestration function for use via lxc exec
container_exec '
    PROJECT_DIR="/root/projects/myproject"
    PROJECT_NAME="myproject"

    # Sanitize database name
    DB_NAME=$(echo "$PROJECT_NAME" | tr "[:upper:]" "[:lower:]" | tr ".-" "_" | tr -cd "a-z0-9_")
    [[ "$DB_NAME" =~ ^[0-9] ]] && DB_NAME="db_${DB_NAME}"
    DB_NAME="${DB_NAME:0:63}"

    echo "Database name: $DB_NAME"

    # Create database if not exists
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='"'"'$DB_NAME'"'"'" | grep -q 1; then
        sudo -u postgres createdb -O dev "$DB_NAME"
        sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
        echo "Database created: $DB_NAME"
    else
        echo "Database already exists: $DB_NAME"
    fi

    # Generate DATABASE_URL
    DATABASE_URL="postgresql://dev:dev@localhost:5432/${DB_NAME}"

    # Append to .env if not present
    if ! grep -qF "DATABASE_URL=" "$PROJECT_DIR/.env" 2>/dev/null; then
        echo "" >> "$PROJECT_DIR/.env"
        echo "DATABASE_URL=\"${DATABASE_URL}\"" >> "$PROJECT_DIR/.env"
        echo "DATABASE_URL added to .env"
    fi
'
```

### Complete Prisma Migration (lxc exec compatible)
```bash
# Source: https://www.prisma.io/docs/orm/prisma-migrate/workflows/development-and-production
container_exec '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    PROJECT_DIR="/root/projects/myproject"
    DATABASE_URL="postgresql://dev:dev@localhost:5432/myproject"

    cd "$PROJECT_DIR"

    # Check for Prisma
    if [[ -f "prisma/schema.prisma" ]]; then
        echo "Running Prisma migrations..."
        DATABASE_URL="$DATABASE_URL" npx prisma migrate deploy
        echo "Prisma migrations complete"
    fi
'
```

### Complete Drizzle Migration (lxc exec compatible)
```bash
# Source: https://orm.drizzle.team/docs/drizzle-kit-push
container_exec '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    PROJECT_DIR="/root/projects/myproject"
    DATABASE_URL="postgresql://dev:dev@localhost:5432/myproject"

    cd "$PROJECT_DIR"

    # Check for Drizzle config
    if [[ -f "drizzle.config.ts" ]] || [[ -f "drizzle.config.js" ]]; then
        echo "Running Drizzle push..."
        DATABASE_URL="$DATABASE_URL" npx drizzle-kit push --force
        echo "Drizzle push complete"
    fi
'
```

### Complete Raw SQL Migration (lxc exec compatible)
```bash
# Source: https://www.postgresql.org/docs/current/app-psql.html
container_exec '
    PROJECT_DIR="/root/projects/myproject"
    DB_NAME="myproject"
    MIGRATIONS_DIR="$PROJECT_DIR/migrations"

    if [[ -d "$MIGRATIONS_DIR" ]]; then
        SQL_COUNT=$(find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" -type f | wc -l)

        if [[ "$SQL_COUNT" -gt 0 ]]; then
            echo "Running $SQL_COUNT SQL migration(s)..."

            find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" -type f | sort | while read -r sql_file; do
                filename=$(basename "$sql_file")
                echo "Applying: $filename"
                sudo -u postgres psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -1 -f "$sql_file"
            done

            echo "SQL migrations complete"
        fi
    fi
'
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| prisma migrate dev | prisma migrate deploy | Prisma 2.x GA | Non-interactive for CI/CD |
| drizzle-kit generate + migrate | drizzle-kit push | Drizzle Kit 0.20+ | Simpler for dev envs |
| Manual pg_hba.conf editing | trust auth via provision script | Phase 3 design | Simplified auth |
| Password-based auth | Trust auth for localhost | Dev environment decision | No password needed |

**Deprecated/outdated:**
- Using `prisma migrate dev` in scripts: Prompts for migration names
- Manual database user creation per project: `dev` user handles all projects
- Storing passwords in DATABASE_URL for local dev: Trust auth makes it unnecessary (but compatible)

## Open Questions

Things that couldn't be fully resolved:

1. **Multiple schemas in one database vs separate databases**
   - What we know: Current design creates one database per project
   - What's unclear: Whether to support schema-per-project in shared database
   - Recommendation: Separate databases (current approach) for better isolation

2. **Handling migration failures**
   - What we know: ON_ERROR_STOP exits on first error
   - What's unclear: Whether to rollback partial migrations or leave state
   - Recommendation: Let psql -1 handle transaction, fail fast, user can investigate

3. **Drizzle config file with DATABASE_URL from process.env**
   - What we know: drizzle.config.ts often uses process.env.DATABASE_URL
   - What's unclear: Whether to set env var or pass via CLI
   - Recommendation: Set DATABASE_URL env var before running drizzle-kit (matches .env pattern)

4. **Nested migration directories**
   - What we know: Some projects have `db/migrations` or `src/migrations`
   - What's unclear: How deep to search for migrations directory
   - Recommendation: Check `migrations/` at project root first; document limitation

## Sources

### Primary (HIGH confidence)
- [PostgreSQL createdb documentation](https://www.postgresql.org/docs/current/app-createdb.html) - createdb syntax, options
- [PostgreSQL psql documentation](https://www.postgresql.org/docs/current/app-psql.html) - psql -f, ON_ERROR_STOP, -1 transaction
- [PostgreSQL SQL identifiers](https://www.postgresql.org/docs/current/sql-syntax-lexical.html) - Database name rules
- [Prisma migrate deploy documentation](https://www.prisma.io/docs/orm/prisma-migrate/workflows/development-and-production) - Production migrations
- [Drizzle-kit push documentation](https://orm.drizzle.team/docs/drizzle-kit-push) - drizzle-kit push command
- [Drizzle config file documentation](https://orm.drizzle.team/docs/drizzle-config-file) - drizzle.config.ts patterns

### Secondary (MEDIUM confidence)
- [Prisma schema location](https://www.prisma.io/docs/orm/prisma-schema/overview/location) - prisma/ directory structure
- [PostgreSQL connection strings](https://www.connectionstrings.com/postgresql/) - DATABASE_URL format
- [Baeldung Linux file appending](https://www.baeldung.com/linux/appending-non-existent-line-to-file) - grep -qF pattern

### Tertiary (LOW confidence)
- WebSearch results for raw SQL migration patterns in bash scripts

## Metadata

**Confidence breakdown:**
- Database creation: HIGH - Official PostgreSQL documentation, same pattern as Phase 3
- Prisma migrations: HIGH - Official Prisma documentation, well-documented deploy command
- Drizzle migrations: HIGH - Official Drizzle documentation, clear push command
- Raw SQL migrations: MEDIUM - Standard patterns, but varies by project
- .env handling: HIGH - Same pattern as Phase 7, well-established convention

**Research date:** 2026-02-01
**Valid until:** 2026-04-01 (stable domain, 60 days)

---

## Appendix: Requirements Mapping

| Requirement | Technical Approach | Verified |
|-------------|-------------------|----------|
| DB-01: Create PostgreSQL database with sanitized project name | sanitize_db_name() + createdb | Yes |
| DB-02: Detect Prisma by presence of prisma/ directory | test -d prisma && test -f prisma/schema.prisma | Yes |
| DB-03: Detect Drizzle by presence of drizzle/ or drizzle.config.* | test -f drizzle.config.{ts,js,mjs} or test -d drizzle | Yes |
| DB-04: Run prisma migrate deploy for Prisma projects | DATABASE_URL=... npx prisma migrate deploy | Yes |
| DB-05: Run drizzle-kit push for Drizzle projects | DATABASE_URL=... npx drizzle-kit push --force | Yes |
| DB-06: Detect raw SQL migrations in migrations/ directory | test -d migrations && find *.sql | Yes |
| DB-07: Run raw SQL migrations in alphabetical order | find | sort | psql -f | Yes |
| ENV-03: Generate DATABASE_URL for PostgreSQL connection | postgresql://dev:dev@localhost:5432/$db_name | Yes |
| ENV-04: Append DATABASE_URL to .env if not present | grep -qF + echo >> | Yes |

All Phase 8 requirements have clear technical implementations identified.

---

## Appendix: Integration with 04-migrate-project.sh

### Execution Order
The database setup should run AFTER Node.js dependency installation (Phase 7) because:
1. `prisma` and `drizzle-kit` are project dependencies, installed via npm/pnpm/yarn
2. `npx` runs the locally-installed versions for compatibility

### Proposed Addition to Script Flow
```bash
# Current flow (Phases 6-7):
# transfer_project()
#   +-- clone_git_repository() or copy_local_directory()
#   +-- setup_nodejs_dependencies()
#       +-- copy_env_example_if_needed()
#       +-- detect_package_manager()
#       +-- setup_node_version()
#       +-- install_dependencies()

# New flow (Phase 8):
# transfer_project()
#   +-- ... existing ...
#   +-- setup_database()           # NEW
#       +-- create_project_database()
#       +-- append_database_url()
#       +-- run_migrations()
#           +-- detect_migration_tool()
#           +-- run_prisma/drizzle/sql_migrations()
```

### Host vs Container Execution
- **Database creation**: Runs inside container (where PostgreSQL is installed)
- **Migration detection**: Runs inside container (files are in container)
- **Migration execution**: Runs inside container (ORM CLIs need project dependencies)
- **All PostgreSQL commands**: Use `sudo -u postgres` inside container

### Exit on Failure
Database/migration errors should cause script to fail (consistent with Phase 7 behavior):
```bash
if ! create_project_database "$db_name"; then
    log_error "Failed to create database"
    exit 1
fi
```
