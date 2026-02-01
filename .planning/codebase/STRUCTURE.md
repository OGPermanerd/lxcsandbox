# Codebase Structure

**Analysis Date:** 2026-02-01

## Directory Layout

```
lxcsandbox/
├── 01-setup-host.sh            # Host infrastructure initialization
├── 02-create-container.sh      # LXC container creation
├── 03-provision-container.sh   # Development stack installation
├── sandbox.sh                  # CLI management wrapper
├── CLAUDE.md                   # Detailed project context for Claude Code
├── CONTEXT.md                  # Architecture and problem statement overview
├── README.md                   # User-facing documentation
└── .planning/codebase/         # Analysis documents (this directory)
    ├── ARCHITECTURE.md         # This file
    └── STRUCTURE.md            # Codebase layout
```

## Directory Purposes

**Repository Root:**
- Purpose: Contains all infrastructure-as-code for LXC sandbox management
- Contains: Bash scripts for provisioning, documentation files, git metadata
- Key files: All four shell scripts, three markdown documentation files

**`.planning/codebase/`:**
- Purpose: Stores codebase analysis documents for the GSD orchestrator
- Contains: Architecture analysis, structure documentation, conventions, testing patterns, concerns
- Generated: These documents are written by the GSD mapper, not committed to repo originally

## Key File Locations

**Entry Points:**

- `01-setup-host.sh`: Host one-time setup (must be first, run as root)
  ```bash
  sudo ./01-setup-host.sh
  ```

- `02-create-container.sh`: Create new container (run as root, after host setup)
  ```bash
  sudo ./02-create-container.sh <name>
  ```

- `03-provision-container.sh`: Provision container stack (run as root, after creation)
  ```bash
  sudo ./03-provision-container.sh <name> <tailscale-authkey>
  ```

- `sandbox.sh`: Developer CLI wrapper (run as root or from host, unified entry point)
  ```bash
  ./sandbox.sh <command> [args]
  ```

**Configuration:**

- No dedicated config files. Configuration is embedded in scripts:
  - LXD preseed config: Lines 80-111 in `01-setup-host.sh`
  - Resource limits: Lines 106-109 in `02-create-container.sh` (4GB RAM, 2 CPU)
  - Node.js version: Line 110 in `03-provision-container.sh` (nvm install 22)
  - PostgreSQL credentials: Lines 134-135 in `03-provision-container.sh` (user: dev, pass: dev)

**Core Logic:**

- `01-setup-host.sh`: LXD initialization, bridge network creation, storage setup
- `02-create-container.sh`: Container image launch, TUN device configuration, connectivity verification
- `03-provision-container.sh`: Tailscale installation, dev tool stacks, shell environment setup
- `sandbox.sh`: Dispatcher for common operations (create, delete, shell, snapshot, restore, info, ip, list)

**Documentation:**

- `README.md`: User guide with quick start, command reference, architecture diagram
- `CLAUDE.md`: Detailed project context including problem statement, implementation details, troubleshooting
- `CONTEXT.md`: Summary of problem, solution, and three-phase implementation

## Naming Conventions

**Files:**

- Scripts: Numbered phase sequence: `01-setup-host.sh`, `02-create-container.sh`, `03-provision-container.sh`
  - Pattern: `NN-description.sh` where NN is execution order
  - Exception: `sandbox.sh` is a management CLI, not a phase

- Documentation: Uppercase descriptive names: `README.md`, `CLAUDE.md`, `CONTEXT.md`
  - Pattern: Explains itself without abbreviation

**Directories:**

- Script directory (root): Contains all executable scripts and docs together
- Hidden directory `.planning/`: GSD-specific analysis documents

**Functions:**

Within scripts:

- Logging functions: `log_info()`, `log_warn()`, `log_error()`, `log_step()`
  - Pattern: `log_<level>() { echo -e ... }` with color codes

- Command functions in `sandbox.sh`: `cmd_<command>()`
  - Examples: `cmd_list()`, `cmd_create()`, `cmd_shell()`, `cmd_snapshot()`, `cmd_restore()`, `cmd_info()`, `cmd_ip()`
  - Pattern: Each command has a dedicated function, dispatched via case statement

**Variables:**

- Script-wide configuration: UPPERCASE with underscores
  - Examples: `CONTAINER_NAME`, `UBUNTU_VERSION`, `TAILSCALE_KEY`, `TAILSCALE_IP`, `INTERNAL_IP`

- Local/temporary variables: lowercase with underscores
  - Examples: `name`, `label`, `confirm`, `ts_key`

- Color codes: UPPERCASE with NC suffix
  - Examples: `RED`, `GREEN`, `YELLOW`, `CYAN`, `NC` (no color)

## Where to Add New Code

