# Architecture

**Analysis Date:** 2026-02-01

## Pattern Overview

**Overall:** Sequential infrastructure provisioning pipeline with three distinct phases: host setup, container creation, and stack provisioning.

**Key Characteristics:**
- **Layered execution model**: Each phase is independent and idempotent, designed to be run at different times
- **Isolated environments**: LXC containers provide full Linux isolation with no shared system state
- **Mesh networking**: Tailscale provides direct, encrypted IP addressability without port mapping complexity
- **Declarative configuration**: Bash scripts use preseed configs and explicit config commands rather than interactive prompts

## Layers

**Host Infrastructure Layer (`01-setup-host.sh`):**
- Purpose: Initialize the LXD daemon and networking infrastructure on the Hetzner VPS
- Location: `01-setup-host.sh`
- Contains: OS detection, LXD installation via snap, bridge network creation (lxdbr0 10.10.10.0/24), storage pool initialization, firewall configuration
- Depends on: Root access to host, snapd
- Used by: All container creation operations (depends on lxdbr0 existing)

**Container Lifecycle Layer (`02-create-container.sh`):**
- Purpose: Bootstrap individual LXC containers with basic OS, networking, and resource configuration
- Location: `02-create-container.sh`
- Contains: Container launch from image, TUN device configuration for Tailscale, resource limits (memory/CPU), basic package installation (git, ssh, curl)
- Depends on: Host Infrastructure layer (lxdbr0 must exist), root access to host
- Used by: Provisioning layer (containers must be created before stacks installed)

**Stack Provisioning Layer (`03-provision-container.sh`):**
- Purpose: Install development tools and runtime environments inside running containers
- Location: `03-provision-container.sh`
- Contains: Tailscale client installation, Node.js via nvm, PostgreSQL setup, browser automation tools (Playwright), CLI tools (Claude Code, Convex), shell environment configuration
- Depends on: Container Lifecycle layer, Tailscale auth key, network connectivity
- Used by: Developer operations (manual entry point for post-creation setup)

**Management Interface Layer (`sandbox.sh`):**
- Purpose: Provide developer-friendly CLI wrapper over lower-level operations
- Location: `sandbox.sh`
- Contains: Command dispatch, user confirmation prompts, informational commands (list, info, ip)
- Depends on: All three lower layers (calls 02 and 03, queries 01 results)
- Used by: Human operators

## Data Flow

**Initial Setup Sequence:**

1. Operator runs `01-setup-host.sh` (once per VPS)
   - LXD daemon starts, creates lxdbr0 bridge with DHCP (10.10.10.0/24)
   - NAT rules enable container internet access
   - Firewall configured to allow lxdbr0 traffic
   - `/opt/dev-sandbox/` created for future backups

2. Operator creates container with `02-create-container.sh relay-dev`
   - LXD launches ubuntu:24.04 image as relay-dev
   - Container gets internal IP via DHCP (e.g., 10.10.10.2)
   - TUN device added to container (required for Tailscale)
   - Resource limits applied (4GB RAM, 2 CPU cores)
   - Container waits for network connectivity before returning

3. Operator provisions container with `03-provision-container.sh relay-dev <auth-key>`
   - Tailscale client installs, connects with provided auth key
   - Container receives Tailscale IP (e.g., 100.64.1.5)
   - Node.js, PostgreSQL, Playwright installed via apt/npm
   - Shell environment configured with database credentials and aliases
   - Workspace directory created at ~/workspace

**Runtime Access:**

```
Developer Laptop (Tailscale: 100.64.1.1)
    │
    └── ssh root@relay-dev  ──→  Tailscale mesh  ──→  VPS Tailscale: 100.64.1.5
                                  (encrypted)           │
                                                       LXC: relay-dev
                                                       Internal: 10.10.10.2
                                                       Workspace: ~/workspace
```

**State Management:**

- **Container state**: Managed by LXD (stored in /var/snap/lxd/common/lxd/)
- **Snapshots**: User-initiated via `sandbox.sh snapshot` (stored in LXD snapshot storage)
- **Persistent data**: Lives in container filesystem, survives restart but not deletion
- **Volatile data**: Process state, Tailscale session state (lost on container restart)

## Key Abstractions

