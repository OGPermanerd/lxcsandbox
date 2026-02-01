# Technology Stack for Project Migration

**Project:** Dev Sandbox Infrastructure - v1.1 Migration Milestone
**Researched:** 2026-02-01
**Scope:** Tools and patterns for migrating Node.js projects into LXC containers

## Recommended Stack

### Prerequisite: Container Base Tools

These are already installed in containers (per `02-create-container.sh` and `03-provision-container.sh`):

| Tool | Source | Purpose |
|------|--------|---------|
| git | apt (02-create-container.sh line 273) | Repository cloning |
| curl | apt (02-create-container.sh line 272) | HTTP requests |
| nvm | install script (03-provision-container.sh) | Node version management |
| jq | **MISSING - needs adding** | JSON parsing for package.json |

**Action Required:** Add `jq` to `02-create-container.sh` basic packages:
```bash
apt-get install -y -qq jq
```

### Detection Tools (Host-Side Analysis)

These patterns run on the host to analyze project before copying into container.

| Tool | Version | Purpose | Why |
|------|---------|---------|-----|
| jq | latest apt | Parse package.json for engines, dependencies | Pure bash alternative is fragile with nested JSON |
| bash 5.x | system | Script execution, regex matching | Already available on Ubuntu 22.04/24.04 |
| grep/sed | system | Pattern extraction from config files | Simple text matching for .env, .nvmrc |

## Detection Patterns

### 1. Node.js Version Detection

**Priority order:** `.nvmrc` > `package.json engines.node` > fallback to container default (22)

```bash
# Detect Node.js version from project
detect_node_version() {
    local project_dir="$1"
    local version=""

    # Priority 1: .nvmrc (exact version, most explicit)
    if [[ -f "$project_dir/.nvmrc" ]]; then
        version=$(cat "$project_dir/.nvmrc" | tr -d '[:space:]')
        # Handle common .nvmrc formats:
        # "18" -> 18
        # "v18.17.0" -> 18.17.0
        # "lts/*" -> lts (nvm understands this)
        # "node" -> node (latest)
        version="${version#v}"  # Remove leading 'v' if present
        echo "$version"
        return 0
    fi

    # Priority 2: package.json engines.node
    if [[ -f "$project_dir/package.json" ]]; then
        # Use jq to extract engines.node, handle missing field gracefully
        version=$(jq -r '.engines.node // empty' "$project_dir/package.json" 2>/dev/null)
        if [[ -n "$version" ]]; then
            # Parse semver range to get minimum viable version
            # Examples: ">=18.0.0" -> 18, "^20.0.0" -> 20, "18.x" -> 18
            version=$(echo "$version" | grep -oE '[0-9]+' | head -1)
            if [[ -n "$version" ]]; then
                echo "$version"
                return 0
            fi
        fi
    fi

    # Priority 3: Fallback to container default
    echo "22"
    return 0
}
```

**Handling variations:**

| .nvmrc Value | Interpretation | nvm command |
|--------------|----------------|-------------|
| `18` | Major version 18.x latest | `nvm install 18` |
| `18.17.0` | Exact version | `nvm install 18.17.0` |
| `v20.10.0` | Exact with v prefix | `nvm install 20.10.0` |
| `lts/*` | Latest LTS | `nvm install --lts` |
| `node` | Latest current | `nvm install node` |

| engines.node Value | Parsed To | Rationale |
|-------------------|-----------|-----------|
| `>=18.0.0` | 18 | Use minimum satisfying version |
| `^20.0.0` | 20 | Caret means 20.x compatible |
| `18.x` | 18 | Major version only |
| `>=18 <22` | 18 | Use lower bound |

### 2. Database Migration Tool Detection

**Detection order:** Check package.json dependencies, then look for config files.

```bash
# Detect which migration tool is used
detect_migration_tool() {
    local project_dir="$1"

    if [[ ! -f "$project_dir/package.json" ]]; then
        echo "none"
        return 0
    fi

    # Check dependencies and devDependencies combined
    local deps
    deps=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' "$project_dir/package.json" 2>/dev/null)

    # Priority order: Prisma > Drizzle > TypeORM > Sequelize > Knex > raw SQL
    if echo "$deps" | grep -qx "prisma"; then
        echo "prisma"
        return 0
    fi

    if echo "$deps" | grep -qx "drizzle-kit"; then
        echo "drizzle"
        return 0
    fi

    if echo "$deps" | grep -qx "typeorm"; then
        echo "typeorm"
        return 0
    fi

    if echo "$deps" | grep -qx "sequelize"; then
        echo "sequelize"
        return 0
    fi

    if echo "$deps" | grep -qx "knex"; then
        echo "knex"
        return 0
    fi

    # Check for raw SQL migrations directory
    if [[ -d "$project_dir/migrations" ]] || [[ -d "$project_dir/sql" ]]; then
        # Look for .sql files
        if find "$project_dir/migrations" "$project_dir/sql" -name "*.sql" 2>/dev/null | grep -q .; then
            echo "raw-sql"
            return 0
        fi
    fi

    echo "none"
    return 0
}
```

