# Requirements: v1.1 Project Migration

**Defined:** 2026-02-01
**Core Value:** Migrate existing Node.js projects into isolated LXC sandboxes with automated environment setup

## v1.1 Requirements

Requirements for migrating existing projects into containers with full environment setup.

### Source Handling (SRC)

- [x] **SRC-01**: Script accepts git repository URL as source
- [x] **SRC-02**: Script accepts local directory path as source
- [x] **SRC-03**: Script supports git branch/tag specification with `--branch` flag
- [x] **SRC-04**: Script clones git repos to `/root/projects/<name>` in container
- [x] **SRC-05**: Script copies local directories via rsync (excludes node_modules, .git)
- [ ] **SRC-06**: Script detects if project already exists and offers re-migration options

### Node.js Setup (NODE)

- [x] **NODE-01**: Script detects package manager from lock files (npm/yarn/pnpm)
- [x] **NODE-02**: Script runs appropriate install command (npm install, yarn, pnpm install)
- [x] **NODE-03**: Script detects .nvmrc and installs specified Node version if different
- [x] **NODE-04**: Script verifies node_modules exists after install

### Environment Setup (ENV)

- [x] **ENV-01**: Script copies .env file from source to container
- [x] **ENV-02**: Script falls back to .env.example if .env missing
- [ ] **ENV-03**: Script generates DATABASE_URL for PostgreSQL connection
- [ ] **ENV-04**: Script appends DATABASE_URL to .env if not present
- [x] **ENV-05**: Script preserves existing environment variables unchanged

### Database Integration (DB)

- [ ] **DB-01**: Script creates PostgreSQL database with sanitized project name
- [ ] **DB-02**: Script detects Prisma by presence of prisma/ directory
- [ ] **DB-03**: Script detects Drizzle by presence of drizzle/ or drizzle.config.*
- [ ] **DB-04**: Script runs `npx prisma migrate deploy` for Prisma projects
- [ ] **DB-05**: Script runs `npx drizzle-kit push` for Drizzle projects
- [ ] **DB-06**: Script detects raw SQL migrations in migrations/ directory
- [ ] **DB-07**: Script runs raw SQL migrations in alphabetical order

### CLI Integration (CLI)

- [ ] **CLI-01**: sandbox.sh migrate command accepts container name and source
- [ ] **CLI-02**: sandbox.sh migrate calls 04-migrate-project.sh backend
- [ ] **CLI-03**: Script creates pre-migration snapshot automatically
- [ ] **CLI-04**: Script outputs clear success/error messages with next steps
- [ ] **CLI-05**: Script provides migration summary (detected tools, actions taken)

## Traceability

| Requirement | Phase | Priority | Status |
|-------------|-------|----------|--------|
| SRC-01 | Phase 6 | Must Have | Complete |
| SRC-02 | Phase 6 | Must Have | Complete |
| SRC-03 | Phase 6 | Must Have | Complete |
| SRC-04 | Phase 6 | Must Have | Complete |
| SRC-05 | Phase 6 | Must Have | Complete |
| SRC-06 | Phase 9 | Should Have | Pending |
| NODE-01 | Phase 7 | Must Have | Complete |
| NODE-02 | Phase 7 | Must Have | Complete |
| NODE-03 | Phase 7 | Should Have | Complete |
| NODE-04 | Phase 7 | Must Have | Complete |
| ENV-01 | Phase 6 | Must Have | Complete |
| ENV-02 | Phase 7 | Should Have | Complete |
| ENV-03 | Phase 8 | Must Have | Pending |
| ENV-04 | Phase 8 | Must Have | Pending |
| ENV-05 | Phase 6 | Must Have | Complete |
| DB-01 | Phase 8 | Must Have | Pending |
| DB-02 | Phase 8 | Must Have | Pending |
| DB-03 | Phase 8 | Must Have | Pending |
| DB-04 | Phase 8 | Must Have | Pending |
| DB-05 | Phase 8 | Must Have | Pending |
| DB-06 | Phase 8 | Should Have | Pending |
| DB-07 | Phase 8 | Should Have | Pending |
| CLI-01 | Phase 9 | Must Have | Pending |
| CLI-02 | Phase 9 | Must Have | Pending |
| CLI-03 | Phase 9 | Must Have | Pending |
| CLI-04 | Phase 9 | Must Have | Pending |
| CLI-05 | Phase 9 | Must Have | Pending |

## Out of Scope

| Feature | Reason |
|---------|--------|
| Production data migration | Security risk; migrations only, fresh DB |
| Interactive setup wizard | Breaks scriptability; use flags |
| Docker Compose translation | LXC != Docker; fundamentally different |
| Remote database migration | Security risk; local only |
| Custom migration frameworks | Support Prisma, Drizzle, raw SQL only |
| Multi-project containers | Defeats isolation purpose |

## Coverage Summary

- **Total requirements:** 27
- **Phase 6 (Core Transfer):** 7 requirements
- **Phase 7 (Node.js Setup):** 5 requirements
- **Phase 8 (Database Integration):** 9 requirements
- **Phase 9 (CLI Integration):** 6 requirements

---
*Created: 2026-02-01 for v1.1 milestone*
*Updated: 2026-02-01 with phase traceability*
