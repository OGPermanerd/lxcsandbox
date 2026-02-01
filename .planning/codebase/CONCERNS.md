# Codebase Concerns

**Analysis Date:** 2026-02-01

## Security Concerns

**Hardcoded Database Credentials:**
- Issue: PostgreSQL user and password are hardcoded as "dev"/"dev" in multiple locations
- Files: `03-provision-container.sh` (lines 134, 144-248), shell environment setup (lines 245-248)
- Impact: Every container created has the same default credentials. If any container is compromised, the credentials are known. Production exposure would be catastrophic.
- Fix approach: Generate random passwords during provisioning, store in environment files with restricted permissions, output to user with warning about security implications.

**Tailscale Auth Key Exposure in Process:**
- Issue: Tailscale auth key passed as command-line argument to `tailscale up` command (line 88)
- Files: `03-provision-container.sh` (line 88)
- Impact: Auth key appears in process list (`ps aux`), shell history, and logs. Could allow privilege escalation or unauthorized network access.
- Fix approach: Pass auth key via environment variable or stdin instead of command argument.

**SSH Server with Root Login:**
- Issue: SSH is enabled with default root user and no explicit password policy enforcement
- Files: `02-create-container.sh` (lines 156, 164-165)
- Impact: Root account accessible directly; no key-only enforcement visible in provisioning scripts.
- Fix approach: Document SSH key setup requirements, enforce key-based auth only, disable root password login, create non-root user for typical operations.

**Firewall Configuration Not Enforced:**
- Issue: UFW firewall setup in `01-setup-host.sh` (line 146) can be skipped, and firewall may not be active on all deployments
- Files: `01-setup-host.sh` (lines 130-151)
- Impact: If skipped, host and all containers have no ingress protection from the public internet.
- Fix approach: Make firewall mandatory or provide clear security warning if skipped.

**Network Exposure via SSH in Containers:**
- Issue: SSH server installed and enabled in each container (lines 156, 164-165 in `02-create-container.sh`), directly accessible via Tailscale IP
- Files: `02-create-container.sh`, `03-provision-container.sh`
- Impact: Each container is a separate SSH entry point. Compromised container key = host access to that container.
- Fix approach: Document SSH key rotation requirements, implement audit logging for container access.

## Tech Debt

**Hardcoded Version Strings:**
- Issue: Node version, NVM version, and various package versions are hardcoded
- Files: `03-provision-container.sh` (lines 104, 110, 195, 213, 227)
- Impact: When versions become EOL or have security issues, all scripts must be manually updated. No CI mechanism to detect version deprecation.
- Fix approach: Extract versions to a configuration file (`.env.versions` or `config/versions.conf`), document update process, consider adding version checking before provisioning.

**No Error Handling for Network Issues:**
- Issue: `sleep` commands used for timing with no verification of actual readiness
- Files: `02-create-container.sh` (lines 76, 116), `03-provision-container.sh` (lines 92, 108)
- Impact: If container startup is slow or Tailscale connection is delayed, timing assumptions break and silent failures occur. User may think provisioning succeeded when it didn't.
- Fix approach: Replace fixed `sleep` calls with polling loops that verify actual readiness (e.g., wait for Tailscale IP to actually be assigned, wait for postgres to accept connections).

**Bash Script Error Handling Gaps:**
- Issue: `set -euo pipefail` used, but several commands suppress errors with `2>/dev/null` or `|| echo` without logging failures
- Files: `02-create-container.sh` (lines 58, 76, 79, 94, 124, 173), `03-provision-container.sh` (lines 94, 287), `sandbox.sh` (lines 107, 148, 159)
- Impact: When commands fail silently, users don't know what went wrong, making troubleshooting difficult.
- Fix approach: Log all suppressed errors to a file, show warning if error occurs despite silent suppression, document which errors are expected vs. unexpected.

**No Idempotency Guarantees:**
- Issue: Scripts assume fresh container state; re-running provisioning on an existing container could cause conflicts
- Files: `03-provision-container.sh` (no checks for existing installations)
- Impact: If provisioning script is run twice (intentionally for update, or accidentally), npm/python packages get installed multiple times, nvm gets re-sourced, git config gets re-applied.
- Fix approach: Add checks for existing installations (e.g., `if ! command -v node`, `if [ ! -d ~/.nvm ]`), skip already-installed components, handle re-runs gracefully.

**Database Connection String in Plain Bashrc:**
- Issue: DATABASE_URL with credentials stored in unencrypted `~/.bashrc`
- Files: `03-provision-container.sh` (lines 248)
- Impact: Database credentials visible in shell environment, shell history, and any process that inherits environment.
- Fix approach: Store in `.env` file with restricted permissions (mode 600), source from bashrc only, use `.env` as template for user to fill in real credentials.