**Schema/config file locations by tool:**

| Tool | Schema File | Config File | Migrations Directory |
|------|-------------|-------------|---------------------|
| Prisma | `prisma/schema.prisma` | `prisma/schema.prisma` (combined) | `prisma/migrations/` |
| Drizzle | `src/db/schema/*.ts` or per config | `drizzle.config.ts` | `drizzle/` or per config |
| TypeORM | Entity files in `src/entity/` | `ormconfig.json`, `data-source.ts` | `src/migrations/` |
| Sequelize | `models/*.js` | `config/config.json`, `.sequelizerc` | `migrations/` |
| Knex | N/A (query builder) | `knexfile.js` | `migrations/` |

### 3. Migration Execution Commands

```bash
# Run migrations based on detected tool
run_migrations() {
    local tool="$1"
    local project_dir="$2"

    case "$tool" in
        prisma)
            # Prisma: Generate client + deploy migrations
            # Uses npx to ensure correct version from package.json
            echo "Running Prisma migrations..."
            lxc exec "$CONTAINER" -- bash -c "
                cd '$project_dir'
                export NVM_DIR=\"\$HOME/.nvm\"
                [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
                npx prisma generate
                npx prisma migrate deploy
            "
            ;;

        drizzle)
            # Drizzle: Check for migration files, use push or migrate
            echo "Running Drizzle migrations..."
            lxc exec "$CONTAINER" -- bash -c "
                cd '$project_dir'
                export NVM_DIR=\"\$HOME/.nvm\"
                [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
                # Prefer migrate if migrations exist, else push
                if [[ -d 'drizzle' ]] && ls drizzle/*.sql 2>/dev/null | grep -q .; then
                    npx drizzle-kit migrate
                else
                    npx drizzle-kit push
                fi
            "
            ;;

        typeorm)
            # TypeORM: Run migrations (requires compiled JS or ts-node)
            echo "Running TypeORM migrations..."
            lxc exec "$CONTAINER" -- bash -c "
                cd '$project_dir'
                export NVM_DIR=\"\$HOME/.nvm\"
                [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
                # Try ts-node first, fallback to compiled
                if [[ -f 'src/data-source.ts' ]]; then
                    npx typeorm-ts-node-esm migration:run -d ./src/data-source.ts
                else
                    npx typeorm migration:run -d ./dist/data-source.js
                fi
            "
            ;;

        sequelize)
            # Sequelize: Use sequelize-cli
            echo "Running Sequelize migrations..."
            lxc exec "$CONTAINER" -- bash -c "
                cd '$project_dir'
                export NVM_DIR=\"\$HOME/.nvm\"
                [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
                npx sequelize-cli db:migrate
            "
            ;;

        knex)
            # Knex: Use knex CLI
            echo "Running Knex migrations..."
            lxc exec "$CONTAINER" -- bash -c "
                cd '$project_dir'
                export NVM_DIR=\"\$HOME/.nvm\"
                [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
                npx knex migrate:latest
            "
            ;;

        raw-sql)
            # Raw SQL: Execute .sql files in order
            echo "Running raw SQL migrations..."
            lxc exec "$CONTAINER" -- bash -c "
                cd '$project_dir'
                for sql_file in migrations/*.sql sql/*.sql; do
                    [[ -f \"\$sql_file\" ]] || continue
                    echo \"Applying: \$sql_file\"
                    psql -U dev -d dev -f \"\$sql_file\"
                done
            "
            ;;

        none)
            echo "No migration tool detected, skipping migrations"
            ;;
    esac
}
```

### 4. Environment File Parsing and Transformation

