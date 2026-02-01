# External Integrations

**Analysis Date:** 2026-02-01

## APIs & External Services

**Tailscale Mesh Network:**
- Tailscale - Encrypted VPN mesh and container discovery
  - What it's used for: Per-container IP assignment, NAT traversal, direct access from developer laptops
  - SDK/Client: Official curl-based installer via `https://tailscale.com/install.sh`
  - Auth: Environment variable `TAILSCALE_AUTHKEY` (reusable ephemeral auth keys)
  - Installation: `03-provision-container.sh` lines 74-89
  - Status check: `tailscale status` and `tailscale ip -4` commands
  - MagicDNS: Optional hostname resolution (e.g., `ssh root@relay-dev`)

**Package Registries:**
- npm (npmjs.com) - JavaScript package registry
  - Used for: Node.js packages (npm, yarn, pnpm, global tools)
  - Packages installed:
    - `@anthropic-ai/claude-code` - Claude Code CLI
    - `convex` - Backend-as-a-service
    - `playwright` - Browser automation
  - Installation: Via nvm/npm in `03-provision-container.sh` lines 102-228
- Ubuntu apt repositories - System packages
  - Source: Standard Ubuntu package mirrors
  - Used for: PostgreSQL, build tools, system libraries, Python

**Version Control:**
- GitHub (nvm repository) - Node version manager distribution
  - Source URL: `https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh`
  - Used for: Installing Node.js version manager
  - Installation: `03-provision-container.sh` line 104

## Data Storage

**Databases:**

**PostgreSQL:**
- Type: SQL database
- Connection: localhost:5432 (standard PostgreSQL port)
- Client: Built-in `psql` command-line tool
- Credentials:
  - User: `dev`
  - Password: `dev`
  - Database: `dev`
  - Connection string: `postgresql://dev:dev@localhost:5432/dev`
- Configuration:
  - Configured in: `03-provision-container.sh` lines 126-142
  - Host auth methods: md5 for local connections
  - Startup: Enabled via systemd (`systemctl enable postgresql`)
- Environment variables set for all containers:
  - `PGUSER=dev`
  - `PGPASSWORD=dev`
  - `PGDATABASE=dev`
  - `DATABASE_URL=postgresql://dev:dev@localhost:5432/dev`

**Storage:**
- Type: Local filesystem (inside LXC container and host)
- Backend: btrfs storage pool on host (50GB, `01-setup-host.sh` lines 91-95)
- Use cases:
  - Container root filesystem
  - Container snapshots (LXD snapshot feature)
  - Application data (stored in container /root/workspace)

**Caching:**
- None detected - applications use in-memory caching only

## Authentication & Identity

**Auth Provider:**
- Tailscale - Provides per-container device authentication
  - Implementation: Tailscale auth keys (reusable + ephemeral mode)
  - Admin console: https://login.tailscale.com/admin/settings/keys
  - Container auth: Each container authenticates with unique auth key during provisioning
  - No traditional username/password authentication configured

**SSH Access:**
- Public key infrastructure (standard SSH)
- SSH server enabled in all containers (`02-create-container.sh` line 164)
- Root user access by default
- SSH port: 22 (standard)
- Access methods:
  - Direct: `ssh root@<container-internal-ip>` from host
  - Via Tailscale: `ssh root@<tailscale-ip>` from laptop
  - Via MagicDNS: `ssh root@<container-name>` with Tailscale MagicDNS enabled

## Monitoring & Observability

**Error Tracking:**
- Not detected - no error tracking service configured

**Logs:**
- Systemd journalctl - Standard Linux logging
  - Access: `journalctl -u tailscaled` for Tailscale diagnostics
  - Access: `journalctl` for general system logs
  - PostgreSQL logs: Default systemd journal integration
- Application stdout/stderr - Captured via lxc exec output

**Diagnostic Commands:**
- `lxc exec <name> -- tailscale status` - Show Tailscale connection status
- `lxc exec <name> -- journalctl -u tailscaled` - Tailscale daemon logs
- `lxc info <name>` - Container status and resource usage
- `lxc list` - All containers and their IPs

## CI/CD & Deployment

**Hosting:**
- Hetzner VPS (https://www.hetzner.com/)
  - Typical cost: $4-20/month for a single server
  - Configuration: Single public IPv4, runs LXD host infrastructure

**CI Pipeline:**
- Not detected - no CI/CD system configured in infrastructure
- Each sandbox can run its own local development, testing, or deployment operations via Claude Code CLI

**Repository Integration:**
- Git is installed in all containers (`02-create-container.sh` line 157)
- Global git configuration in `03-provision-container.sh` lines 277-279:
  - Default branch: main
  - User email: dev@sandbox.local
  - User name: Dev Sandbox

## Environment Configuration

**Required Environment Variables (For Provisioning):**
- `TAILSCALE_AUTHKEY` - Mandatory for `03-provision-container.sh` script
  - Format: `tskey-auth-XXXXXX...` (reusable auth key from Tailscale admin)
  - Sourcing: https://login.tailscale.com/admin/settings/keys

**Container Runtime Environment Variables:**
- `NVM_DIR=$HOME/.nvm` - Node version manager directory
- `PGUSER=dev` - PostgreSQL user
- `PGPASSWORD=dev` - PostgreSQL password
- `PGDATABASE=dev` - Default database name
- `DATABASE_URL=postgresql://dev:dev@localhost:5432/dev` - Full connection string

**Secrets Location:**
- PostgreSQL credentials: Hardcoded in provisioning script (development default)
- Tailscale auth key: Passed as command-line argument during provisioning
- SSH keys: Generated by SSH daemon on first boot, stored in `/etc/ssh/`
- No centralized secrets management configured

**Development Access:**
- Tailscale auth keys configured with:
  - Reusable: Yes (allows multiple containers from single key)
  - Ephemeral: Yes (recommended, auto-removes device on container deletion)
  - Tags: Optional `tag:dev-sandbox` for ACL policies

## Webhooks & Callbacks

**Incoming Webhooks:**
- Not detected - no webhook endpoints configured

**Outgoing Webhooks:**
- Not detected - no outgoing webhooks configured

**Event-Based Triggers:**
- Container lifecycle managed via LXD API/CLI only
- No webhook or pub/sub system detected

## Network Configuration

**Firewall Rules (Host Level):**
- UFW (Uncomplicated Firewall) - Configured in `01-setup-host.sh` lines 130-151
  - SSH: Allow 22/tcp
  - Tailscale: Allow 41641/udp
  - LXD bridge (lxdbr0): Allow all traffic on bridge interface

**Port Allocation (Per Container):**
- Port 3000: Default Node.js application port
- Port 5432: PostgreSQL database
- Port 5173: Typical Vite dev server port
- Other ports: Available as needed (no conflicts between containers due to separate IPs)

**Network Architecture:**
```
Developer Laptop (Tailscale IP: 100.64.x.1)
    ↓ (encrypted Tailscale tunnel)
Hetzner VPS (Public IP: single static IP)
    ↓
Host OS (Ubuntu 24.04)
    ├── Tailscale daemon (optional on host)
    ├── LXD daemon (manages containers)
    └── lxdbr0 bridge (10.10.10.0/24)
        ├── Container 1: relay-dev
        │   ├── Internal IP: 10.10.10.x (DHCP)
        │   └── Tailscale IP: 100.64.x.5
        └── Container 2: project-b
            ├── Internal IP: 10.10.10.y (DHCP)
            └── Tailscale IP: 100.64.x.6
```

---

*Integration audit: 2026-02-01*
