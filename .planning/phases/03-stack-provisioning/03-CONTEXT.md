# Phase 3: Stack Provisioning - Context

**Gathered:** 2026-02-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Install complete dev stack inside LXC containers and connect to Tailscale for direct IP access. Takes a container name and Tailscale auth key, installs all required tools (Node.js, PostgreSQL, Playwright, Claude Code), and configures the shell environment. Container creation is handled by Phase 2.

</domain>

<decisions>
## Implementation Decisions

### Tailscale Setup
- Auth key provided as script argument: `./03-provision-container.sh container-name tskey-auth-xxx`
- Verify connection: IP assigned (100.x.x.x) AND `tailscale status` shows connected
- Timeout: 60 seconds for Tailscale to connect
- On failure: Fail script, leave container running for debugging (consistent with Phase 2)

### Database Configuration
- Credentials: Hardcoded dev/dev (user=dev, password=dev, database=dev)
- Listen address: All interfaces (0.0.0.0) for Tailscale accessibility
- Authentication: trust for all connections (no password required, dev environment)
- Extensions: Claude's discretion based on common dev patterns

### Node.js Environment
- nvm installed for root user (system-wide)
- Default version: Node.js 22 LTS
- Package managers: npm bundled with Node, corepack enabled for yarn and pnpm
- Shell integration: nvm auto-loaded in .bashrc

### Script Execution Flow
- Fully idempotent: Check each component, skip if already installed, safe to re-run
- Partial failure: Keep installed components, fail script (user can re-run to finish)
- Progress: Step-by-step with status markers (Installing Tailscale... check)
- Final output: Full status summary with all versions, IPs, paths, and env vars

### Claude's Discretion
- PostgreSQL extensions to pre-install (if any)
- Exact spinner/progress implementation
- Order of component installation
- Playwright installation approach (npm global vs npx)
- Claude Code CLI installation method

</decisions>

<specifics>
## Specific Ideas

- Follow same patterns as 01-setup-host.sh and 02-create-container.sh for consistency
- Database accessible via Tailscale IP from development machine (psql -h 100.x.x.x -U dev dev)
- Full status summary helps users immediately know how to connect

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope

</deferred>

---

*Phase: 03-stack-provisioning*
*Context gathered: 2026-02-01*