**LXC Container:**
- Purpose: Represents a complete isolated Linux environment with dedicated filesystem, network, process namespace
- Examples: relay-dev, project-b, dev-template
- Pattern: Ephemeral by design (can be deleted and recreated), with optional snapshots for recovery

**Tailscale Integration:**
- Purpose: Provides mesh network connectivity with encrypted tunnel between laptop and container
- Examples: Each container runs `tailscale up --authkey=...` to get a 100.x.x.x IP
- Pattern: Reusable auth keys allow multi-container setup; ephemeral keys auto-cleanup on container deletion

**Resource Limits:**
- Purpose: Prevent runaway containers from consuming entire VPS
- Examples: 4GB RAM, 2 CPU cores per container (configurable in `02-create-container.sh`)
- Pattern: Set once at creation time, immutable without container restart

**Dev Stack:**
- Purpose: Common development environment (Node.js, PostgreSQL, Playwright, Claude Code)
- Examples: Installed in Step 3-9 of `03-provision-container.sh`
- Pattern: Modular installation steps, each can be customized independently

## Entry Points

**Host Setup (`01-setup-host.sh`):**
- Location: `/home/claude/projects/lxcsandbox/01-setup-host.sh`
- Triggers: Manual execution once per VPS (`sudo ./01-setup-host.sh`)
- Responsibilities: Install LXD, configure bridge network, set up storage, enable firewall
- Output: Working LXD daemon, lxdbr0 bridge, firewall rules

**Container Creation (`02-create-container.sh`):**
- Location: `/home/claude/projects/lxcsandbox/02-create-container.sh`
- Triggers: Manual execution or called by `sandbox.sh create` (`sudo ./02-create-container.sh <name>`)
- Responsibilities: Launch container from image, add TUN device, set limits, verify connectivity
- Output: Running LXC container with name, internal IP, basic tooling

**Stack Provisioning (`03-provision-container.sh`):**
- Location: `/home/claude/projects/lxcsandbox/03-provision-container.sh`
- Triggers: Manual execution or called by `sandbox.sh create` (`sudo ./03-provision-container.sh <name> <auth-key>`)
- Responsibilities: Install dev tools, configure shell, create workspace
- Output: Container with full dev stack, Tailscale IP, ready for work

**Management CLI (`sandbox.sh`):**
- Location: `/home/claude/projects/lxcsandbox/sandbox.sh`
- Triggers: User commands like `./sandbox.sh create`, `./sandbox.sh shell`
- Responsibilities: Command dispatch, user prompts, information retrieval
- Output: Executed commands or informational output

## Error Handling

**Strategy:** Fail-fast with error messages and exit codes. Each script uses `set -euo pipefail` to catch errors immediately.

**Patterns:**

- **Existence checks**: Verify LXD/container exists before operating on it
  ```bash
  if ! lxc info "$CONTAINER_NAME" &> /dev/null; then
      log_error "Container '$CONTAINER_NAME' does not exist"
      exit 1
  fi
  ```

- **Connectivity validation**: Wait for network before proceeding
  ```bash
  for i in {1..30}; do
      if lxc exec "$CONTAINER_NAME" -- ping -c 1 8.8.8.8 &> /dev/null; then
          log_info "Network connectivity confirmed"
          break
      fi
  done
  ```

- **Package lock handling**: Retry apt operations that fail due to concurrent dpkg locks
  ```bash
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
      sleep 1
  done
  ```

- **Status verification**: Check container status after actions
  ```bash
  if [[ "$(lxc info "$CONTAINER_NAME" | grep 'Status:' | awk '{print $2}')" != "RUNNING" ]]; then
      log_error "Container failed to start"
      exit 1
  fi
  ```

## Cross-Cutting Concerns

**Logging:** Color-coded log functions (log_info, log_warn, log_error, log_step) provide visibility into what's happening. Green for success, yellow for warnings, red for errors.

**Validation:** Container names validated against regex (alphanumeric, hyphens, leading letter). Arguments checked for required values before use.

**Idempotency:** Scripts check for existing state (e.g., "LXD already installed") and skip if already done, allowing re-runs without side effects.

**Confirmation Prompts:** Destructive operations (delete, restore) prompt for confirmation to prevent accidental data loss.

---

*Architecture analysis: 2026-02-01*
