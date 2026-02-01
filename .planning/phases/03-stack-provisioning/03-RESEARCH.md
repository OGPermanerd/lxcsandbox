# Phase 3: Stack Provisioning - Research

**Researched:** 2026-02-01
**Domain:** LXC container provisioning with dev stack (Tailscale, Node.js, PostgreSQL, Playwright, Claude Code)
**Confidence:** HIGH

## Summary

This phase implements the `03-provision-container.sh` script that installs a complete development stack inside LXC containers. The script must be fully idempotent, checking each component before installation and supporting re-runs to complete partial installations.

Key technologies are well-documented with established installation patterns:
- **Tailscale**: curl-based install script with non-interactive auth via `--authkey`
- **nvm + Node.js 22**: curl install script with bash integration, corepack for yarn/pnpm
- **PostgreSQL 16**: Ubuntu 24.04 default package, simple trust auth for dev
- **Playwright**: npm package with `--with-deps` for system dependencies
- **Claude Code**: Native installer preferred over npm (no Node.js dependency)

**Primary recommendation:** Install components in order of dependencies (Tailscale first for connectivity verification, PostgreSQL early for stability, nvm/Node.js, then npm-based tools). Use idempotency checks before each install operation.

## Standard Stack

The locked decisions from CONTEXT.md specify these exact tools:

### Core Components
| Component | Version/Source | Purpose | Installation Method |
|-----------|---------------|---------|---------------------|
| Tailscale | Latest stable | VPN connectivity | `curl -fsSL https://tailscale.com/install.sh \| sh` |
| nvm | v0.40.4 | Node.js version manager | `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh \| bash` |
| Node.js | 22 LTS (Jod) | JavaScript runtime | `nvm install 22 && nvm alias default 22` |
| PostgreSQL | 16 (Ubuntu default) | Database | `apt install postgresql postgresql-contrib` |
| Playwright | Latest | Browser automation | `npx playwright install --with-deps chromium firefox` |
| Claude Code | Native binary | AI coding assistant | `curl -fsSL https://claude.ai/install.sh \| bash` |

### Package Managers (via Corepack)
| Tool | Method | Notes |
|------|--------|-------|
| npm | Bundled with Node.js | Default with Node.js 22 |
| yarn | `corepack enable` | Managed by corepack |
| pnpm | `corepack enable` | Managed by corepack |

### PostgreSQL Extensions (Claude's Discretion)
| Extension | Purpose | Recommendation |
|-----------|---------|----------------|
| pgcrypto | UUID generation, cryptography | **Recommended** - includes `gen_random_uuid()`, better performance than uuid-ossp |
| uuid-ossp | UUID generation | Not needed if pgcrypto installed |

**Recommendation:** Pre-install `pgcrypto` extension. It provides `gen_random_uuid()` for UUID generation (common in dev) and is twice as fast as uuid-ossp. Install with `CREATE EXTENSION IF NOT EXISTS pgcrypto;`.

## Architecture Patterns

### Recommended Installation Order

```
1. Tailscale        (first - provides connectivity verification)
2. PostgreSQL       (early - stable, no dependencies)
3. nvm + Node.js 22 (after apt packages)
4. Corepack enable  (after Node.js)
5. Playwright       (requires npm)
6. Claude Code      (last - native installer, independent)
```

**Rationale:**
- Tailscale first allows IP verification before proceeding
- PostgreSQL early because it's apt-based and stable
- Node.js before npm-dependent tools
- Claude Code last because it's independent (native installer)

### Script Structure Pattern

```bash
#!/bin/bash
# Follow 01-setup-host.sh and 02-create-container.sh patterns

set -euo pipefail
trap 'log_error "Script failed at line $LINENO"' ERR

# Colors and logging functions (same as other scripts)
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Idempotent install pattern
install_component() {
    if check_installed; then
        log_info "Component already installed, skipping..."
        return 0
    fi
    # Install logic here
}
```

### Execution via lxc exec

All installation commands run inside the container via:
```bash
lxc exec "$CONTAINER_NAME" -- bash -c 'commands here'
```

For multi-line scripts:
```bash
lxc exec "$CONTAINER_NAME" -- bash -c '
    # Multiple commands
    command1
    command2
'
```

## Don't Hand-Roll

Problems with existing solutions - use these instead:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Node.js installation | apt install nodejs | nvm | nvm provides version management, apt version is outdated |
| Package manager shims | Manual yarn/pnpm install | corepack | Built into Node.js, maintains per-project versions |
| Tailscale auth | Manual login flow | `--authkey` flag | Non-interactive, scriptable |
| Playwright browsers | Manual browser download | `--with-deps` | Handles system dependencies automatically |
| Claude Code install | npm global | Native installer | Simpler, no Node.js dependency, auto-updates |
| PostgreSQL user/db | Raw SQL files | createuser/createdb | Simpler, handles quoting |

**Key insight:** Each tool has a canonical installation method. Using alternatives (like apt for Node.js) creates version management problems later.

## Common Pitfalls