**Missing Configuration Directory Structure:**
- Issue: Project documentation mentions `config/` and `templates/` directories that don't exist
- Files: `CLAUDE.md` (referenced structure), actual filesystem
- Impact: Users expect to find configuration files that aren't there; template usage unclear.
- Fix approach: Create `config/container-packages.txt`, `config/versions.conf`, `templates/bashrc-additions.sh` as documented, provide example configurations.

## Known Bugs

**Convex Installation Has Environment Variable Typo:**
- Symptom: Convex installation may fail silently or use wrong NVM directory
- Files: `03-provision-container.sh` (line 224)
- Trigger: Run provisioning script fully; check if `convex` command works in container
- Workaround: Manually re-run `npm install -g convex` inside container after provisioning
- Details: Line 224 uses `$ROOT/.nvm` instead of `$HOME/.nvm`, which evaluates to `/root/.nvm` (correct) but inconsistency with other steps (lines 107, 191, 211 use `$HOME/.nvm`)

**Container IP Extraction May Fail with Multiple Addresses:**
- Symptom: Container shows internal bridge IP but extraction logic assumes single address
- Files: `02-create-container.sh` (line 173), `03-provision-container.sh` (line 288)
- Trigger: If container has both IPv4 and IPv6 addresses, `cut -d' ' -f1` may select wrong address
- Workaround: Manually run `lxc list <name> --format csv -c 4` to verify IP
- Details: Output format is space-separated; if IPv6 is present, field extraction gets wrong IP

**Silent Failures in Tailscale IP Retrieval:**
- Symptom: Tailscale IP shown as "pending" or "error" in output but provisioning continues
- Files: `03-provision-container.sh` (lines 94-95, 287)
- Trigger: Tailscale takes longer than 5 seconds to connect; user runs command and Tailscale not ready
- Workaround: Wait 10+ seconds and run `./sandbox.sh ip <name>` manually
- Details: No polling loop ensures IP is actually assigned before reporting success

## Performance Bottlenecks

**Playwright Installation Downloads All Browsers:**
- Problem: Every container installs Chromium and Firefox even if only one is needed
- Files: `03-provision-container.sh` (lines 195-199)
- Cause: Default behavior of `npm install playwright` + `npx playwright install chromium firefox`
- Improvement path: Make browser installation configurable (optional parameter to script), provide pre-baked "minimal" vs "full" container templates.

**Full apt-get Upgrade on Every Container Creation:**
- Problem: Each new container downloads and applies all system package updates (slow, unnecessary)
- Files: `02-create-container.sh` (line 147)
- Cause: `apt-get update` is always run; base image may not be latest
- Improvement path: Use image caching strategy, create snapshotted "base-ready" container, clone from it instead of launching fresh each time.

**NVM Installation Downloads from GitHub on Every Provisioning:**
- Problem: `curl` downloads NVM install script and runs bash on every container creation
- Files: `03-provision-container.sh` (line 104)
- Cause: No caching mechanism; script assumes offline environment
- Improvement path: Cache NVM installer in container image, or pre-install in base template, significantly speeds up container provisioning (saves 1-2 minutes per container).

## Fragile Areas

**Tailscale Integration:**
- Files: `02-create-container.sh` (TUN device setup), `03-provision-container.sh` (installation and connection)
- Why fragile: TUN device must be added before restart; if missing, Tailscale fails silently. Auth key validity depends on external Tailscale service. Network connectivity depends on multiple layers (host NAT, firewall rules, Tailscale infrastructure).
- Safe modification: Always test Tailscale connectivity immediately after provisioning, log Tailscale service status, document common Tailscale failure modes.
- Test coverage: No automated tests verify Tailscale IP assignment; README mentions troubleshooting but no pre-flight checks.

**PostgreSQL Setup:**
- Files: `03-provision-container.sh` (lines 126-142)
- Why fragile: Hardcoded password, md5 auth method deprecated in PostgreSQL 14+, pg_hba.conf location varies by version (`/etc/postgresql/*/main/pg_hba.conf` glob assumes standard layout)
- Safe modification: Use a template for pg_hba.conf, test pg_connect before declaring success, verify PostgreSQL version before applying config.
- Test coverage: No verification that database is actually accessible after creation.

**Shell Environment Configuration:**
- Files: `03-provision-container.sh` (lines 237-264)
- Why fragile: Uses cat with heredoc to append to bashrc; if bashrc already has NVM setup, creates duplicates. No idempotent check.
- Safe modification: Check if environment block already exists before appending, use symlink to separate file instead of direct append.
- Test coverage: No test that bashrc is properly formatted after provisioning.

