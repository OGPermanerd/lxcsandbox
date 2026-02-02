# Dev Sandbox Infrastructure

Fully isolated development sandboxes on a single Hetzner VPS using LXC containers and Tailscale.

## Why?

When using Claude Code in `--dangerously-skip-permissions` mode, it makes autonomous decisions about ports, databases, and system config. Running multiple projects on the same box leads to:
- Port conflicts (both want port 3000)
- Database contamination (both configure postgres differently)
- Config file collisions

This solution gives each project its own "virtual machine" (LXC container) with its own Tailscale IP, so everything is isolated.

## Quick Start

```bash
# 1. Clone to your Hetzner VPS
git clone <this-repo> ~/dev-sandbox-infra
cd ~/dev-sandbox-infra
chmod +x *.sh

# 2. Set up host infrastructure (once)
sudo ./01-setup-host.sh

# 3. Create a sandbox
sudo ./sandbox.sh create relay-dev
# Enter your Tailscale auth key when prompted

# 4. Access it
./sandbox.sh shell relay-dev
# Or from your laptop: ssh root@relay-dev (with Tailscale + MagicDNS)
```

## What's Installed

Each sandbox comes with:
- **Node.js 22** via nvm (with npm, yarn, pnpm)
- **PostgreSQL** (user: dev, pass: dev, db: dev)
- **Playwright** with Chromium and Firefox
- **Claude Code CLI**
- **Convex CLI**
- **Python 3** with pip and venv
- **Git, tmux, htop**, and build tools

## Commands

```bash
./sandbox.sh list                    # List all sandboxes
./sandbox.sh create <name>           # Create new sandbox
./sandbox.sh delete <name>           # Delete sandbox
./sandbox.sh shell <name>            # Open shell
./sandbox.sh snapshot <name> <label> # Create snapshot
./sandbox.sh restore <name> <label>  # Restore from snapshot
./sandbox.sh info <name>             # Show details
./sandbox.sh ip <name>               # Show Tailscale IP
```

## Architecture

```
Your Laptop (Tailscale)
    │
    └── Encrypted mesh
            │
Hetzner VPS ($4-20/mo)
    │
    ├── lxdbr0 (10.10.10.0/24)
    │
    ├── relay-dev (100.64.x.5)
    │   └── postgres, node, etc.
    │
    └── project-b (100.64.x.6)
        └── postgres, node, etc.
```

## Tailscale Auth Keys

Get a reusable auth key from https://login.tailscale.com/admin/settings/keys

Recommended settings:
- **Reusable**: Yes (create multiple sandboxes)
- **Ephemeral**: Yes (auto-cleanup when container deleted)
- **Tags**: `tag:dev-sandbox` (optional, for ACLs)

## Customization

### Add more packages to provisioning

Edit `03-provision-container.sh` and add to the apt-get or npm install sections.

### Change resource limits

Edit `02-create-container.sh`:
```bash
lxc config set "$CONTAINER_NAME" limits.memory=8GB
lxc config set "$CONTAINER_NAME" limits.cpu=4
```

### Use a different base image

```bash
./02-create-container.sh my-project 22.04  # Ubuntu 22.04
```

## Tips

### Snapshot before risky operations
```bash
./sandbox.sh snapshot relay-dev before-migration
# Do risky stuff...
./sandbox.sh restore relay-dev before-migration  # If it breaks
```

### Create a template container
```bash
# Provision a container with everything you want
# Then copy it as a template
lxc copy relay-dev dev-template
lxc snapshot dev-template base

# Create new containers from template
lxc copy dev-template/base new-project
```

### Access from browser
With Tailscale MagicDNS enabled:
- http://relay-dev:3000
- http://relay-dev:5173 (Vite)

Or use Tailscale IP directly:
- http://100.64.x.x:3000

## Troubleshooting

### "TUN device not found"
```bash
lxc config device add <name> tun unix-char path=/dev/net/tun
lxc restart <name>
```

### Container has no internet
```bash
# Check NAT rules on host
sudo iptables -t nat -L POSTROUTING -v
```

### Tailscale won't connect
```bash
# Check inside container
lxc exec <name> -- tailscale status
lxc exec <name> -- journalctl -u tailscaled
```

## License

MIT
