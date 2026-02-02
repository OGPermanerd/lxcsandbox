# Dev Sandbox Infrastructure

## What This Is

Infrastructure scripts to create fully isolated development sandboxes on a single Hetzner VPS using LXC containers with Tailscale networking. Each sandbox gets its own IP address, allowing multiple projects to bind to standard ports (3000, 5432) without conflicts.

## Core Value

Complete isolation between projects so Claude Code can run autonomously (`--dangerously-skip-permissions`) without contaminating other environments.

## Current State (v1.2 Shipped)

**Shipped:** 2026-02-02

**Deliverables (v1.0):**
- `01-setup-host.sh` — Idempotent LXD setup with bridge network and btrfs storage
- `02-create-container.sh` — Container launch with TUN device and resource limits
- `03-provision-container.sh` — Full dev stack (Tailscale, Node.js, PostgreSQL, Playwright, Claude Code)
- `sandbox.sh` — Unified CLI with 8 commands (create, shell, list, snapshot, restore, delete, info, migrate)

**Deliverables (v1.1):**
- `04-migrate-project.sh` — Project migration with git clone, local copy, Node.js setup, database integration
- Package manager detection (npm/yarn/pnpm)
- Database migration execution (Prisma/Drizzle/raw SQL)
- Monorepo build support

**Deliverables (v1.2):**
- Automatic credential copying from host (Claude Code + git)
- SSH keys, .gitconfig, gh CLI copied to both root and dev users
- GitHub/GitLab added to known_hosts automatically

**Blocking:** Integration testing on actual LXD host with Tailscale auth key

## Requirements

### Validated

- ✓ Host setup with LXD, bridge network, btrfs storage — v1.0
- ✓ Container creation with TUN device and resource limits — v1.0
- ✓ Tailscale VPN integration with auth key — v1.0
- ✓ Node.js 22 via nvm with npm, yarn, pnpm — v1.0
- ✓ PostgreSQL with dev/dev credentials and remote access — v1.0
- ✓ Playwright with Chromium and Firefox — v1.0
- ✓ Claude Code CLI — v1.0
- ✓ Management CLI (create, shell, list, snapshot, restore, delete, info) — v1.0
- ✓ Project migration from git URLs and local paths — v1.1
- ✓ Package manager detection and dependency installation — v1.1
- ✓ Database creation and migration execution — v1.1
- ✓ Monorepo build support — v1.1
- ✓ Claude Code credentials copied from host automatically — v1.2
- ✓ Git credentials (SSH keys, gh CLI) copied from host by default — v1.2
- ✓ GitHub/GitLab added to SSH known_hosts automatically — v1.2

### Active

(None — ready for next milestone)

### Out of Scope

- Template containers for faster spinup — defer until basic flow validated
- Backup to Hetzner object storage — future enhancement
- MCP tool for sandbox management — future enhancement
- GPU passthrough — not needed for current use case
- Docker support — LXC chosen specifically for full Linux environment
- Data migration (copying production data) — migrations only, fresh DB
- Interactive secret prompting — preserve .env as-is

## Context

**Target environment:** Hetzner VPS with ~8GB RAM running Ubuntu 22.04/24.04.

**Key technical requirements:**
- Unprivileged LXC containers need explicit TUN device for Tailscale
- LXD manages lxdbr0 bridge with NAT automatically
- Each container gets Tailscale IP (100.64.x.x) for direct access

**Migration context:**
- Projects may use different migration tools (Prisma, Drizzle, raw SQL)
- .env files may reference localhost which needs updating to container context
- Node.js version may differ from container default (check .nvmrc)

## Constraints

- **Platform**: Ubuntu 22.04 or 24.04 on host and containers
- **Resources**: ~8GB RAM total, need to fit host + 1-2 containers
- **Networking**: Tailscale for container access, no Hetzner floating IPs needed
- **Permissions**: Scripts require root/sudo on host
- **SACRED: Host access**: Never break SSH or Tailscale access to the host VPS — this is the recovery path if something goes wrong. All LXC changes must be additive, not modify existing host networking.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| LXC over Docker | Claude Code needs full Linux env (apt install, system config) | ✓ Good — works well |
| Tailscale per container | Avoids port mapping, provides direct IP access | ✓ Good — verified in code |
| Unprivileged containers | Security best practice, requires TUN device passthrough | ✓ Good — TUN validation added |
| btrfs storage pool | Enables efficient snapshots for rollback | ✓ Good — snapshot/restore work |
| Preseed-based LXD config | Non-interactive idempotent setup | ✓ Good — avoids conflicts |
| Soft memory limits (4GB) | Allow bursting when single container running | ✓ Good — flexibility |
| Native Claude Code installer | Simpler PATH handling than npm | ✓ Good — per RESEARCH.md |
| trust auth for PostgreSQL | Dev-only environment | ✓ Good — enables Tailscale access |
| Argument-based CLI | Non-interactive for scriptability | ✓ Good — automation friendly |
| Default credential copying | Auth should "just work" without flags | ✓ Good — v1.2 |

---
*Last updated: 2026-02-02 after v1.2 milestone complete*
