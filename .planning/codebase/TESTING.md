# Testing Patterns

**Analysis Date:** 2026-02-01

## Test Framework

**Status:** No automated testing framework currently configured.

This is an infrastructure automation project written in bash. No test runner (jest, vitest, mocha, pytest, etc.) is installed or configured.

**Why testing is different for bash scripts:**
- These are imperative infrastructure scripts, not libraries with discrete testable units
- Success is measured by: container creation, network connectivity, software installation
- Testing requires actual LXC/Tailscale environment, not mock data
- Manual testing via staged deployments is the primary validation approach

## Testing Approach

**Manual staged testing pattern (observed):**

1. **Dry-run on non-critical infrastructure:**
   - Test scripts on a staging VPS before production
   - Run `01-setup-host.sh` on empty box
   - Verify each step logs expected output

2. **Snapshot-based testing (built-in):**
   - Create sandbox, snapshot before changes
   - Apply modifications
   - Restore from snapshot if issues arise
   - Example from README:
     ```bash
     ./sandbox.sh snapshot relay-dev before-migration
     # Do risky stuff...
     ./sandbox.sh restore relay-dev before-migration  # If it breaks
     ```

3. **Exit code validation:**
   - All scripts use `set -euo pipefail` so any command failure stops execution
   - Parent scripts check container status before proceeding
   - Example from `02-create-container.sh`:
     ```bash
     if [[ "$(lxc info "$CONTAINER_NAME" | grep 'Status:' | awk '{print $2}')" != "RUNNING" ]]; then
         log_error "Container failed to start"
         exit 1
     fi
     ```

4. **Network connectivity checks:**
   - Polling pattern waits for container network availability
   - From `02-create-container.sh`:
     ```bash
     for i in {1..30}; do
         if lxc exec "$CONTAINER_NAME" -- ping -c 1 8.8.8.8 &> /dev/null; then
             log_info "Network connectivity confirmed"
             break
         fi
         if [[ $i -eq 30 ]]; then
             log_error "Container networking failed after 30 seconds"
             exit 1
         fi
         sleep 1
     done
     ```

5. **Installation verification:**
   - Each provisioning step ends with a successful log message
   - Software versions are queried at end:
     ```bash
     log_info "LXD version: $(lxd --version)"
     log_info "Bridge network: $(lxc network show lxdbr0 | grep 'ipv4.address')"
     ```

## Precondition Checks

**Before operations, scripts validate:**

**Root/sudo requirement:**
```bash
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (or with sudo)"
   exit 1
fi
```

**OS detection:**
```bash
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    log_error "Cannot detect OS"
    exit 1
fi
```

**Command availability:**
```bash
if command -v lxd &> /dev/null; then
    log_warn "LXD already installed, skipping..."
else
    snap install lxd --channel=latest/stable
fi
```

**Container existence before provisioning:**
```bash
if ! lxc info "$CONTAINER_NAME" &> /dev/null; then
    log_error "Container '$CONTAINER_NAME' does not exist"
    echo "Create it first with: ./02-create-container.sh $CONTAINER_NAME"
    exit 1
fi
```

**Container running state:**
```bash
if [[ "$(lxc info "$CONTAINER_NAME" | grep 'Status:' | awk '{print $2}')" != "RUNNING" ]]; then
    log_error "Container '$CONTAINER_NAME' is not running"
    echo "Start it with: lxc start $CONTAINER_NAME"
    exit 1
fi
```

**Input validation (container naming):**
```bash
if [[ ! "$CONTAINER_NAME" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
    log_error "Container name must start with a letter and contain only letters, numbers, and hyphens"
    exit 1
fi
```

## Cleanup Patterns

**Optional package installation cleanup:**
When packages are conditionally installed, scripts verify they won't be reinstalled:
```bash
if command -v lxd &> /dev/null; then
    log_warn "LXD already installed, skipping..."
else
    snap install lxd --channel=latest/stable
fi
```

**Cloud-init lock avoidance:**
Initial container setup waits for cloud-init to complete before package operations:
```bash
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 1
done
```

## Idempotency

