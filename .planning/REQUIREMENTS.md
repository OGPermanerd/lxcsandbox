# Requirements: Dev Sandbox Infrastructure

**Defined:** 2026-02-01
**Core Value:** Complete isolation between projects for autonomous Claude Code operation

## v1 Requirements

Requirements for getting the sandbox infrastructure working end-to-end.

### Host Setup

- [x] **HOST-01**: Script detects Ubuntu version and validates compatibility
- [x] **HOST-02**: Script installs LXD via snap if not present
- [x] **HOST-03**: Script creates lxdbr0 bridge network with 10.10.10.0/24 subnet
- [x] **HOST-04**: Script enables NAT for container internet access
- [x] **HOST-05**: Script creates btrfs storage pool for containers
- [x] **HOST-06**: Script configures UFW firewall to allow LXD traffic

### Container Creation

- [ ] **CONT-01**: Script accepts container name as argument
- [ ] **CONT-02**: Script validates container name format
- [ ] **CONT-03**: Script launches Ubuntu 24.04 container from image
- [ ] **CONT-04**: Script adds TUN device to container for Tailscale
- [ ] **CONT-05**: Script sets memory limit (4GB default)
- [ ] **CONT-06**: Script sets CPU limit (2 cores default)
- [ ] **CONT-07**: Script waits for container network connectivity
- [ ] **CONT-08**: Script installs basic packages (curl, git, ssh)

### Stack Provisioning

- [ ] **PROV-01**: Script accepts container name and Tailscale auth key
- [ ] **PROV-02**: Script installs Tailscale client in container
- [ ] **PROV-03**: Script connects Tailscale with provided auth key
- [ ] **PROV-04**: Script verifies Tailscale IP is assigned
- [ ] **PROV-05**: Script installs nvm and Node.js 22
- [ ] **PROV-06**: Script installs npm, yarn, pnpm
- [ ] **PROV-07**: Script installs PostgreSQL server
- [ ] **PROV-08**: Script creates dev user/password/database
- [ ] **PROV-09**: Script installs Playwright with Chromium and Firefox
- [ ] **PROV-10**: Script installs Claude Code CLI
- [ ] **PROV-11**: Script configures shell with database env vars and aliases

### Management CLI

- [ ] **MGMT-01**: sandbox.sh create command runs 02 + 03 scripts
- [ ] **MGMT-02**: sandbox.sh shell command opens bash in container
- [ ] **MGMT-03**: sandbox.sh list command shows all containers
- [ ] **MGMT-04**: sandbox.sh snapshot command creates named snapshot
- [ ] **MGMT-05**: sandbox.sh restore command restores from snapshot
- [ ] **MGMT-06**: sandbox.sh delete command removes container with confirmation
- [ ] **MGMT-07**: sandbox.sh info command shows container details and IPs

## v2 Requirements

Deferred to future release after basic workflow is validated.

### Templates

- **TMPL-01**: Create template container with pre-installed stack
- **TMPL-02**: Clone from template for faster spinup

### Backup

- **BKUP-01**: Export container to tarball
- **BKUP-02**: Upload to Hetzner object storage
- **BKUP-03**: Restore from backup

### Advanced

- **ADVN-01**: Configurable resource limits via CLI flags
- **ADVN-02**: Multiple container profiles (minimal, full)
- **ADVN-03**: MCP tool for Claude-driven sandbox management

## Out of Scope

| Feature | Reason |
|---------|--------|
| Docker support | LXC chosen for full Linux environment |
| GPU passthrough | Not needed for current dev work |
| Multi-host clustering | Single VPS is sufficient |
| Windows containers | Linux-only workflow |
| Automated testing | Manual validation sufficient for infra scripts |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| HOST-01 | Phase 1 | Complete |
| HOST-02 | Phase 1 | Complete |
| HOST-03 | Phase 1 | Complete |
| HOST-04 | Phase 1 | Complete |
| HOST-05 | Phase 1 | Complete |
| HOST-06 | Phase 1 | Complete |
| CONT-01 | Phase 2 | Pending |
| CONT-02 | Phase 2 | Pending |
| CONT-03 | Phase 2 | Pending |
| CONT-04 | Phase 2 | Pending |
| CONT-05 | Phase 2 | Pending |
| CONT-06 | Phase 2 | Pending |
| CONT-07 | Phase 2 | Pending |
| CONT-08 | Phase 2 | Pending |
| PROV-01 | Phase 3 | Pending |
| PROV-02 | Phase 3 | Pending |
| PROV-03 | Phase 3 | Pending |
| PROV-04 | Phase 3 | Pending |
| PROV-05 | Phase 3 | Pending |
| PROV-06 | Phase 3 | Pending |
| PROV-07 | Phase 3 | Pending |
| PROV-08 | Phase 3 | Pending |
| PROV-09 | Phase 3 | Pending |
| PROV-10 | Phase 3 | Pending |
| PROV-11 | Phase 3 | Pending |
| MGMT-01 | Phase 4 | Pending |
| MGMT-02 | Phase 4 | Pending |
| MGMT-03 | Phase 4 | Pending |
| MGMT-04 | Phase 4 | Pending |
| MGMT-05 | Phase 4 | Pending |
| MGMT-06 | Phase 4 | Pending |
| MGMT-07 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 32 total
- Mapped to phases: 32
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-01*
*Last updated: 2026-02-01 after Phase 1 completion*
