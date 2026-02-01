# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Complete isolation between projects so Claude Code can run autonomously without contaminating other environments
**Current focus:** Phase 9 - CLI Integration COMPLETE

## Current Position

Milestone: v1.1 (Project Migration)
Phase: 9 of 9 (CLI Integration) COMPLETE
Plan: 1 of 1 in current phase
Status: v1.1 milestone complete
Last activity: 2026-02-01 - Completed 09-01-PLAN.md

Progress: [####################] 100% (9/9 phases complete)

## Accumulated Context

### Decisions

See PROJECT.md Key Decisions table for full list with outcomes.

Recent decisions affecting current work:

- [v1.0]: Argument-based CLI for scriptability (affects migrate command design)
- [v1.0]: trust auth for PostgreSQL (enables easy DATABASE_URL setup)
- [Research]: Always exclude node_modules during transfer (prevents architecture mismatch)
- [Research]: Use prisma migrate deploy (not dev) for non-interactive context
- [06-01]: Tar pipe over lxc file push -r for directories (handles symlinks, permissions)
- [06-01]: Clone git repos directly inside container (no double transfer)
- [06-01]: Extended exclusions: dist, build, .next, .nuxt, .cache, coverage
- [07-01]: Lockfile detection for package manager (no jq needed)
- [07-01]: pnpm > yarn > npm precedence for detection
- [07-01]: Always source nvm.sh in container_exec for non-interactive shells
- [08-01]: Sanitize DB names (hyphens->underscores, 63-char limit, prefix digit-start with db_)
- [08-01]: Prisma > Drizzle > SQL detection precedence
- [08-01]: Use --force flag for drizzle-kit push in dev environment
- [08-01]: Raw SQL migrations sorted alphabetically with find | sort
- [08-01]: psql -v ON_ERROR_STOP=1 -1 for fail-fast with transaction wrapping
- [09-01]: Pre-migration snapshot created automatically before any changes
- [09-01]: Global variables used to track detected values for summary output
- [09-01]: Rollback instructions shown on both success and failure

### Pending Todos

None yet.

### Blockers/Concerns

- [v1.0]: Integration testing on actual LXD host blocked by hardware availability
- [RESOLVED]: jq blocker resolved - lockfile existence check sufficient for PM detection

## Session Continuity

Last session: 2026-02-01T22:19:22Z
Stopped at: Completed 09-01-PLAN.md (CLI Integration complete, v1.1 milestone complete)
Resume file: None
