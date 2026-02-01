# Roadmap: Dev Sandbox Infrastructure

## Milestones

- v1.0 MVP - Phases 1-5 (shipped 2026-02-01)
- **v1.1 Project Migration** - Phases 6-9 (in progress)

## Overview

v1.1 adds project migration capabilities to the existing sandbox infrastructure. Starting with file transfer (git clone or local copy), progressing through Node.js dependency installation and database setup, and finishing with full CLI integration. Each phase delivers a testable capability that enables the next.

## Phases

<details>
<summary>v1.0 MVP (Phases 1-5) - SHIPPED 2026-02-01</summary>

See: .planning/milestones/v1.0-ROADMAP.md

- [x] **Phase 1: Host Infrastructure** - LXD setup with bridge network and storage
- [x] **Phase 2: Container Creation** - LXC containers with isolation and networking
- [x] **Phase 3: Stack Provisioning** - Tailscale, Node.js, PostgreSQL, Playwright, Claude Code
- [x] **Phase 4: Management CLI** - sandbox.sh with create, shell, list, snapshot, restore, delete, info
- [x] **Phase 5: Tech Debt Cleanup** - Defensive checks and dead code removal

</details>

### v1.1 Project Migration (In Progress)

**Milestone Goal:** Migrate existing Node.js projects into isolated LXC sandboxes with automated environment setup.

- [x] **Phase 6: Core Transfer** - Get project files into containers via git clone or local copy
- [ ] **Phase 7: Node.js Setup** - Install correct Node version and project dependencies
- [ ] **Phase 8: Database Integration** - Create PostgreSQL database and run migrations
- [ ] **Phase 9: CLI Integration** - Polish sandbox.sh migrate command and user experience

## Phase Details

### Phase 6: Core Transfer

**Goal**: Project files are transferred into container with environment preserved
**Depends on**: Phase 5 (v1.0 complete)
**Requirements**: SRC-01, SRC-02, SRC-03, SRC-04, SRC-05, ENV-01, ENV-05
**Plans:** 1 plan
**Success Criteria** (what must be TRUE):
  1. User can run migrate command with git URL and code appears in `/root/projects/<name>`
  2. User can run migrate command with local directory path and code appears in container
  3. User can specify `--branch` flag to clone specific branch or tag
  4. Local directory copy excludes node_modules and .git (never copies build artifacts)
  5. .env file from source is copied to container project directory

Plans:
- [x] 06-01-PLAN.md - Create 04-migrate-project.sh with source detection and file transfer

### Phase 7: Node.js Setup

**Goal**: Project dependencies are installed with correct Node version and package manager
**Depends on**: Phase 6
**Requirements**: NODE-01, NODE-02, NODE-03, NODE-04, ENV-02
**Success Criteria** (what must be TRUE):
  1. Script detects package manager from lockfile (npm/yarn/pnpm) and uses correct install command
  2. Script detects .nvmrc and installs specified Node version if different from default
  3. node_modules directory exists after migration with all dependencies installed
  4. If no .env exists but .env.example does, it is copied as .env
**Plans**: TBD

Plans:
- [ ] 07-01: Add package manager detection and dependency installation to migrate script

### Phase 8: Database Integration

**Goal**: PostgreSQL database is created and migrations are executed
**Depends on**: Phase 7
**Requirements**: DB-01, DB-02, DB-03, DB-04, DB-05, DB-06, DB-07, ENV-03, ENV-04
**Success Criteria** (what must be TRUE):
  1. Script creates PostgreSQL database with sanitized project name
  2. DATABASE_URL environment variable is generated and appended to .env
  3. Prisma projects have migrations applied via `prisma migrate deploy`
  4. Drizzle projects have schema pushed via `drizzle-kit push`
  5. Raw SQL migrations in migrations/ directory are executed in alphabetical order
**Plans**: TBD

Plans:
- [ ] 08-01: Add database creation and migration runner to migrate script

### Phase 9: CLI Integration

**Goal**: User has polished migrate command with safety features and clear feedback
**Depends on**: Phase 8
**Requirements**: SRC-06, CLI-01, CLI-02, CLI-03, CLI-04, CLI-05
**Success Criteria** (what must be TRUE):
  1. `sandbox.sh migrate <container> <source>` command works end-to-end
  2. Pre-migration snapshot is created automatically before any changes
  3. If project already exists in container, user is offered re-migration options
  4. Migration outputs clear success/error messages with next steps
  5. Migration summary shows detected tools and actions taken
**Plans**: TBD

Plans:
- [ ] 09-01: Integrate migrate command into sandbox.sh with UX polish

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Host Infrastructure | v1.0 | 1/1 | Complete | 2026-02-01 |
| 2. Container Creation | v1.0 | 1/1 | Complete | 2026-02-01 |
| 3. Stack Provisioning | v1.0 | 1/1 | Complete | 2026-02-01 |
| 4. Management CLI | v1.0 | 1/1 | Complete | 2026-02-01 |
| 5. Tech Debt Cleanup | v1.0 | 1/1 | Complete | 2026-02-01 |
| 6. Core Transfer | v1.1 | 1/1 | Complete | 2026-02-01 |
| 7. Node.js Setup | v1.1 | 0/1 | Not started | - |
| 8. Database Integration | v1.1 | 0/1 | Not started | - |
| 9. CLI Integration | v1.1 | 0/1 | Not started | - |

## Requirement Coverage

All 27 v1.1 requirements mapped:

| Phase | Requirements | Count |
|-------|--------------|-------|
| Phase 6 | SRC-01, SRC-02, SRC-03, SRC-04, SRC-05, ENV-01, ENV-05 | 7 |
| Phase 7 | NODE-01, NODE-02, NODE-03, NODE-04, ENV-02 | 5 |
| Phase 8 | DB-01, DB-02, DB-03, DB-04, DB-05, DB-06, DB-07, ENV-03, ENV-04 | 9 |
| Phase 9 | SRC-06, CLI-01, CLI-02, CLI-03, CLI-04, CLI-05 | 6 |
| **Total** | | **27** |

---

*Created: 2026-02-01 for v1.1 milestone*