**Scripts are idempotent where possible:**

- `01-setup-host.sh` checks before installing (won't reinstall LXD)
- Running `01-setup-host.sh` multiple times is safe
- Creating a container with same name fails with clear error (prevents data loss)
- Provisioning requires fresh container (prevents duplicate software install)

## Manual Testing Workflow

**Recommended workflow for testing changes:**

1. **Create test sandbox:**
   ```bash
   sudo ./02-create-container.sh test-sandbox
   ```

2. **Edit provisioning script (`03-provision-container.sh`) with changes**

3. **Provision with modified script:**
   ```bash
   sudo ./03-provision-container.sh test-sandbox <tailscale-key>
   ```

4. **Validate installation in container:**
   ```bash
   lxc exec test-sandbox -- node --version
   lxc exec test-sandbox -- psql --version
   lxc exec test-sandbox -- playwright --version
   ```

5. **If successful, container is production-ready**

6. **If changes break, snapshot helps recovery:**
   ```bash
   ./sandbox.sh snapshot test-sandbox before-changes
   # Make changes...
   ./sandbox.sh restore test-sandbox before-changes  # If needed
   ```

## Validation Points

**After `01-setup-host.sh`:**
- LXD runs: `lxd --version` returns version
- Bridge exists: `lxc network show lxdbr0` shows network config
- Storage ready: `lxc storage show default` shows btrfs driver
- Optional: Tailscale authenticates: `tailscale status` shows device

**After `02-create-container.sh <name>`:**
- Container exists: `lxc info <name>` returns info
- Status is RUNNING: Not stopped/frozen
- Internal IP assigned: `lxc list <name>` shows 4th column (IP)
- SSH accessible: `ssh root@<IP>` works (if key-based auth configured)
- Internet accessible: `lxc exec <name> -- ping 8.8.8.8` succeeds

**After `03-provision-container.sh <name> <key>`:**
- Tailscale connected: `lxc exec <name> -- tailscale ip -4` returns IP
- Node.js installed: `lxc exec <name> -- node --version` returns v22.x
- npm installed: `lxc exec <name> -- npm --version` returns version
- PostgreSQL running: `lxc exec <name> -- psql --version` returns version
- Database accessible: `lxc exec <name> -- psql -c "SELECT version();"` works
- Playwright browsers: `lxc exec <name> -- npx playwright --version` shows browsers
- Claude Code CLI: `lxc exec <name> -- claude --version` returns version
- Convex CLI: `lxc exec <name> -- convex --version` returns version

**From sandbox.sh commands:**
- `./sandbox.sh list` shows all containers
- `./sandbox.sh info <name>` shows snapshots, IPs, status
- `./sandbox.sh ip <name>` returns Tailscale IP
- `./sandbox.sh snapshot <name> label` creates named snapshot
- `./sandbox.sh restore <name> label` restores from snapshot

## Known Testing Limitations

**No unit test framework:**
- Bash functions cannot be tested in isolation without environment
- Each script depends on LXC/Tailscale being available on host
- Network operations cannot be mocked

**No CI/CD pipeline:**
- No automated tests on commit/PR
- Scripts must be validated manually on test infrastructure

**Environment-specific:**
- Tests only valid on Hetzner VPS with LXD
- Requires Tailscale account and auth keys
- Cannot run in typical CI (GitHub Actions, etc.) without special setup

## Documentation as Specification

The README.md and CLAUDE.md files serve as executable specifications:
- Expected behavior documented in examples
- Troubleshooting section identifies failure modes
- Architecture diagram clarifies design intent

These should be kept in sync with script behavior.

## Regression Prevention

**Best practice for changes:**
1. Make changes to scripts
2. Test on staging VPS
3. Create new sandbox: `sudo ./02-create-container.sh staging-test`
4. Provision: `sudo ./03-provision-container.sh staging-test <key>`
5. Manually validate all installed tools work
6. Only commit if all validations pass
7. Run existing commands to ensure no regressions:
   - `./sandbox.sh list` still works
   - Snapshots still work
   - Delete/restore operations still work

---

*Testing analysis: 2026-02-01*
