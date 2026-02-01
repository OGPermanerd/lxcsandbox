---
phase: 03-stack-provisioning
plan: 01
subsystem: infra
tags: [lxc, tailscale, nodejs, nvm, postgresql, playwright, claude-code, bash]

# Dependency graph
requires:
  - phase: 02-container-creation
    provides: LXC container with TUN device and network connectivity
provides:
  - Complete dev stack provisioning script (03-provision-container.sh)
  - Tailscale VPN integration for direct IP access
  - PostgreSQL with remote access configuration
  - Node.js 22 with npm, yarn, pnpm via corepack
  - Playwright browsers (Chromium, Firefox)
  - Claude Code CLI
  - Shell environment with database vars and aliases
affects: [04-testing-ux, future container provisioning]

# Tech tracking
tech-stack:
  added: [tailscale-cli, nvm-v0.40.4, node-22, corepack, postgresql-16, playwright, claude-code]
  patterns: [idempotent-installation, container-exec-wrapper, nvm-sourcing-in-scripts]

key-files:
  created: [03-provision-container.sh]
  modified: []

key-decisions:
  - "Use native installer for Claude Code (not npm) per RESEARCH.md"
  - "pgcrypto extension for gen_random_uuid() support"
  - "trust auth for PostgreSQL (dev environment only)"
  - "corepack for yarn/pnpm instead of manual install"
  - "Chromium+Firefox only (no WebKit per CONTEXT.md)"

patterns-established:
  - "container_exec(): wrapper for lxc exec with bash -c"
  - "NVM sourcing: always export NVM_DIR and source nvm.sh before nvm commands"
  - "Idempotency checks: check before install, skip if already present"
  - "60s timeout for Tailscale connection with spinner feedback"

# Metrics
duration: 4min
completed: 2026-02-01
---

# Phase 3 Plan 01: Stack Provisioning Summary

**Tailscale VPN, Node.js 22 via nvm, PostgreSQL with remote access, Playwright browsers, and Claude Code CLI - fully idempotent 583-line script**

## Performance

- **Duration:** 4 min (211 seconds)
- **Started:** 2026-02-01T18:29:33Z
- **Completed:** 2026-02-01T18:33:04Z
- **Tasks:** 6
- **Files created:** 1

## Accomplishments

- Complete provisioning script covering all 11 PROV requirements
- Fully idempotent with 14 "already installed/configured" checks
- Comprehensive status summary with connection instructions
- Shell environment with DATABASE_URL, PG* vars, and useful aliases

## Task Commits

Each task was committed atomically:

1. **Task 1: Script structure with argument handling and helpers** - `4236b3f` (feat)
2. **Task 2: Tailscale installation and connection** - `57f748c` (feat)
3. **Task 3: PostgreSQL installation and configuration** - `5f6758a` (feat)
4. **Task 4: nvm, Node.js, and package managers** - `7c0d7fd` (feat)
5. **Task 5: Playwright and Claude Code installation** - `9b3dcc5` (feat)
6. **Task 6: Shell configuration and main execution** - `a65f903` (feat)

## Files Created

- `03-provision-container.sh` - Complete dev stack provisioning script (583 lines)
  - Tailscale installation with 60s connection timeout
  - PostgreSQL with dev/dev credentials and pgcrypto
  - nvm/Node.js 22 with corepack-managed yarn/pnpm
  - Playwright with Chromium and Firefox
  - Claude Code CLI via native installer
  - Shell configuration with env vars and aliases

## Decisions Made

- **Native installer for Claude Code:** Per RESEARCH.md, native installer preferred over npm for simpler PATH handling
- **pgcrypto extension:** Pre-installed for gen_random_uuid() - 2x faster than uuid-ossp
- **trust auth for PostgreSQL:** Dev-only environment, enables passwordless remote access via Tailscale
- **corepack for yarn/pnpm:** Built into Node.js, provides per-project version management

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - all tasks completed successfully.

## User Setup Required

None - no external service configuration required. Tailscale auth key is provided at runtime.

## Next Phase Readiness

- All three scripts (01, 02, 03) now complete
- Ready for Phase 4: Testing and UX Polish
- Integration testing requires actual LXD host with Tailscale auth key

---
*Phase: 03-stack-provisioning*
*Completed: 2026-02-01*