**New Command/Operation:**
1. Add logic to existing script or create new shell file
2. If adding to `sandbox.sh`, follow the pattern:
   - Create `cmd_<name>()` function
   - Add case statement entry
   - Add help text entry in `show_help()`
3. Keep scripts at repo root, named semantically (e.g., `04-backup-container.sh`)

**Customization Points:**

- **Change resource limits**: Edit `02-create-container.sh` lines 106-109
  ```bash
  lxc config set "$CONTAINER_NAME" limits.memory=8GB
  lxc config set "$CONTAINER_NAME" limits.cpu=4
  ```

- **Add packages to provisioning**: Edit `03-provision-container.sh` appropriate section:
  - System packages: Lines 153-161 (apt-get)
  - Browser automation: Lines 164-180 (playwright deps)
  - Node packages: Lines 115-116, 195 (npm -g)

- **Change Node.js version**: Edit `03-provision-container.sh` line 110
  ```bash
  nvm install 22  # Change to desired version
  ```

- **Change PostgreSQL version**: Edit `03-provision-container.sh` line 127
  ```bash
  apt-get install -y postgresql postgresql-contrib  # Default latest
  ```

- **Modify shell environment**: Edit `03-provision-container.sh` lines 237-265 (bashrc additions)

- **Change base OS image**: Edit `02-create-container.sh` line 43
  ```bash
  IMAGE="ubuntu:${UBUNTU_VERSION}"  # Change distribution
  ```

**New Feature Pattern:**

If adding a feature requiring changes across multiple scripts:

1. Update `01-setup-host.sh` if host-level infrastructure needed
2. Update `02-create-container.sh` if container-level config needed
3. Update `03-provision-container.sh` if stack packages needed
4. Add corresponding `cmd_` function to `sandbox.sh` if user-facing operation
5. Document in README.md under "Commands" or "Customization"

## Special Directories

**Host System (outside scripts):**
- `/opt/dev-sandbox/`: Created by `01-setup-host.sh` line 172 for future backups/helpers
  - Purpose: Central location for backup and helper scripts on the host
  - Generated: Yes, at setup time
  - Committed: No, created at runtime

**Container Filesystem (inside containers):**
- `~/workspace`: Created by `03-provision-container.sh` line 275 for project code
  - Purpose: Standard location for git clones and project work
  - Generated: Yes, at provisioning time
  - Committed: No, user-created files live here

**LXD Storage:**
- `/var/snap/lxd/common/lxd/`: Default LXD data directory (host system)
  - Purpose: Contains all container filesystems, snapshots, config
  - Generated: Yes, by LXD snap installation
  - Committed: No, runtime data only

**Snapshots:**
- Stored within LXD database, not as separate files
- Created via `lxc snapshot <name> <label>` commands
- Listed via `lxc info <name> | grep -A Snapshots:`
- Restored via `lxc restore <name> <label>`

## Script Execution Flow

**One-time host setup:**
```
01-setup-host.sh (manual)
  ├── Detect OS
  ├── Update packages
  ├── Install LXD via snap
  ├── Initialize LXD with preseed config
  ├── Install firewall + utilities
  ├── Optional: Install Tailscale on host
  └── Create /opt/dev-sandbox directory
```

**Per-container creation:**
```
02-create-container.sh (manual or called by sandbox.sh)
  ├── Validate container name
  ├── Launch ubuntu:24.04 image
  ├── Add TUN device for Tailscale
  ├── Set resource limits (4GB, 2CPU)
  ├── Restart to apply config
  ├── Wait for network connectivity
  ├── Install basic packages (curl, git, ssh)
  └── Display container info
```

**Per-container provisioning:**
```
03-provision-container.sh (manual or called by sandbox.sh)
  ├── Verify container exists and running
  ├── Install Tailscale, connect with auth key
  ├── Install Node.js 22 via nvm
  ├── Install PostgreSQL with dev user
  ├── Install development tools (build-essential, python3)
  ├── Install Playwright + browser deps
  ├── Install Claude Code CLI
  ├── Install Convex CLI
  ├── Configure shell environment (.bashrc)
  ├── Create ~/workspace directory
  └── Display Tailscale IP and access info
```

**Management operations:**
```
sandbox.sh <command> (manual, interactive)
  ├── list: Call lxc list with formatted output
  ├── create: Prompt for name, call 02-create, call 03-provision
  ├── delete: Confirm, call lxc delete --force
  ├── shell: Call lxc exec <name> -- bash -l
  ├── snapshot: Call lxc snapshot with label
  ├── restore: Confirm, call lxc restore with label
  ├── info: Display lxc list, Tailscale IP, snapshots
  ├── ip: Call lxc exec <name> -- tailscale ip -4
  └── help: Display command list
```

---

*Structure analysis: 2026-02-01*