### Pitfall 1: apt Lock Contention
**What goes wrong:** `apt-get` fails because cloud-init or another process holds the lock
**Why it happens:** Ubuntu cloud images run apt on first boot
**How to avoid:** Wait for apt lock before any apt operations
```bash
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 1
done
```
**Warning signs:** Error message mentioning lock file or "waiting for lock"

### Pitfall 2: nvm Not Available in Non-Interactive Shell
**What goes wrong:** `nvm` command not found when running via `lxc exec`
**Why it happens:** nvm is sourced in .bashrc which only loads for interactive shells
**How to avoid:** Source nvm explicitly before use
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 22
```
**Warning signs:** "nvm: command not found" errors

### Pitfall 3: Tailscale Stuck on Authentication
**What goes wrong:** `tailscale up` hangs waiting for browser auth
**Why it happens:** Running without `--authkey` flag
**How to avoid:** Always use `tailscale up --authkey=<key>`
**Warning signs:** Script hangs, output shows URL to visit

### Pitfall 4: PostgreSQL Listening Only on Localhost
**What goes wrong:** Can't connect to PostgreSQL from development machine via Tailscale
**Why it happens:** Default `listen_addresses = 'localhost'`
**How to avoid:** Set `listen_addresses = '*'` in postgresql.conf
**Warning signs:** "connection refused" when connecting via Tailscale IP

### Pitfall 5: pg_hba.conf Order Matters
**What goes wrong:** Authentication fails despite adding trust rule
**Why it happens:** Earlier rule matches first (e.g., peer auth for local)
**How to avoid:** Add trust rules before restrictive rules, or replace existing rules
**Warning signs:** "authentication failed" errors

### Pitfall 6: Playwright Missing System Dependencies
**What goes wrong:** Browsers fail to launch with missing library errors
**Why it happens:** Using `npx playwright install` without `--with-deps`
**How to avoid:** Always use `npx playwright install --with-deps`
**Warning signs:** Errors mentioning libnss3, libatk, libgbm, etc.

### Pitfall 7: Claude Code npm PATH Issues
**What goes wrong:** `claude` command not found after npm install
**Why it happens:** npm global bin not in PATH
**How to avoid:** Use native installer instead of npm
**Warning signs:** "claude: command not found" after installation

## Code Examples

Verified patterns from official sources:

### Tailscale Installation and Auth
```bash
# Source: https://tailscale.com/kb/1031/install-linux
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Authenticate non-interactively with auth key
tailscale up --authkey="$TAILSCALE_AUTHKEY"

# Verify connection
tailscale status
tailscale ip -4  # Get assigned IP
```

### Tailscale Connection Verification
```bash
# Source: https://tailscale.com/kb/1241/tailscale-up
# Wait for Tailscale to connect with timeout
TIMEOUT=60
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    if tailscale status 2>/dev/null | grep -q "^100\."; then
        TAILSCALE_IP=$(tailscale ip -4)
        echo "Connected: $TAILSCALE_IP"
        break
    fi
    sleep 1
    ((ELAPSED++))
done
if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "Tailscale connection timed out"
    exit 1
fi
```

### nvm and Node.js Installation
```bash
# Source: https://github.com/nvm-sh/nvm
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

# Load nvm in current shell (required for non-interactive)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install Node.js 22 LTS and set as default
nvm install 22
nvm alias default 22

# Verify
node --version  # Should show v22.x.x
```

### Corepack Setup
```bash
# Source: https://nodejs.org/download/release/v22.11.0/docs/api/corepack.html
# Enable corepack (creates yarn and pnpm shims)
corepack enable

# Verify
yarn --version
pnpm --version
```

### PostgreSQL Setup
```bash
# Source: https://documentation.ubuntu.com/server/how-to/databases/install-postgresql/
# Install PostgreSQL
apt-get install -y postgresql postgresql-contrib

# Create user and database
sudo -u postgres createuser dev
sudo -u postgres createdb -O dev dev
sudo -u postgres psql -c "ALTER USER dev WITH PASSWORD 'dev';"

# Enable pgcrypto extension
sudo -u postgres psql -d dev -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
```

### PostgreSQL Remote Access Configuration
```bash
# Source: https://www.postgresql.org/docs/current/auth-pg-hba-conf.html
PG_VERSION=$(ls /etc/postgresql/)
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

# Listen on all interfaces
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

# Allow trust authentication from anywhere (dev only!)
echo "host    all    all    0.0.0.0/0    trust" >> "$PG_HBA"
echo "host    all    all    ::0/0        trust" >> "$PG_HBA"

# Restart PostgreSQL
systemctl restart postgresql
```

### Playwright Installation
```bash
# Source: https://playwright.dev/docs/browsers
# Install Playwright with browser dependencies
# Must run after nvm/node is available
npx playwright install --with-deps chromium firefox
```

### Claude Code Native Installation
```bash
# Source: https://code.claude.com/docs/en/setup
# Install Claude Code (native binary)
curl -fsSL https://claude.ai/install.sh | bash

