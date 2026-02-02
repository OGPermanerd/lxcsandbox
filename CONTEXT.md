# Dev Sandbox Project - Context for Claude Code

## Problem Statement

Running multiple dev projects on a single Hetzner VPS creates resource contention:
- **Port conflicts**: Multiple apps want port 3000, 5432, etc.
- **Database contamination**: Claude Code configures postgres differently per project
- **Config collisions**: Autonomous tooling in `--dangerously-skip-permissions` mode modifies system files

Need fully isolated "sandboxes" where each project has its own environment, accessible without complex port mapping.

## Solution: LXC + Tailscale

**LXC containers** (not Docker) because Claude Code needs a full Linux environment — it runs `apt install`, modifies system configs, starts services. LXC feels like a VM but with minimal overhead.

**Tailscale per container** gives each sandbox its own IP (100.64.x.x). No port mapping needed — every container can bind to port 3000 because they have different IPs.

## Architecture

```
Developer laptop (Tailscale: 100.64.1.1)
    │
    └── Tailscale mesh (encrypted, NAT-punching)
            │
Hetzner VPS (single $4-20/mo server, one public IP)
    │
    ├── lxdbr0 bridge (10.10.10.0/24) ← LXD creates/manages this internally
    │
    ├── LXC: relay-dev
    │       ├── Internal: 10.10.10.2
    │       ├── Tailscale: 100.64.1.5
    │       └── postgres:5432, node:3000, playwright, claude-code
    │
    └── LXC: project-b
            ├── Internal: 10.10.10.3
            ├── Tailscale: 100.64.1.6
            └── postgres:5432, node:3000 (no conflict!)
```

**Key insight**: You don't need Hetzner to give you multiple IPs. LXD creates its own virtual network (lxdbr0) entirely inside your VPS. Tailscale then provides routable IPs from anywhere.

## Implementation - Three Scripts

### 01-setup-host.sh (run once)
- Installs LXD via snap
- Creates bridge network (10.10.10.0/24) with NAT
- Creates btrfs storage pool
- Configures firewall

### 02-create-container.sh <name>
- Launches Ubuntu 24.04 LXC container
- Adds TUN device (required for Tailscale in unprivileged containers)
- Sets resource limits (4GB RAM, 2 CPU default)
- Installs basic packages (curl, git, ssh)

### 03-provision-container.sh <name> <tailscale-authkey>
- Installs and connects Tailscale
- Installs Node.js 22 via nvm
- Installs PostgreSQL (user: dev, pass: dev, db: dev)
- Installs Playwright with browsers
- Installs Claude Code CLI, Convex CLI
- Configures shell environment with helpful aliases

## Usage

```bash
# First time setup
sudo ./01-setup-host.sh

# Create new sandbox
sudo ./02-create-container.sh relay-dev
sudo ./03-provision-container.sh relay-dev tskey-auth-xxxxx

# Access
./sandbox.sh shell relay-dev           # From host
ssh root@relay-dev                      # From laptop (MagicDNS)
http://100.64.x.x:3000                  # Browser

# Snapshot before risky operations
./sandbox.sh snapshot relay-dev before-migration
./sandbox.sh restore relay-dev before-migration
```

## Tailscale Setup

Get auth key from https://login.tailscale.com/admin/settings/keys
- **Reusable**: Yes (for multiple containers)
- **Ephemeral**: Yes (auto-removes device when container deleted)

## Key Technical Details

1. **LXC needs TUN device for Tailscale**: Unprivileged containers don't have /dev/net/tun by default
   ```bash
   lxc config device add <name> tun unix-char path=/dev/net/tun
   ```

2. **LXD handles all internal networking**: The host's lxdbr0 bridge does DHCP and NAT automatically

3. **No Hetzner network config needed**: This all happens inside the VPS, Hetzner only sees traffic from the single public IP

4. **Floating IPs not required**: Tailscale provides the per-container addressability

## Files in This Project

```
dev-sandbox-infra/
├── CLAUDE.md                    # Detailed project context
├── README.md                    # User documentation
├── 01-setup-host.sh            # Host infrastructure
├── 02-create-container.sh      # Container creation
├── 03-provision-container.sh   # Dev stack provisioning
└── sandbox.sh                  # Helper for common operations
```

## Potential Enhancements

- Template container for faster spinup (provision once, copy many)
- Ansible playbook for complex provisioning
- Backup to Hetzner object storage
- MCP tool for sandbox management from Claude
- GPU passthrough for ML projects
