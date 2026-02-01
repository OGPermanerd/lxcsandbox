# Technology Stack

**Analysis Date:** 2026-02-01

## Languages

**Primary:**
- Bash/Shell - Infrastructure provisioning and container management (all `.sh` files)

**Secondary:**
- YAML - LXD configuration in preseed format (embedded in `01-setup-host.sh`)

## Runtime

**Environment:**
- Linux (Ubuntu 22.04, 24.04) - Target OS for both host and containers

**Package Manager:**
- apt-get - Primary package manager for Ubuntu containers
- snap - Used to install LXD on host (`01-setup-host.sh` line 64)
- npm - JavaScript package manager for Node.js packages
- nvm - Node version manager for managing Node.js installations

## Frameworks

**Core Infrastructure:**
- LXD (Linux Container Daemon) - Installed via snap channel `latest/stable` (`01-setup-host.sh` line 64)
  - Version: Latest stable from snap
  - Purpose: Container orchestration and virtual networking
  - Storage backend: btrfs (50GB pool, `01-setup-host.sh` lines 91-95)

**Networking:**
- Tailscale - VPN/mesh networking for container access
  - Installation source: Official install script via curl (`03-provision-container.sh` line 77)
  - Authentication: Reusable auth keys with optional ephemeral mode
  - Provides: Per-container Tailscale IPs in 100.64.x.x range

**Development:**
- Node.js 22 - Installed via nvm (`03-provision-container.sh` lines 102-117)
- PostgreSQL - Database server (`03-provision-container.sh` lines 126-142)

## Key Dependencies

**Critical Infrastructure:**
- snap - For LXD installation (installed in `01-setup-host.sh` if missing)
- curl - HTTP client for downloading install scripts (used in multiple provisioning steps)
- git - Version control system (`02-create-container.sh` line 157, `03-provision-container.sh` line 277)

**Database:**
- PostgreSQL with postgresql-contrib (`03-provision-container.sh` line 127)
  - User credentials: dev/dev (default, configured in `03-provision-container.sh` lines 134-135)
  - Database: dev (created with `CREATE DATABASE dev OWNER dev`)
  - Port: 5432 (standard)

**Development Tools:**
- nvm (Node Version Manager) - Installed from GitHub (`03-provision-container.sh` line 104)
  - Source: `https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh`
  - Manages: Node.js 22 with npm, yarn, pnpm
- Playwright - Browser automation framework (`03-provision-container.sh` lines 188-200)
  - Installed globally: `npm install -g playwright`
  - Browsers: Chromium and Firefox
  - Dependencies: libnss3, libatk1.0-0, libcups2, libxkbcommon0, and ~15 other system libs
- Claude Code CLI - Installed from npm (`03-provision-container.sh` lines 209-214)
  - Package: `@anthropic-ai/claude-code`
  - Mode: Can run with `--dangerously-skip-permissions` flag
- Convex CLI - Backend-as-a-service platform (`03-provision-container.sh` lines 221-228)
  - Package: `convex`

**Build & System Tools:**
- build-essential - Compilation tools for C/C++ dependencies
- python3, python3-pip, python3-venv - Python development environment
- tmux - Terminal multiplexer
- htop - System monitor
- jq - JSON query tool

## Configuration

**Environment Variables:**
- `TAILSCALE_AUTHKEY` - Required for container provisioning (`03-provision-container.sh` line 45)
- `NVM_DIR` - Configured as `$HOME/.nvm` for Node version management
- `PGUSER`, `PGPASSWORD`, `PGDATABASE` - PostgreSQL credentials (dev/dev/dev, `03-provision-container.sh` lines 245-247)
- `DATABASE_URL` - Full PostgreSQL connection string (`postgresql://dev:dev@localhost:5432/dev`)

**Build Configuration Files:**
- LXD preseed config - Embedded in `01-setup-host.sh` (lines 80-111)
  - Bridge network: lxdbr0 (10.10.10.1/24)
  - Storage pool: default (btrfs, 50GB)
  - Default profile with eth0 NIC and root disk

**Host Setup:**
- LXD initializes with UFW firewall rules
- SSH enabled in containers
- systemd service management for PostgreSQL

## Platform Requirements

**Development (Host Machine):**
- Tailscale client installed locally for mesh access
- SSH client for container access
- Optional: MagicDNS enabled in Tailscale for hostname resolution (e.g., `ssh root@relay-dev`)

**Production/Deployment Target:**
- Hetzner VPS (or any Linux server with public IP)
- Minimum: 2GB RAM, 1 vCPU (Recommended: 4GB RAM, 2 vCPU per container)
- Ubuntu 22.04 or 24.04 LTS
- sudo/root access for initial host setup
- Outbound internet access for downloading packages and Tailscale

**Container Runtime Limits (Configurable):**
- Memory: 4GB per container (set in `02-create-container.sh` line 106)
- CPU: 2 cores per container (set in `02-create-container.sh` line 107)
- Storage: 50GB total pool (shared across all containers)

## Special Infrastructure Components

**Virtual Networking:**
- lxdbr0 bridge network (10.10.10.0/24) - Created by LXD, managed automatically
  - IPv4 NAT enabled for internet access from containers
  - IPv6 disabled
- Tailscale virtual network - Provides encrypted mesh and per-container IPs
  - No port mapping needed - each container has unique IP

**Storage:**
- btrfs filesystem for LXD storage pool (snapshots, container images)
- Snapshot support for quick rollback before risky operations

---

*Stack analysis: 2026-02-01*
