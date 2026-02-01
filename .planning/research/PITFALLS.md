# Domain Pitfalls: Node.js Project Migration to LXC Containers

**Domain:** Node.js project migration into LXC sandboxes
**Researched:** 2026-02-01
**Confidence:** HIGH (multiple authoritative sources)

## Critical Pitfalls

Mistakes that cause migration failures or require restarts.

---

### Pitfall 1: localhost in DATABASE_URL

**What goes wrong:** Source project has `DATABASE_URL=postgres://user:pass@localhost:5432/mydb` in `.env`. After copying to container, the app tries to connect to the container's localhost, but PostgreSQL is also running on the container's localhost. This works — until you try to run the app from the host or from a different container, where "localhost" means something different.

**Why it happens:** Developers use localhost for local development, which is fine. But in container contexts, "localhost" is container-local, not network-accessible.

**Consequences:**
- App runs in container but can't be debugged from host
- Cross-container connections fail silently
- Confusion when same .env works locally but not after migration

**Warning signs:**
- `.env` contains `localhost` or `127.0.0.1` in any URL
- Connection errors mentioning "connection refused" at localhost
- App works inside container but not via Tailscale IP

**Prevention:**
```bash
# Detect localhost references during analysis
if grep -q 'localhost\|127\.0\.0\.1' "$PROJECT_DIR/.env" 2>/dev/null; then
    log_warn "Found localhost references in .env"
    log_warn "Consider updating to container's Tailscale IP or hostname"
fi
```

**After copying .env, offer to update:**
```bash
# Replace localhost with container IP for DATABASE_URL
CONTAINER_IP=$(lxc exec "$CONTAINER" -- tailscale ip -4)
sed -i "s|localhost:5432|$CONTAINER_IP:5432|g" /root/project/.env
```

**Recovery:** Edit `.env` in container to use the Tailscale IP or container hostname.

