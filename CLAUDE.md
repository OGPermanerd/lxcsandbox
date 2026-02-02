# Dev Sandbox Infrastructure

## Claude Code Instructions

When you need me to run a command that requires elevated privileges (sudo) or must be run on the VPS host, **always append a tee to a log file** so I can just tell you when to check the log instead of copy-pasting output:

```bash
# Good - I can just say "check the log"
sudo ./sandbox.sh migrate test-sandbox ~/projects/relay 2>&1 | tee -a ~/sandbox-ops.log

# Bad - requires me to copy-paste potentially long output
sudo ./sandbox.sh migrate test-sandbox ~/projects/relay
```

This minimizes my wait time and copy-paste overhead.

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
├── sandbox.sh                   # PRIMARY INTERFACE - wrapper for all operations
├── 01-setup-host.sh            # One-time host infrastructure setup
├── 02-create-container.sh      # Creates new LXC container with networking
├── 03-provision-container.sh   # Installs dev stack inside container
└── 04-migrate-project.sh       # Migrates project into container
```

## Usage

**Use `sandbox.sh` for all operations** - it wraps the individual scripts and adds safety features like automatic snapshots.

### Initial Setup (once per VPS)
```bash
# SSH into Hetzner VPS
./01-setup-host.sh
```

### Create New Sandbox
```bash
# Create and provision in one command
sudo ./sandbox.sh create relay-dev tskey-auth-xxxxxxx

# Or without Tailscale (local development only)
sudo ./sandbox.sh create relay-dev --no-tailscale
```

### Migrate Project into Sandbox
```bash
# From git URL
sudo ./sandbox.sh migrate relay-dev https://github.com/user/project.git

# From local directory
sudo ./sandbox.sh migrate relay-dev ~/projects/myproject

# With specific branch
sudo ./sandbox.sh migrate relay-dev https://github.com/user/project.git --branch main

# Force re-migration (overwrites existing)
sudo ./sandbox.sh migrate relay-dev ~/projects/myproject --force
```

Migration automatically:
- Creates pre-migration snapshot (for rollback)
- Copies files (excluding node_modules, .git, dist, build)
- Copies .env file separately (may be gitignored)
- Detects package manager and runs install
- Creates PostgreSQL database
- Runs migrations (Prisma/Drizzle/raw SQL if detected)

### Access Sandbox
```bash
# For Claude Code (use dev user - required for YOLO mode)
ssh dev@relay-dev                    # MagicDNS name
ssh dev@100.64.x.x                   # Direct Tailscale IP
cd ~/projects/<name>
claude --dangerously-skip-permissions

# For admin tasks (root)
ssh root@relay-dev
ssh root@100.64.x.x

# Web access
http://relay-dev:3000                # Web app in browser

# Or via sandbox.sh
./sandbox.sh shell relay-dev         # Opens bash in container
./sandbox.sh info relay-dev          # Shows details and Tailscale IP
```

### Other Operations
```bash
./sandbox.sh list                           # List all sandboxes
./sandbox.sh snapshot relay-dev my-snapshot # Create snapshot
./sandbox.sh restore relay-dev my-snapshot  # Restore (auto-backups first)
./sandbox.sh delete relay-dev               # Delete (prompts for confirmation)
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

All operations use `sandbox.sh` - see Usage section above. Raw `lxc` commands are available if needed:

```bash
lxc list                              # List containers
lxc copy relay-dev relay-template     # Copy as template
lxc exec relay-dev -- bash            # Shell access
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