```bash
# Parse and transform .env for container context
transform_env_file() {
    local source_env="$1"
    local dest_env="$2"
    local container_ip="$3"  # Tailscale IP

    if [[ ! -f "$source_env" ]]; then
        echo "No .env file found"
        return 0
    fi

    # Copy original, then apply transformations
    cp "$source_env" "$dest_env"

    # Transform localhost references to container IP (optional, usually not needed)
    # Most apps work fine with localhost inside container

    # Transform DATABASE_URL to use container's PostgreSQL
    # Pattern: postgresql://user:pass@host:port/db
    if grep -q "^DATABASE_URL=" "$dest_env"; then
        # Preserve original as comment
        sed -i 's/^DATABASE_URL=/# ORIGINAL_DATABASE_URL=/' "$dest_env"
        # Add container DATABASE_URL
        echo "DATABASE_URL=postgresql://dev:dev@localhost:5432/dev" >> "$dest_env"
    fi

    # Common patterns to handle:
    # - PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE
    # - Already handled by container shell config

    # Warn about external services that may need updating
    local external_warnings=()
    if grep -qE "^(CLERK_|CONVEX_|STRIPE_|AUTH0_)" "$dest_env"; then
        echo "WARNING: Found external service keys. Verify they work in new environment."
    fi
}

# Preserve secrets - copy .env as-is
copy_env_preserving_secrets() {
    local project_dir="$1"
    local container="$2"
    local container_project_dir="$3"

    for env_file in "$project_dir/.env" "$project_dir/.env.local"; do
        if [[ -f "$env_file" ]]; then
            local basename=$(basename "$env_file")
            echo "Copying $basename to container..."
            lxc file push "$env_file" "$container/$container_project_dir/$basename"
        fi
    done

    # Copy .env.example for reference if exists
    if [[ -f "$project_dir/.env.example" ]]; then
        lxc file push "$project_dir/.env.example" "$container/$container_project_dir/.env.example"
    fi
}
```

### 5. Git Clone Strategies

**Recommendation:** Full clone for development, shallow clone only for CI/build.

```bash
# Clone repository into container
clone_repository() {
    local repo_url="$1"
    local container="$2"
    local dest_dir="$3"
    local strategy="${4:-full}"  # full, shallow, blobless

    case "$strategy" in
        shallow)
            # Fast but limited: no history, can't push easily
            # Use only for read-only/build scenarios
            echo "Shallow cloning (depth=1)..."
            lxc exec "$container" -- bash -c "
                git clone --depth=1 '$repo_url' '$dest_dir'
            "
            ;;

        blobless)
            # Good balance: full history, blobs fetched on demand
            # Recommended for large repos with big files
            echo "Blobless cloning (filter=blob:none)..."
            lxc exec "$container" -- bash -c "
                git clone --filter=blob:none '$repo_url' '$dest_dir'
            "
            ;;

        full|*)
            # Default: full clone with all history
            # Best for development - all git operations work
            echo "Full cloning..."
            lxc exec "$container" -- bash -c "
                git clone '$repo_url' '$dest_dir'
            "
            ;;
    esac
}

# Detect if source is git URL or local path
detect_source_type() {
    local source="$1"

    # Git URL patterns
    if [[ "$source" =~ ^https?:// ]] || \
       [[ "$source" =~ ^git@ ]] || \
       [[ "$source" =~ ^ssh:// ]] || \
       [[ "$source" =~ ^git:// ]]; then
        echo "git"
        return 0
    fi

    # Local directory
    if [[ -d "$source" ]]; then
        echo "local"
        return 0
    fi

    # GitHub shorthand: owner/repo
    if [[ "$source" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
        echo "github-shorthand"
        return 0
    fi

    echo "unknown"
    return 1
}

# Expand GitHub shorthand to full URL
expand_github_shorthand() {
    local shorthand="$1"
    echo "https://github.com/$shorthand.git"
}
```

**Clone strategy comparison:**

| Strategy | Speed | Disk | Git Operations | Use Case |
|----------|-------|------|----------------|----------|
| `full` | Slowest | Full | All work | Development (recommended) |
| `blobless` | Medium | Reduced | Most work | Large repos with big assets |
| `shallow` | Fastest | Minimal | Limited (no history) | CI builds, read-only |

### 6. Local Directory Copy

