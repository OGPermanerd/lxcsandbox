# Phase 7: Node.js Setup - Research

**Researched:** 2026-02-01
**Domain:** Node.js dependency installation with package manager detection and version management
**Confidence:** HIGH

## Summary

Phase 7 focuses on installing Node.js project dependencies after files have been transferred (Phase 6). The phase must detect the correct package manager from lockfiles, handle .nvmrc files for Node version requirements, and fall back to .env.example if .env is missing.

Research confirms the standard approach:
1. Detect package manager by checking for lockfile existence (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`)
2. Read .nvmrc (if present) and install/switch to the specified Node version using nvm
3. Run the appropriate install command (`pnpm install`, `yarn install`, `npm install`)
4. Copy .env.example to .env if .env doesn't exist but .env.example does
5. Verify node_modules directory exists after installation

**Primary recommendation:** Use simple file existence checks for lockfile detection (no jq needed - eliminates noted blocker). Use `node -p` to parse package.json when needed since Node.js is already available.

## Standard Stack

The established tools for this domain:

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| nvm | v0.40.4 (installed in container) | Node version management | Already provisioned in Phase 3 |
| npm | bundled with Node.js | Package manager fallback | Default, always available |
| yarn | via corepack | Package manager option | Corepack enabled in Phase 3 |
| pnpm | via corepack | Package manager option | Corepack enabled in Phase 3 |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| bash test -f | system | Lockfile detection | Checking which lockfile exists |
| node -p | installed | JSON parsing | Read .nvmrc or package.json fields |
| cp | system | File copy | Copy .env.example to .env |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| File existence check | jq + package.json parsing | jq adds dependency; lockfile check is simpler and standard |
| npm install | npm ci | npm ci requires package-lock.json; npm install works for all scenarios |

**No additional packages needed:** All required tools are already installed from Phase 3 (nvm, npm, yarn, pnpm via corepack).

## Architecture Patterns

### Recommended Script Structure
```
# Addition to 04-migrate-project.sh OR new function
setup_nodejs_dependencies() {
    |
    +-- Lockfile Detection
    |     +-- detect_package_manager() -> "npm" | "yarn" | "pnpm"
    |
    +-- Node Version Management (optional)
    |     +-- detect_nvmrc_version()
    |     +-- install_required_node_version()
    |
    +-- Dependency Installation
    |     +-- run_package_install()
    |     +-- verify_node_modules()
    |
    +-- Environment Setup
          +-- copy_env_example_if_needed()
}
```

### Pattern 1: Package Manager Detection
**What:** Determine which package manager to use by checking for lockfiles
**When to use:** First step before dependency installation
**Example:**
```bash
# Source: https://www.npmjs.com/package/detect-package-manager (pattern)
# Lockfile precedence: pnpm > yarn > npm (most specific wins)
detect_package_manager() {
    local project_dir="$1"

    if [[ -f "$project_dir/pnpm-lock.yaml" ]]; then
        echo "pnpm"
    elif [[ -f "$project_dir/yarn.lock" ]]; then
        echo "yarn"
    elif [[ -f "$project_dir/package-lock.json" ]]; then
        echo "npm"
    else
        # No lockfile - default to npm
        echo "npm"
    fi
}
```

### Pattern 2: .nvmrc Version Detection and Installation
**What:** Read .nvmrc and install Node version if different from current
**When to use:** Before running package manager install
**Example:**
```bash
# Source: https://github.com/nvm-sh/nvm#nvmrc
detect_and_install_node_version() {
    local project_dir="$1"

    # Source nvm for non-interactive shell (CRITICAL)
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if [[ -f "$project_dir/.nvmrc" ]]; then
        local required_version
        required_version=$(cat "$project_dir/.nvmrc" | tr -d '[:space:]')

        log_info "Detected .nvmrc requiring Node $required_version"

        # nvm install handles both "not installed" and "already installed"
        cd "$project_dir"
        nvm install  # Reads .nvmrc automatically
        nvm use      # Switch to the version

        log_info "Using Node $(node --version)"
    else
        log_info "No .nvmrc found, using default Node version"
    fi
}
```

### Pattern 3: Dependency Installation with Verification
**What:** Run correct package manager install and verify success
**When to use:** After Node version is set up
**Example:**
```bash
# Source: Best practices from npm, yarn, pnpm documentation
install_dependencies() {
    local project_dir="$1"
    local pm
    pm=$(detect_package_manager "$project_dir")

    # Source nvm for non-interactive shell
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    cd "$project_dir"

    log_info "Installing dependencies with $pm..."

    case "$pm" in
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

    # Verify installation succeeded
    if [[ ! -d "$project_dir/node_modules" ]]; then
        log_error "node_modules not created - installation may have failed"
        return 1
    fi

    log_info "Dependencies installed successfully"
}
```

### Pattern 4: .env.example Fallback
**What:** Copy .env.example to .env if .env doesn't exist
**When to use:** After file transfer, before or after npm install
**Example:**
```bash
# Source: Common Node.js project convention
copy_env_example_if_needed() {
    local project_dir="$1"

    if [[ ! -f "$project_dir/.env" ]] && [[ -f "$project_dir/.env.example" ]]; then
        log_info "No .env found, copying from .env.example..."
        cp "$project_dir/.env.example" "$project_dir/.env"
        log_warn ".env created from .env.example - review and update values"
    elif [[ -f "$project_dir/.env" ]]; then
        log_info ".env file exists"
    else
        log_warn "No .env or .env.example found"
    fi
}
```

### Anti-Patterns to Avoid
- **Running npm install without sourcing nvm:** In non-interactive shells, nvm is not loaded automatically
- **Assuming package-lock.json always exists:** Projects may only have yarn.lock or pnpm-lock.yaml
- **Using npm ci unconditionally:** Fails if package-lock.json is missing or out of sync
- **Hardcoding Node version:** Always check .nvmrc for project-specific requirements
- **Modifying .env if it exists:** Only copy .env.example as fallback, never overwrite existing .env

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Package manager detection | Parsing package.json | Lockfile existence check | Simpler, more reliable indicator |
| Node version switching | Manual binary management | nvm install/use | Handles downloads, linking, PATH |
| JSON parsing in bash | Complex regex | node -p "require('./package.json').field" | Node is already installed |
| Dependency integrity | Manual verification | Package manager's built-in checks | Lock files verify integrity |

**Key insight:** The container already has nvm and corepack configured (Phase 3). Leverage what's installed rather than building custom solutions.

## Common Pitfalls

### Pitfall 1: nvm Not Available in Non-Interactive Shell
**What goes wrong:** "nvm: command not found" when running via `lxc exec`
**Why it happens:** nvm is sourced in .bashrc which only loads for interactive shells
**How to avoid:** Always source nvm.sh before using nvm commands
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```
**Warning signs:** "nvm: command not found" or "node: command not found" errors

### Pitfall 2: Wrong Package Manager After Detection
**What goes wrong:** Use npm when project needs pnpm (or vice versa)
**Why it happens:** Checking files in wrong order or missing lockfile
**How to avoid:** Check lockfiles in order: pnpm-lock.yaml, yarn.lock, package-lock.json
**Warning signs:** Different node_modules structure, missing dependencies

### Pitfall 3: .nvmrc Format Variations
**What goes wrong:** nvm fails to parse .nvmrc
**Why it happens:** .nvmrc may contain "v16.20.0", "16.20.0", "16", "lts/*", or "node"
**How to avoid:** Let nvm handle parsing via `nvm install` in the project directory
**Warning signs:** "N/A: version not found" errors

### Pitfall 4: node_modules Not Created
**What goes wrong:** Dependency install appears to succeed but node_modules is empty or missing
**Why it happens:** Install command ran in wrong directory, or permissions issue
**How to avoid:** Always verify node_modules exists after install
**Warning signs:** Missing node_modules directory, "Cannot find module" errors

### Pitfall 5: Overwriting User's .env
**What goes wrong:** User's configured .env file gets replaced with template
**Why it happens:** Script always copies .env.example without checking
**How to avoid:** Only copy if .env doesn't exist: `[[ ! -f .env ]] && cp .env.example .env`
**Warning signs:** Lost database credentials, API keys reset

### Pitfall 6: Current Directory Not Set
**What goes wrong:** Commands execute in wrong directory
**Why it happens:** `cd` inside functions doesn't affect outer scope, or using relative paths
**How to avoid:** Use `cd "$project_dir"` explicitly before nvm/npm commands
**Warning signs:** "package.json not found" errors

## Code Examples

Verified patterns from official sources:

### Complete Package Manager Detection (lxc exec compatible)
```bash
# Run inside container via lxc exec
# Source: Pattern from detect-package-manager npm package
container_exec '
    detect_package_manager() {
        local project_dir="${1:-.}"

        if [[ -f "$project_dir/pnpm-lock.yaml" ]]; then
            echo "pnpm"
        elif [[ -f "$project_dir/yarn.lock" ]]; then
            echo "yarn"
        elif [[ -f "$project_dir/package-lock.json" ]]; then
            echo "npm"
        else
            echo "npm"
        fi
    }

    PM=$(detect_package_manager "/root/projects/myproject")
    echo "Detected package manager: $PM"
'
```

### Complete Node Version Setup (lxc exec compatible)
```bash
# Source: https://github.com/nvm-sh/nvm (non-interactive usage)
container_exec '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    PROJECT_DIR="/root/projects/myproject"
    cd "$PROJECT_DIR"

    if [[ -f .nvmrc ]]; then
        echo "Found .nvmrc, installing required Node version..."
        nvm install
        nvm use
    fi

    echo "Node version: $(node --version)"
'
```

### Complete Dependency Installation (lxc exec compatible)
```bash
# Full setup function for use via lxc exec
container_exec '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    PROJECT_DIR="/root/projects/myproject"
    cd "$PROJECT_DIR"

    # Detect package manager
    if [[ -f "pnpm-lock.yaml" ]]; then
        PM="pnpm"
    elif [[ -f "yarn.lock" ]]; then
        PM="yarn"
    else
        PM="npm"
    fi

    echo "Installing with $PM..."

    # Handle .nvmrc if present
    if [[ -f .nvmrc ]]; then
        nvm install
        nvm use
    fi

    # Install dependencies
    case "$PM" in
        pnpm) pnpm install ;;
        yarn) yarn install ;;
        npm)  npm install ;;
    esac

    # Verify
    if [[ -d node_modules ]]; then
        echo "SUCCESS: node_modules created"
    else
        echo "ERROR: node_modules not found"
        exit 1
    fi
'
```

### .env.example Fallback
```bash
# Source: Common Node.js convention
container_exec '
    PROJECT_DIR="/root/projects/myproject"

    if [[ ! -f "$PROJECT_DIR/.env" ]] && [[ -f "$PROJECT_DIR/.env.example" ]]; then
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
        echo "Created .env from .env.example"
    fi
'
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| jq for JSON parsing | node -p with require() | Node.js available | No extra dependency |
| Global Node.js install | nvm with .nvmrc | nvm standard | Project-specific versions |
| npm only | Detect from lockfile | 2020+ | Respect project tooling |
| .env.example manual copy | Automated fallback copy | Convention | Better developer experience |

**Deprecated/outdated:**
- Using `apt install nodejs`: Version management impossible, use nvm instead
- Ignoring .nvmrc: Projects may require specific Node versions
- npm ci in all cases: Fails without package-lock.json

## Open Questions

Things that couldn't be fully resolved:

1. **Handling conflicting lockfiles**
   - What we know: Some projects have multiple lockfiles (e.g., both package-lock.json and yarn.lock)
   - What's unclear: Which should take precedence?
   - Recommendation: Use detection order (pnpm > yarn > npm) and document behavior

2. **Yarn Berry (v2+) vs Yarn Classic**
   - What we know: Yarn Berry uses different commands for some operations
   - What's unclear: Whether we need to detect Yarn version
   - Recommendation: Use `yarn install` which works for both; defer version detection if issues arise

3. **Bun package manager**
   - What we know: Bun uses bun.lockb and is gaining popularity
   - What's unclear: Whether to add bun support
   - Recommendation: Defer to future phase; npm/yarn/pnpm cover vast majority of projects

## Sources

### Primary (HIGH confidence)
- [nvm GitHub README](https://github.com/nvm-sh/nvm) - .nvmrc format, non-interactive usage, nvm install/use commands
- [npm documentation](https://docs.npmjs.com/cli/v10/commands/npm-install) - npm install behavior
- [pnpm documentation](https://pnpm.io/cli/install) - pnpm install, --frozen-lockfile
- [yarn documentation](https://classic.yarnpkg.com/en/docs/cli/install) - yarn install

### Secondary (MEDIUM confidence)
- [detect-package-manager npm package](https://www.npmjs.com/package/detect-package-manager) - Lockfile detection pattern
- [npm ci vs npm install best practices](https://www.baeldung.com/ops/npm-install-vs-npm-ci) - When to use each
- [Node.js dotenv patterns](https://github.com/motdotla/dotenv) - .env and .env.example conventions
- [Cyberphinix lockfile comparison](https://cyberphinix.de/blog/package-lock-json-vs-yarn-lock-vs-pnpm-lock-yaml-basics/) - Lockfile formats

### Tertiary (LOW confidence)
- WebSearch results for bash JSON parsing alternatives (verified with node -p approach)

## Metadata

**Confidence breakdown:**
- Package manager detection: HIGH - Simple file existence, well-documented pattern
- nvm usage: HIGH - Official nvm documentation, same pattern as Phase 3
- .env.example handling: HIGH - Universal Node.js convention
- Installation commands: HIGH - Official package manager documentation

**Research date:** 2026-02-01
**Valid until:** 2026-04-01 (stable domain, 60 days)

---

## Appendix: Requirements Mapping

| Requirement | Technical Approach | Verified |
|-------------|-------------------|----------|
| NODE-01: Detect package manager from lock files | Check pnpm-lock.yaml, yarn.lock, package-lock.json in order | Yes |
| NODE-02: Run appropriate install command | Switch on detected PM: pnpm/yarn/npm install | Yes |
| NODE-03: Detect .nvmrc and install Node version | Read .nvmrc, use nvm install + nvm use | Yes |
| NODE-04: Verify node_modules exists | test -d "$PROJECT_DIR/node_modules" | Yes |
| ENV-02: Fall back to .env.example if .env missing | [[ ! -f .env ]] && [[ -f .env.example ]] && cp | Yes |

All Phase 7 requirements have clear technical implementations identified.

---

## Appendix: Blocker Resolution

**Blocker from STATE.md:** "jq needs to be added to container packages for package.json parsing"

**Resolution:** Not needed. Package manager detection uses lockfile existence (no JSON parsing required). For any JSON parsing needs, use `node -p "require('./package.json').field"` since Node.js is already installed in the container.
