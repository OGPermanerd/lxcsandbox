# Dev Sandbox Infrastructure

## What This Is

Infrastructure scripts to create fully isolated development sandboxes on a single Hetzner VPS using LXC containers with Tailscale networking. Each sandbox gets its own IP address, allowing multiple projects to bind to standard ports (3000, 5432) without conflicts.

## Core Value

Complete isolation between projects so Claude Code can run autonomously (`--dangerously-skip-permissions`) without contaminating other environments.

## Requirements

### Validated

(None yet — scripts are untested drafts)

### Active

- [ ] Host setup script initializes LXD with bridge network on Ubuntu VPS
- [ ] Container creation script launches isolated LXC container with TUN device
- [ ] Provisioning script installs Tailscale and connects with auth key
- [ ] Provisioning script installs Node.js 22 via nvm
- [ ] Provisioning script installs PostgreSQL with dev/dev credentials
- [ ] Provisioning script installs Playwright with browsers
- [ ] Provisioning script installs Claude Code CLI
- [ ] Container is accessible via Tailscale IP from developer laptop
- [ ] Management CLI provides common operations (create, shell, snapshot, delete)

### Out of Scope

- Template containers for faster spinup — defer until basic flow works
- Backup to Hetzner object storage — future enhancement
- MCP tool for sandbox management — future enhancement
- GPU passthrough — not needed for current use case
- Docker support — LXC chosen specifically for full Linux environment

## Context

**Existing codebase:** Four shell scripts exist as untested drafts:
- `01-setup-host.sh` — LXD installation, bridge network, storage pool
- `02-create-container.sh` — Container launch, TUN device, resource limits
- `03-provision-container.sh` — Dev stack installation (Tailscale, Node, Postgres, etc.)
- `sandbox.sh` — CLI wrapper for common operations

**Target environment:** Existing Hetzner VPS with ~8GB RAM running Ubuntu.

**Tailscale:** Auth key ready for container provisioning.

**Key technical requirements:**
- Unprivileged LXC containers need explicit TUN device for Tailscale
- LXD manages lxdbr0 bridge with NAT automatically
- Each container gets Tailscale IP (100.64.x.x) for direct access

## Constraints

- **Platform**: Ubuntu 22.04 or 24.04 on host and containers
- **Resources**: ~8GB RAM total, need to fit host + 1-2 containers
- **Networking**: Tailscale for container access, no Hetzner floating IPs needed
- **Permissions**: Scripts require root/sudo on host
- **SACRED: Host access**: Never break SSH or Tailscale access to the host VPS — this is the recovery path if something goes wrong. All LXC changes must be additive, not modify existing host networking.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| LXC over Docker | Claude Code needs full Linux env (apt install, system config) | — Pending |
| Tailscale per container | Avoids port mapping, provides direct IP access | — Pending |
| Unprivileged containers | Security best practice, requires TUN device passthrough | — Pending |
| btrfs storage pool | Enables efficient snapshots for rollback | — Pending |

---
*Last updated: 2026-02-01 after initialization*