**Firewall Configuration:**
- Files: `01-setup-host.sh` (lines 130-151)
- Why fragile: UFW installation and enablement can be skipped; if skipped, host is unprotected. No check that rules actually applied.
- Safe modification: Make firewall mandatory, verify rules are active before declaring success, test connectivity after firewall setup.
- Test coverage: No verification that firewall rules are in place.

## Scaling Limits

**Storage Pool Size Hardcoded:**
- Current capacity: 50GB allocated in `01-setup-host.sh` (line 92)
- Limit: Each container base image ~500MB, plus provisioned tools ~2-3GB. At 4GB per container, fits ~12 containers before hitting 50GB limit
- Scaling path: Make storage size configurable, document how to check available disk space before provisioning, provide expansion procedure for btrfs pool.

**Memory Per Container Hardcoded:**
- Current capacity: 4GB per container in `02-create-container.sh` (line 106)
- Limit: Hetzner VPS sizing (e.g., $4/mo has 1GB, $12/mo has 4GB). Assigning 4GB to first container leaves none for second.
- Scaling path: Calculate available memory, adjust container limits based on VPS size, document memory requirements per container type, provide mechanism to override defaults.

**CPU Limits:**
- Current capacity: 2 CPU per container in `02-create-container.sh` (line 107)
- Limit: Small Hetzner plans have 2 vCPU total; assigning 2 to one container leaves nothing for others or host.
- Scaling path: Auto-detect available CPU, divide intelligently, allow per-container override.

## Missing Critical Features

**No Backup Mechanism:**
- Problem: If container corrupts, data is gone. No automated snapshots or backups.
- Blocks: Production-grade usage, long-running sandboxes with important data.
- Approach: Implement daily snapshot strategy with retention, document backup to object storage, provide restore-from-backup workflow.

**No Monitoring or Health Checks:**
- Problem: Container can fail silently; no alerting when Tailscale disconnects, PostgreSQL dies, or disk runs full.
- Blocks: Unattended sandbox operation, early detection of issues.
- Approach: Add health check endpoint (curl localhost:8080/health), implement logging/monitoring aggregation, add container status monitoring to sandbox.sh.

**No Audit Logging:**
- Problem: Changes to containers are not logged; no record of who provisioned what or when.
- Blocks: Compliance requirements, troubleshooting after-the-fact, security incident response.
- Approach: Log all lxc operations, record provisioning timestamps, implement container-level audit logging.

**No Cost Reporting:**
- Problem: No way to track which sandboxes consume storage/resources or estimate costs.
- Blocks: Multi-user scenarios, cost allocation.
- Approach: Add disk usage per container, monitor resource consumption, provide cost estimation.

## Test Coverage Gaps

**No Integration Tests:**
- What's not tested: End-to-end provisioning flow, networking between containers, Tailscale connectivity, database accessibility after setup.
- Files: No test files exist; only manual testing documented
- Risk: Provisioning script may have undiscovered bugs that only surface in specific conditions (old Ubuntu versions, specific Hetzner configurations, network conditions).
- Priority: High — many users will run these scripts; silent failures are costly.

**No Validation of Installed Versions:**
- What's not tested: Whether Node 22, PostgreSQL version, Playwright, Claude Code actually got installed and work.
- Files: No post-provisioning verification
- Risk: Users may think sandbox is ready when key tools are missing or broken.
- Priority: High — provisioning output suggests success but actual functionality untested.

**No Network Connectivity Tests:**
- What's not tested: Whether containers can reach internet, whether Tailscale IP actually works from external machines, whether firewall rules allow required traffic.
- Files: `02-create-container.sh` tests connectivity to 8.8.8.8 (line 124) but no test that Tailscale IP is routable from host or other containers.
- Risk: Provisioning appears successful but networking is partially broken.
- Priority: High — networking is fundamental to the value proposition.

**No PostgreSQL Connectivity Tests:**
- What's not tested: Whether PostgreSQL actually accepts connections after provisioning, whether dev user can create tables/query data.
- Files: `03-provision-container.sh` creates user and database but never verifies they work
- Risk: User attempts to use database and finds it misconfigured or unreachable.
- Priority: Medium — users may catch this quickly, but adds to troubleshooting burden.

**No SSH Key Setup Documentation:**
- What's not tested: SSH key authentication is not addressed; only password login documented
- Files: All scripts enable SSH (systemctl start ssh) but no key setup
- Risk: SSH access relies on default root password or container-specific setup users must remember.
- Priority: Medium — security impact if not addressed.

---

*Concerns audit: 2026-02-01*