# Verify
~/.local/bin/claude --version
# Or if added to PATH:
claude --version
```

## Idempotency Patterns

Verified patterns for checking installation state:

### Check if apt Package Installed
```bash
# Source: https://www.baeldung.com/linux/check-how-package-installed
if dpkg-query -W -f='${Status}' postgresql 2>/dev/null | grep -q "install ok installed"; then
    echo "PostgreSQL already installed"
else
    apt-get install -y postgresql
fi
```

### Check if nvm Installed
```bash
# Source: https://github.com/nvm-sh/nvm
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    echo "nvm already installed"
    \. "$NVM_DIR/nvm.sh"  # Load it
else
    # Install nvm
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
fi
```

### Check if Node.js Version Installed
```bash
# After loading nvm
if nvm ls 22 &>/dev/null; then
    echo "Node.js 22 already installed"
else
    nvm install 22
fi
```

### Check if Tailscale Installed and Connected
```bash
# Check installed
if command -v tailscale &>/dev/null; then
    echo "Tailscale installed"
fi

# Check connected
if tailscale status &>/dev/null; then
    if tailscale status | grep -q "^100\."; then
        echo "Tailscale connected"
        TAILSCALE_IP=$(tailscale ip -4)
    fi
fi
```

### Check if Claude Code Installed
```bash
if command -v claude &>/dev/null || [ -f "$HOME/.local/bin/claude" ]; then
    echo "Claude Code already installed"
else
    curl -fsSL https://claude.ai/install.sh | bash
fi
```

### Check if PostgreSQL User/Database Exists
```bash
# Check user exists
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='dev'" | grep -q 1; then
    echo "User 'dev' exists"
else
    sudo -u postgres createuser dev
fi

# Check database exists
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='dev'" | grep -q 1; then
    echo "Database 'dev' exists"
else
    sudo -u postgres createdb -O dev dev
fi
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| npm install claude-code | Native installer | 2025 | No Node.js dependency, auto-updates |
| Manual yarn/pnpm install | corepack enable | Node.js 16+ | Built-in, per-project versioning |
| uuid-ossp for UUIDs | pgcrypto gen_random_uuid() | PostgreSQL 9.5+ | 2x faster, better maintained |
| Tailscale --auth-key | Tailscale --authkey | 2024 | Both work, --authkey preferred |

**Deprecated/outdated:**
- `npm install -g @anthropic-ai/claude-code`: Deprecated in favor of native installer
- Manual browser downloads for Playwright: Use `--with-deps` instead

## Open Questions

Things that couldn't be fully resolved:

1. **Playwright Browser Selection**
   - What we know: Context says "Chromium and Firefox" per PROV-09
   - What's unclear: Whether WebKit should also be included
   - Recommendation: Install only chromium and firefox as specified

2. **Claude Code PATH Integration**
   - What we know: Native installer puts binary at `~/.local/bin/claude`
   - What's unclear: Whether installer adds to PATH automatically
   - Recommendation: Check PATH in .bashrc additions, add if missing

3. **PostgreSQL Version**
   - What we know: Ubuntu 24.04 includes PostgreSQL 16 by default
   - What's unclear: Whether newer PostgreSQL 17 should be used
   - Recommendation: Use default (16) for stability, matches apt sources

## Sources

### Primary (HIGH confidence)
- [Tailscale LXC Docs](https://tailscale.com/kb/1130/lxc) - TUN device requirements
- [Tailscale Linux Install](https://tailscale.com/kb/1031/install-linux) - Installation and authkey
- [nvm GitHub](https://github.com/nvm-sh/nvm) - v0.40.4 installation, bash integration
- [Node.js Corepack Docs](https://nodejs.org/download/release/v22.11.0/docs/api/corepack.html) - corepack enable
- [PostgreSQL pg_hba.conf Docs](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html) - Trust auth
- [PostgreSQL Trust Auth Docs](https://www.postgresql.org/docs/current/auth-trust.html) - Security implications
- [Playwright Installation](https://playwright.dev/docs/intro) - npm and --with-deps
- [Claude Code Setup](https://code.claude.com/docs/en/setup) - Native installer

### Secondary (MEDIUM confidence)
- [Ubuntu PostgreSQL Docs](https://documentation.ubuntu.com/server/how-to/databases/install-postgresql/) - Ubuntu 24.04 installation
- [Tailscale CLI Docs](https://tailscale.com/kb/1080/cli) - tailscale status, ip commands
- Multiple blog posts corroborating installation patterns

### Tertiary (LOW confidence)
- WebSearch results for idempotency patterns (verified against official docs)
- WebSearch results for PostgreSQL extensions (verified with pg docs)

## Metadata

**Confidence breakdown:**
- Tailscale installation: HIGH - Official docs, well-documented
- nvm/Node.js: HIGH - Official GitHub README with exact version
- PostgreSQL: HIGH - Official docs, Ubuntu standard package
- Playwright: HIGH - Official docs, standard npm pattern
- Claude Code: HIGH - Official setup docs
- Idempotency patterns: MEDIUM - Common patterns, verified approach

**Research date:** 2026-02-01
**Valid until:** 2026-03-01 (30 days - stable technologies)
