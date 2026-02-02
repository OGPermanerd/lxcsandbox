# Dev Sandbox Infrastructure

## Project Objective

Create fully isolated development sandboxes on a single Hetzner VPS using LXC containers, where each sandbox:
- Runs a complete dev stack (postgres, node, npm, convex, clerk, playwright, puppeteer, claude code, etc.)
- Has its own Tailscale IP for direct access without port conflicts
- Is completely isolated from other projects (no database contention, no port collisions)
- Supports Claude Code in `--dangerously-skip-permissions` mode doing autonomous config/testing

## Architecture

```
Your PC (Tailscale: 100.64.x.x)
    │
    └── Tailscale mesh (encrypted)
            │
Hetzner VPS (single public IPv4, ~$20/mo)
    │
    ├── Host: runs LXD, Tailscale (optional)
    │
    ├── lxdbr0 bridge (10.10.10.0/24) - managed by LXD
    │
    ├── LXC: relay-dev
    │       ├── Tailscale: 100.64.x.5
    │       └── Full dev stack, postgres:5432, node:3000
    │
    ├── LXC: project-b
    │       ├── Tailscale: 100.64.x.6
    │       └── Full dev stack, postgres:5432, node:3000
    │
    └── LXC: project-c
            ├── Tailscale: 100.64.x.7
            └── Full dev stack, postgres:5432, node:3000
```

Each container binds to standard ports (3000, 5432, etc.) with no conflicts because each has its own Tailscale IP.

## File Structure

```
dev-sandbox-infra/
├── CLAUDE.md                    # This file - project context
├── 01-setup-host.sh            # One-time host infrastructure setup
├── 02-create-container.sh      # Creates new LXC container with networking
├── 03-provision-container.sh   # Installs dev stack inside container
├── config/
│   └── container-packages.txt  # List of apt packages to install
└── templates/
    └── bashrc-additions.sh     # Shell customizations for containers
```

## Usage

### Initial Setup (once per VPS)
```bash
# SSH into Hetzner VPS
./01-setup-host.sh
```

### Create New Sandbox
```bash
# Create container named "relay-dev"
./02-create-container.sh relay-dev

# Provision with dev tools (run from host, executes inside container)
./03-provision-container.sh relay-dev tskey-auth-xxxxxxx
```

### Access Sandbox
```bash
# From your local machine (with Tailscale)
ssh relay-dev                        # MagicDNS name
ssh root@100.64.x.x                  # Direct Tailscale IP
http://relay-dev:3000                # Web app in browser

# Or from host
lxc exec relay-dev -- bash
```

## Key Design Decisions

1. **LXC over Docker**: Claude Code needs to run system commands, install packages, modify configs. LXC provides a full Linux environment that feels like a VM.

2. **Tailscale per container**: Each container gets its own 100.x.x.x IP. No port mapping, no NAT gymnastics, accessible from anywhere.

3. **Unprivileged containers with TUN**: Security best practice, but requires explicit TUN device passthrough for Tailscale.

4. **Reusable auth keys**: Use Tailscale reusable+ephemeral auth keys so containers can be created/destroyed without manual auth.

## Environment Variables

Scripts expect these (or will prompt):
- `TAILSCALE_AUTHKEY`: Reusable auth key from Tailscale admin console

## Tailscale Auth Key Setup

1. Go to https://login.tailscale.com/admin/settings/keys
2. Generate auth key with:
   - Reusable: Yes
   - Ephemeral: Yes (optional, auto-removes device when container deleted)
   - Tags: `tag:dev-sandbox` (optional, for ACLs)

## Common Operations

### List all sandboxes
```bash
lxc list
```

### Snapshot before risky operation
```bash
lxc snapshot relay-dev before-migration
```

### Restore from snapshot
```bash
lxc restore relay-dev before-migration
```

### Delete sandbox
```bash
lxc delete relay-dev --force
```

### Copy sandbox as template
```bash
lxc copy relay-dev relay-template
```

## Troubleshooting

### Container can't reach internet
```bash
# Check NAT is working
lxc exec relay-dev -- ping 8.8.8.8

# If not, verify lxdbr0 exists and has masquerade
sudo iptables -t nat -L POSTROUTING
```

### Tailscale won't start in container
```bash
# Verify TUN device exists
lxc exec relay-dev -- ls -la /dev/net/tun

# If missing, re-add it
lxc config device add relay-dev tun unix-char path=/dev/net/tun
lxc restart relay-dev
```

### Port already in use (inside container)
```bash
# Find what's using it
lxc exec relay-dev -- lsof -i :5432
```

## Future Enhancements

- [ ] Ansible playbook version for more complex provisioning
- [ ] Automated backup to Hetzner object storage
- [ ] Template container with pre-baked stack for faster spinup
- [ ] Integration with Claude Code MCP for sandbox management