**Sources:**
- [Prisma Discussion #20794](https://github.com/prisma/prisma/discussions/20794) - Can't reach database at localhost
- [Semaphore Docker Tutorial](https://semaphore.io/community/tutorials/dockerizing-a-node-js-web-application)

---

### Pitfall 2: Node.js Version Mismatch

**What goes wrong:** Project requires Node.js 18, container has Node.js 22. Native modules compiled for Node 18 won't load on Node 22. ABI (Application Binary Interface) version mismatch causes crashes.

**Why it happens:** Node.js native modules (bcrypt, sharp, sqlite3, etc.) compile to binary `.node` files tied to a specific Node.js ABI version. Changing Node versions breaks binary compatibility.

**Consequences:**
- Immediate crash: `Error: Module was compiled against a different Node.js version`
- Subtle bugs: Different JavaScript engine behavior between versions
- `npm install` succeeds but runtime fails

**Warning signs:**
- Error messages containing "NODE_MODULE_VERSION" or "ABI"
- Project has `.nvmrc` or `.node-version` file
- `package.json` has `engines.node` field
- Dependencies include bcrypt, sharp, canvas, grpc, or sqlite3

**Prevention:**
```bash
detect_node_version() {
    local project_dir="$1"

    # Priority order for version detection
    if [[ -f "$project_dir/.nvmrc" ]]; then
        cat "$project_dir/.nvmrc"
    elif [[ -f "$project_dir/.node-version" ]]; then
        cat "$project_dir/.node-version"
    elif [[ -f "$project_dir/package.json" ]]; then
        jq -r '.engines.node // empty' "$project_dir/package.json" 2>/dev/null
    fi
}

switch_if_needed() {
    local required="$1"
    if [[ -n "$required" ]]; then
        log_info "Project requires Node.js $required"
        lxc exec "$CONTAINER" -- bash -c "source ~/.nvm/nvm.sh && nvm install $required && nvm use $required"
    fi
}
```

**Recovery:**
1. Delete `node_modules` in container
2. Run `nvm install` with correct version
3. Run `npm rebuild` or fresh `npm install`

**Sources:**
- [Azure Blog: Module compiled against different Node.js version](https://azureossd.github.io/2023/05/31/Troubleshooting-a-Module-was-compiled-against-a-different-Node.js-version-errors/)
- [NVM Node Documentation](https://www.nvmnode.com/)

---

### Pitfall 3: Native Module Architecture Mismatch

**What goes wrong:** `node_modules` copied from macOS (ARM64 or x86_64) to Linux container (x86_64). Native modules are platform-specific binaries that won't run on different OS/architecture combinations.

**Why it happens:** Developers copy their entire project directory including `node_modules` to speed up migration. Native modules compiled for one platform are binary-incompatible with another.

**Consequences:**
- `Error: No native build was found for platform=linux arch=x64`
- Segmentation faults at runtime
- Mysterious crashes in dependencies

**Warning signs:**
- Source machine is macOS (especially Apple Silicon)
- Project uses: sharp, bcrypt, canvas, better-sqlite3, grpc, node-sass
- `node_modules` directory is being transferred (not just source code)

**Prevention:**
```bash
# NEVER copy node_modules from source
# Always exclude during transfer

transfer_files() {
    local source="$1"
    local dest="$2"

    # Use rsync with exclusions
    rsync -avz --exclude='node_modules' --exclude='.git' \
        "$source/" "$dest/"

    # Or with lxc file push, don't include node_modules
}

# Always reinstall dependencies in container
lxc exec "$CONTAINER" -- bash -c "cd /root/project && npm ci"
```

**Recovery:**
```bash
# In container
rm -rf node_modules
npm ci  # or npm install
```

**Sources:**
- [Medium: 5 Tips for Handling Node.js Native Module Issues](https://article.arunangshudas.com/5-tips-for-handling-node-js-native-module-issues-ce25ce47059f)
- [GitHub nodejs/node #21897](https://github.com/nodejs/node/issues/21897)

---

### Pitfall 4: Package Manager Mismatch

**What goes wrong:** Project uses pnpm (has `pnpm-lock.yaml`), but migration script runs `npm install`. This ignores the lockfile, potentially installing different versions of dependencies.

**Why it happens:** Scripts assume npm is universal. Different lockfile formats are incompatible across package managers.

**Consequences:**
- Different dependency versions than development
- Missing peer dependencies
- Broken symlinked packages (pnpm-specific)
- "Works on my machine" bugs

**Warning signs:**
- `pnpm-lock.yaml` present (pnpm)
- `yarn.lock` present (yarn)
- `package-lock.json` present (npm)
- Multiple lockfiles (indicates past manager switching — use newest)

**Prevention:**
```bash
detect_package_manager() {
    local project_dir="$1"

    if [[ -f "$project_dir/pnpm-lock.yaml" ]]; then
        echo "pnpm"
    elif [[ -f "$project_dir/yarn.lock" ]]; then
        echo "yarn"
    elif [[ -f "$project_dir/package-lock.json" ]]; then
        echo "npm"
    else
        echo "npm"  # default fallback
    fi
}

install_dependencies() {
    local pm
    pm=$(detect_package_manager "$PROJECT_DIR")

    case "$pm" in
        pnpm) lxc exec "$CONTAINER" -- bash -c "cd /root/project && pnpm install --frozen-lockfile" ;;
        yarn) lxc exec "$CONTAINER" -- bash -c "cd /root/project && yarn install --frozen-lockfile" ;;
        npm)  lxc exec "$CONTAINER" -- bash -c "cd /root/project && npm ci" ;;
    esac
}
```

**Recovery:** Delete `node_modules` and reinstall with correct package manager.

**Sources:**
- [pnpm Symlinked node_modules structure](https://pnpm.io/symlinked-node-modules-structure)

---

### Pitfall 5: Database Migration Without Database

**What goes wrong:** Migration script runs `npx prisma migrate deploy` before creating the PostgreSQL database. Prisma (or Drizzle) tries to connect to a non-existent database and fails.

**Why it happens:** Scripts assume the database already exists because PostgreSQL is running. But PostgreSQL starts with only default databases (postgres, template0, template1).

**Consequences:**
- Migration command fails with "database does not exist"
- Prisma: `P1003: Database does not exist`
- Scripts abort mid-migration

**Warning signs:**
- Database name in DATABASE_URL is project-specific (not "postgres")
- Migration tool detected (prisma/, drizzle/, migrations/)
- Fresh container (no prior database creation)

**Prevention:**
```bash
# Extract database name from DATABASE_URL
extract_db_name() {
    local db_url="$1"
    # postgres://user:pass@host:5432/dbname -> dbname
    echo "$db_url" | sed 's|.*/||' | sed 's|\?.*||'
}

setup_database() {
    local db_url
    db_url=$(lxc exec "$CONTAINER" -- bash -c "grep DATABASE_URL /root/project/.env" | cut -d= -f2-)
    local db_name
    db_name=$(extract_db_name "$db_url")

    if [[ -n "$db_name" && "$db_name" != "postgres" ]]; then
        log_info "Creating database: $db_name"
        lxc exec "$CONTAINER" -- bash -c "createdb -U dev '$db_name' 2>/dev/null || true"
    fi
}

# Order matters: setup_database THEN run_migrations
```

**Recovery:**
```bash
# In container
createdb -U dev myprojectdb
npx prisma migrate deploy  # or equivalent
```

**Sources:**
- [Prisma Docker Guide](https://www.prisma.io/docs/guides/docker)
- [notiz.dev: Prisma Migrate Deploy with Docker](https://notiz.dev/blog/prisma-migrate-deploy-with-docker/)

---

## Moderate Pitfalls

Mistakes that cause delays or require manual intervention.

---

### Pitfall 6: Non-Interactive Shell Breaks nvm

**What goes wrong:** `lxc exec container -- nvm use 18` fails with "nvm: command not found". nvm only loads in interactive login shells.

**Why it happens:** nvm is loaded via `.bashrc` which only runs in interactive shells. `lxc exec` runs a non-interactive shell by default.

**Consequences:**
- Node version switching fails silently
- Wrong Node version used for npm install
- ABI mismatch errors appear later

**Warning signs:**
- nvm commands fail in scripts
- `node --version` shows wrong version after nvm use
- Works when you `lxc exec -- bash` interactively but not in scripts

**Prevention:**
```bash
# Always source nvm explicitly or use login shell
container_exec() {
    lxc exec "$CONTAINER" -- bash -l -c "$1"
    # The -l flag makes it a login shell, loading .bashrc
}

# Or source nvm explicitly
lxc exec "$CONTAINER" -- bash -c "source ~/.nvm/nvm.sh && nvm use 18 && npm install"
```

**Recovery:** Re-run commands with proper shell initialization.

**Sources:**
- [GitHub nvm-sh/nvm #2797](https://github.com/nvm-sh/nvm/issues/2797)
- [LogRocket: How to switch Node.js versions](https://blog.logrocket.com/how-switch-node-js-versions-nvm/)

---

### Pitfall 7: Prisma in Non-Interactive Environment

**What goes wrong:** `prisma migrate dev` hangs or fails with warnings about non-interactive environment. Prisma detect it's not in a terminal and refuses to run certain commands.

**Why it happens:** `prisma migrate dev` is designed for interactive development — it prompts for input. In containers/CI, you need `prisma migrate deploy` or `prisma db push`.

**Consequences:**
- Migration hangs waiting for input
- Script appears frozen
- Timeout after several minutes

**Warning signs:**
- Using `prisma migrate dev` in scripts
- Error: "Prisma Migrate was detected to be run in a non-interactive environment"
- Container exec commands never complete

**Prevention:**
```bash
run_migrations() {
    local migration_tool
    migration_tool=$(detect_migration_tool)

    case "$migration_tool" in
        prisma)
            # Use deploy (not dev) for non-interactive
            lxc exec "$CONTAINER" -- bash -c "cd /root/project && npx prisma migrate deploy"
            ;;
        drizzle)
            lxc exec "$CONTAINER" -- bash -c "cd /root/project && npx drizzle-kit push"
            ;;
    esac
}
```

**Recovery:** Kill the stuck process, use `migrate deploy` instead.

**Sources:**
- [Prisma Troubleshooting](https://www.prisma.io/docs/orm/prisma-migrate/workflows/troubleshooting)

---

### Pitfall 8: Permission Denied on node_modules

**What goes wrong:** `npm install` fails with `EACCES: permission denied` when trying to create files in node_modules.

**Why it happens:** In LXC containers running as root, this is less common than Docker. But it can happen if files were transferred with wrong ownership or if npm cache has permission issues.

**Consequences:**
- npm install fails
- Partial installations leave broken state
- Manual chown required

**Warning signs:**
- Error mentions EACCES and a path in node_modules
- Transferred files owned by non-existent UID
- npm cache in unusual location

**Prevention:**
```bash
# After file transfer, fix ownership
transfer_files() {
    lxc file push -r "$SOURCE" "$CONTAINER/root/project/"

    # Ensure root owns everything (we're running as root in container)
    lxc exec "$CONTAINER" -- chown -R root:root /root/project/
}

# Clear npm cache if issues persist
lxc exec "$CONTAINER" -- npm cache clean --force
```

**Recovery:**
```bash
# In container
chown -R root:root /root/project/
rm -rf node_modules
npm install
```

**Sources:**
- [npm Docs: Resolving EACCES permissions errors](https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally/)
- [Code Concisely: Fix Docker Permission Denied for node_modules](https://www.codeconcisely.com/posts/docker-node-modules-permission-denied/)

---

### Pitfall 9: PgBouncer Connection Pooling Conflicts

**What goes wrong:** Prisma migrate commands fail with "prepared statement 's0' already exists" when connecting through a connection pooler.

**Why it happens:** Some projects have PgBouncer or similar connection poolers configured. Prisma migrations require direct database connections, not pooled connections.

**Consequences:**
- Migrations fail with cryptic prepared statement errors
- Works for regular queries but not migrations
- Confusing because app itself might work

**Warning signs:**
- DATABASE_URL contains port 6543 (common PgBouncer port)
- Error: "prepared statement 's0' already exists"
- Project has PgBouncer in its stack

**Prevention:**
```bash
# For migrations, use direct DATABASE_URL without pooler
# Many projects use DIRECT_URL for this

if grep -q 'DIRECT_URL\|DIRECT_DATABASE_URL' "$PROJECT_DIR/.env"; then
    log_info "Project has DIRECT_URL - using for migrations"
fi

# In container .env, ensure DATABASE_URL points to localhost:5432 (direct)
# not any pooler port
```

**Recovery:** Set up a separate DIRECT_URL environment variable pointing to port 5432.

**Sources:**
- [Prisma Limitations and known issues](https://www.prisma.io/docs/orm/prisma-migrate/understanding-prisma-migrate/limitations-and-known-issues)

---

### Pitfall 10: Port Conflicts in Container

**What goes wrong:** `npm start` fails with `EADDRINUSE: address already in use :::3000`. Something is already listening on port 3000 in the container.

**Why it happens:**
- Previous npm process didn't shut down cleanly
- Another service started on same port
- nodemon zombie processes from failed runs

**Consequences:**
- App won't start
- User thinks migration failed

**Warning signs:**
- Error: "EADDRINUSE: address already in use"
- Prior migration attempt crashed
- Using nodemon and terminated with Ctrl+Z instead of Ctrl+C

**Prevention:**
```bash
# Before starting app, check for port conflicts
check_port() {
    local port="$1"
    if lxc exec "$CONTAINER" -- lsof -i ":$port" >/dev/null 2>&1; then
        log_warn "Port $port is in use"
        lxc exec "$CONTAINER" -- lsof -i ":$port"
        return 1
    fi
    return 0
}

# Kill previous node processes if needed
cleanup_node_processes() {
    lxc exec "$CONTAINER" -- pkill -f "node" 2>/dev/null || true
}
```

**Recovery:**
```bash
# In container
lsof -i :3000  # Find PID
kill -9 <PID>  # Or: pkill -f node
```

**Sources:**
- [bobbyhadz: Error listen EADDRINUSE address already in use](https://bobbyhadz.com/blog/node-express-eaddrinuse-address-already-in-use)

---

## Minor Pitfalls

Mistakes that cause annoyance but are easily fixed.

---

### Pitfall 11: Missing .env File

**What goes wrong:** Source project has `.env` in `.gitignore` (correctly), so git clone doesn't include it. App crashes on startup due to missing environment variables.

**Prevention:**
```bash
# When cloning from git, check for .env.example
if [[ ! -f /root/project/.env ]]; then
    if [[ -f /root/project/.env.example ]]; then
        log_warn "No .env found, copying from .env.example"
        cp /root/project/.env.example /root/project/.env
        log_warn "Edit /root/project/.env with actual values"
    else
        log_error "No .env or .env.example found - app may not start"
    fi
fi
```

**Recovery:** Create `.env` manually or copy from `.env.example`.

---

### Pitfall 12: Git Not Installed in Container

**What goes wrong:** Migration from git URL fails because git isn't installed in the container.

**Prevention:**
```bash
# The provisioning script (03) should install git
# But verify before clone attempt
ensure_git() {
    if ! lxc exec "$CONTAINER" -- which git >/dev/null 2>&1; then
        log_info "Installing git..."
        lxc exec "$CONTAINER" -- apt-get update
        lxc exec "$CONTAINER" -- apt-get install -y git
    fi
}
```

**Note:** The existing `03-provision-container.sh` installs git via `build-essential` meta-package. This should already be covered, but verification is cheap.

---

### Pitfall 13: Large node_modules Transfer Time

**What goes wrong:** If accidentally transferring `node_modules` (against advice), transfer takes forever. node_modules can be hundreds of MB with thousands of small files.

**Prevention:**
```bash
# Always exclude node_modules
transfer_files() {
    rsync -avz \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='dist' \
        --exclude='.next' \
        --exclude='.nuxt' \
        "$SOURCE/" "$CONTAINER_PATH/"
}
```

**Recovery:** Cancel transfer, restart with exclusions.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Source analysis | Missing .nvmrc detection | Check multiple version sources |
| File transfer | node_modules copied | Always exclude, reinstall in container |
| Node setup | nvm not loaded | Use `bash -l -c` for login shell |
| npm install | Wrong package manager | Detect from lockfile |
| Database setup | DB doesn't exist | Create before running migrations |
| Migrations | Using `migrate dev` | Use `migrate deploy` for non-interactive |
| .env handling | localhost in URLs | Offer to update to container IP |
| App startup | Port already in use | Check/kill before starting |

---

## Quick Reference: Detection Commands

```bash
# Detect Node version requirement
cat .nvmrc 2>/dev/null || jq -r '.engines.node // empty' package.json 2>/dev/null

# Detect package manager
[[ -f pnpm-lock.yaml ]] && echo "pnpm" || \
[[ -f yarn.lock ]] && echo "yarn" || echo "npm"

# Detect migration tool
[[ -d prisma ]] && echo "prisma" || \
[[ -f drizzle.config.ts ]] && echo "drizzle" || \
[[ -d migrations ]] && echo "raw-sql" || echo "none"

# Check for native modules
jq -r '.dependencies + .devDependencies | keys[]' package.json | \
    grep -E '^(bcrypt|sharp|canvas|better-sqlite3|grpc|node-sass)$'

# Check for localhost in .env
grep -E 'localhost|127\.0\.0\.1' .env

# Check port availability
lsof -i :3000 -t
```

---

## Sources

### Container Networking & Database
- [Prisma Discussion #20794: Can't reach database at localhost](https://github.com/prisma/prisma/discussions/20794) - HIGH confidence
- [Prisma Discussion #14187: Can't reach database at postgres](https://github.com/prisma/prisma/discussions/14187) - HIGH confidence
- [Semaphore: Dockerizing a Node.js Web Application](https://semaphore.io/community/tutorials/dockerizing-a-node-js-web-application) - MEDIUM confidence

### Node.js Version Management
- [Azure Blog: Module compiled against different Node.js version](https://azureossd.github.io/2023/05/31/Troubleshooting-a-Module-was-compiled-against-a-different-Node.js-version-errors/) - HIGH confidence
- [nvm-sh/nvm GitHub](https://github.com/nvm-sh/nvm) - HIGH confidence
- [LogRocket: How to switch Node.js versions](https://blog.logrocket.com/how-switch-node-js-versions-nvm/) - MEDIUM confidence

### Native Modules
- [Medium: 5 Tips for Handling Node.js Native Module Issues](https://article.arunangshudas.com/5-tips-for-handling-node-js-native-module-issues-ce25ce47059f) - MEDIUM confidence
- [GitHub nodejs/node #21897](https://github.com/nodejs/node/issues/21897) - HIGH confidence

### Migration Tools
- [Prisma: How to use Prisma in Docker](https://www.prisma.io/docs/guides/docker) - HIGH confidence
- [Prisma Troubleshooting](https://www.prisma.io/docs/orm/prisma-migrate/workflows/troubleshooting) - HIGH confidence
- [notiz.dev: Prisma Migrate Deploy with Docker](https://notiz.dev/blog/prisma-migrate-deploy-with-docker/) - MEDIUM confidence
- [Drizzle ORM: Migrate from Prisma](https://orm.drizzle.team/docs/migrate/migrate-from-prisma) - HIGH confidence

### Permissions & Package Managers
- [npm Docs: Resolving EACCES permissions errors](https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally/) - HIGH confidence
- [pnpm: Symlinked node_modules structure](https://pnpm.io/symlinked-node-modules-structure) - HIGH confidence

### Port Conflicts
- [bobbyhadz: Error listen EADDRINUSE](https://bobbyhadz.com/blog/node-express-eaddrinuse-address-already-in-use) - MEDIUM confidence
- [OpenReplay: Fix EADDRINUSE in Node.js](https://blog.openreplay.com/fix-error-eaddrinuse-nodejs/) - MEDIUM confidence

---

**Confidence:** HIGH - All critical pitfalls verified with multiple sources; prevention strategies based on official documentation and established patterns.