```bash
# Copy local project into container
copy_local_project() {
    local source_dir="$1"
    local container="$2"
    local dest_dir="$3"

    echo "Copying project files to container..."

    # Normalize source path (remove trailing slash)
    source_dir="${source_dir%/}"

    # Create destination directory
    lxc exec "$container" -- mkdir -p "$dest_dir"

    # Use lxc file push with recursive flag
    # --recursive copies directory contents
    lxc file push -r "$source_dir/." "$container/$dest_dir/"

    # Alternative: tar + lxc exec for better handling of special files
    # (Uncomment if lxc file push has issues with symlinks or permissions)
    # tar -C "$source_dir" -cf - . | lxc exec "$container" -- tar -C "$dest_dir" -xf -

    echo "Project copied to $container:$dest_dir"
}

# Exclude common non-essential directories
copy_local_project_filtered() {
    local source_dir="$1"
    local container="$2"
    local dest_dir="$3"

    echo "Copying project files (excluding node_modules, .git)..."

    lxc exec "$container" -- mkdir -p "$dest_dir"

    # Use tar with excludes for better control
    tar -C "$source_dir" \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='.next' \
        --exclude='.nuxt' \
        -cf - . | lxc exec "$container" -- tar -C "$dest_dir" -xf -

    echo "Project copied (node_modules excluded, will npm install fresh)"
}
```

## Package Manager Detection

```bash
# Detect package manager from lockfile
detect_package_manager() {
    local project_dir="$1"

    # Check for lockfiles in priority order
    if [[ -f "$project_dir/pnpm-lock.yaml" ]]; then
        echo "pnpm"
    elif [[ -f "$project_dir/yarn.lock" ]]; then
        echo "yarn"
    elif [[ -f "$project_dir/package-lock.json" ]]; then
        echo "npm"
    elif [[ -f "$project_dir/bun.lockb" ]]; then
        echo "bun"
        # Note: bun not installed in containers, would need to add
    else
        # Default to npm if no lockfile
        echo "npm"
    fi
}

# Install dependencies with detected package manager
install_dependencies() {
    local container="$1"
    local project_dir="$2"
    local pkg_manager="$3"

    echo "Installing dependencies with $pkg_manager..."

    lxc exec "$container" -- bash -c "
        cd '$project_dir'
        export NVM_DIR=\"\$HOME/.nvm\"
        [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"

        case '$pkg_manager' in
            pnpm)
                pnpm install --frozen-lockfile || pnpm install
                ;;
            yarn)
                yarn install --frozen-lockfile || yarn install
                ;;
            npm|*)
                npm ci || npm install
                ;;
        esac
    "
}
```

## Integration with Existing Scripts

### Pattern: container_exec Helper

Reuse the existing pattern from `03-provision-container.sh`:

```bash
# Execute command inside the container (existing pattern)
container_exec() {
    lxc exec "$CONTAINER_NAME" -- bash -c "$1"
}

# With nvm sourced (common pattern for Node.js operations)
container_exec_node() {
    lxc exec "$CONTAINER_NAME" -- bash -c '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        '"$1"
}
```

### Pattern: Error Handling

Match existing script patterns:

```bash
set -euo pipefail
trap 'log_error "Script failed at line $LINENO"' ERR

# Colors (match existing)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
```

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| JSON parsing | jq | Node.js -e | jq is lighter, doesn't need Node.js loaded |
| JSON parsing | jq | bash regex | Fragile with nested JSON, escaping issues |
| Git clone | Full clone | Shallow | Shallow breaks common git operations |
| File copy | lxc file push | scp | lxc file push is native, no SSH needed |
| File copy | tar pipe | lxc file push -r | tar handles symlinks/permissions better |

## Missing Dependencies to Add

Update `02-create-container.sh` basic packages:

```bash
# Current (line 268-274):
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates \
    curl \
    git \
    openssh-server \
    sudo

# Should become:
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-server \
    sudo
```

## Sources

### Official Documentation
- [npm package.json engines field](https://docs.npmjs.com/files/package.json/)
- [Prisma Migrate Deploy](https://www.prisma.io/docs/orm/prisma-client/deployment/deploy-database-changes-with-prisma-migrate)
- [Drizzle Kit Push vs Migrate](https://orm.drizzle.team/docs/drizzle-kit-push)
- [Sequelize CLI Migrations](https://sequelize.org/docs/v6/other-topics/migrations/)
- [TypeORM CLI Migrations](https://typeorm.io/docs/migrations/executing/)
- [Git Clone Documentation](https://git-scm.com/docs/git-clone)

### Community Resources
- [Git shallow clone performance study](https://github.blog/open-source/git/get-up-to-speed-with-partial-clone-and-shallow-clone/)
- [jq usage with package.json](https://gist.github.com/DarrenN/8c6a5b969481725a4413)
- [pnpm package.json documentation](https://pnpm.io/package_json)

---

*Stack research for v1.1 migration milestone: 2026-02-01*
