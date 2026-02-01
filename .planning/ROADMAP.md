# Roadmap: Dev Sandbox Infrastructure

## Overview

Transform untested shell scripts into a working LXC-based sandbox infrastructure. Starting with host setup, progressing through container creation and provisioning, and finishing with a management CLI that orchestrates the complete workflow. Each phase delivers a testable capability that enables the next.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Host Infrastructure** - LXD installation and network setup on Hetzner VPS
- [x] **Phase 2: Container Creation** - Launch isolated LXC containers with networking
- [x] **Phase 3: Stack Provisioning** - Install complete dev stack in containers
- [x] **Phase 4: Management CLI** - User-facing commands for sandbox operations
- [ ] **Phase 5: Tech Debt Cleanup** - Fix minor issues from milestone audit

## Phase Details

### Phase 1: Host Infrastructure
**Goal**: VPS is configured with LXD and ready to host containers
**Depends on**: Nothing (first phase)
**Requirements**: HOST-01, HOST-02, HOST-03, HOST-04, HOST-05, HOST-06
**Success Criteria** (what must be TRUE):
  1. Host detects Ubuntu version and validates compatibility before proceeding
  2. LXD is installed and lxdbr0 bridge network exists with 10.10.10.0/24 subnet
  3. Containers can reach internet through NAT
  4. btrfs storage pool is created and available for container images
  5. UFW firewall allows LXD traffic without blocking container networking
**Plans**: 1 plan

Plans:
- [x] 01-01-PLAN.md - Rewrite 01-setup-host.sh with full idempotency and safety checks

### Phase 2: Container Creation
**Goal**: Script can launch new LXC containers with proper isolation and networking
**Depends on**: Phase 1
**Requirements**: CONT-01, CONT-02, CONT-03, CONT-04, CONT-05, CONT-06, CONT-07, CONT-08
**Success Criteria** (what must be TRUE):
  1. User can run script with container name and receive a running Ubuntu 24.04 container
  2. Container has TUN device for Tailscale networking
  3. Container has resource limits applied (4GB soft memory, host CPU cores)
  4. Container has network connectivity and basic packages installed (curl, git, ssh)
  5. Script validates container name format and reports errors for invalid names
**Plans**: 1 plan

Plans:
- [x] 02-01-PLAN.md - Create container creation script with validation, resource limits, TUN device

### Phase 3: Stack Provisioning
**Goal**: Script installs complete dev stack and connects container to Tailscale
**Depends on**: Phase 2
**Requirements**: PROV-01, PROV-02, PROV-03, PROV-04, PROV-05, PROV-06, PROV-07, PROV-08, PROV-09, PROV-10, PROV-11
**Success Criteria** (what must be TRUE):
  1. Container is connected to Tailscale with unique 100.64.x.x IP address
  2. Node.js 22 is installed via nvm with npm, yarn, and pnpm available
  3. PostgreSQL is running with dev/dev credentials and dev database created
  4. Playwright is installed with Chromium and Firefox browsers ready
  5. Claude Code CLI is installed and accessible in PATH
  6. Shell has database environment variables and useful aliases configured
**Plans**: 1 plan

Plans:
- [x] 03-01-PLAN.md - Create provisioning script with Tailscale, Node.js, PostgreSQL, Playwright, Claude Code

### Phase 4: Management CLI
**Goal**: User has simple CLI commands for all sandbox operations
**Depends on**: Phase 3
**Requirements**: MGMT-01, MGMT-02, MGMT-03, MGMT-04, MGMT-05, MGMT-06, MGMT-07
**Success Criteria** (what must be TRUE):
  1. User can create complete sandbox with single command that runs setup and provisioning
  2. User can open shell in any container, list all containers, and view container details
  3. User can create named snapshots and restore from them
  4. User can delete containers with confirmation prompt to prevent accidents
  5. sandbox.sh info command shows Tailscale IP and connection instructions
**Plans**: 1 plan

Plans:
- [x] 04-01-PLAN.md - Update sandbox.sh with all CLI commands per CONTEXT.md decisions

### Phase 5: Tech Debt Cleanup
**Goal**: Clean up minor issues identified in milestone audit
**Depends on**: Phase 4
**Requirements**: None (polish, not requirements)
**Gap Closure**: Addresses tech debt from v1.0-MILESTONE-AUDIT.md
**Success Criteria** (what must be TRUE):
  1. All scripts are executable (chmod +x applied)
  2. 02-create-container.sh validates LXD is available before operations
  3. 03-provision-container.sh validates TUN device before Tailscale install
  4. No dead code (unused functions removed)
**Plans**: TBD

Plans:
- [ ] (Plans to be created during planning phase)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Host Infrastructure | 1/1 | Complete | 2026-02-01 |
| 2. Container Creation | 1/1 | Complete | 2026-02-01 |
| 3. Stack Provisioning | 1/1 | Complete | 2026-02-01 |
| 4. Management CLI | 1/1 | Complete | 2026-02-01 |
| 5. Tech Debt Cleanup | 0/TBD | Not started | - |
