# Project Research Summary

**Project:** Dev Sandbox Infrastructure - v1.1 Migration Milestone
**Domain:** Developer tooling - Node.js project migration into LXC containers
**Researched:** 2026-02-01
**Confidence:** HIGH

## Executive Summary

This research covers the v1.1 milestone: adding project migration capabilities to the existing LXC sandbox infrastructure. The domain is well-understood - migrating Node.js projects with PostgreSQL databases involves mature, documented patterns. The existing v1.0 infrastructure provides a solid foundation with container creation, provisioning, and management already working.

The recommended approach is a single `sandbox.sh migrate <container> <source>` command that orchestrates: source detection (git URL vs local path), file transfer, dependency installation, database creation, and migration execution. The architecture follows the existing script pattern - a thin CLI dispatcher calling a new `04-migrate-project.sh` script. Key differentiators include auto-detection of migration tools (Prisma/Drizzle) and package managers (npm/yarn/pnpm).

The primary risks are platform-specific: Node.js native module architecture mismatches (copying node_modules from macOS to Linux) and ABI version mismatches (wrong Node version). These are fully preventable by always excluding node_modules during transfer and respecting .nvmrc files. Secondary risks involve non-interactive shell contexts breaking nvm and Prisma commands - both solved by using login shells and `prisma migrate deploy` instead of `prisma migrate dev`.

## Key Findings

### Recommended Stack

The migration feature requires minimal additions to the existing stack. Most tools are already present from v1.0 provisioning.

**Core technologies:**
- **jq**: JSON parsing for package.json - MISSING, add to `02-create-container.sh` basic packages
- **git**: Already installed - required for git URL cloning inside containers
- **bash 5.x**: Already present - all detection logic implemented in bash
- **lxc file push**: Native LXD tool - preferred for file transfer (atomic, no SSH needed)

**Detection patterns identified:**
- Node.js version: `.nvmrc` > `package.json engines.node` > default (22)
- Package manager: `pnpm-lock.yaml` > `yarn.lock` > `package-lock.json` > npm fallback
- Migration tool: prisma/ > drizzle.config.ts > migrations/*.sql > none

### Expected Features

**Must have (table stakes):**
- Git clone support with branch/tag option
- Local directory copy support
- npm/yarn/pnpm detection and install
- .env file preservation
- Database creation
- Basic success/error output

**Should have (competitive):**
- DATABASE_URL auto-generation for container context
- Prisma/Drizzle migration detection and execution
- Pre-migration snapshot suggestion
- .nvmrc version detection and switching
- Migration summary report

**Defer (v2+):**
- Health check after migration
- Idempotent re-migration handling
- .env.example fallback
- Raw SQL migration support
- Interactive setup wizard (anti-feature: breaks scriptability)

### Architecture Approach

The migration integrates as a new command in the existing `sandbox.sh` dispatcher pattern. Heavy lifting is delegated to `04-migrate-project.sh`, following the numbered script convention (01-setup-host, 02-create-container, 03-provision-container). All container operations use `lxc exec` with explicit nvm sourcing to handle non-interactive shell limitations.

**Major components:**
1. **Source resolver** - Detect git URL vs local path, handle GitHub shorthand
2. **Project analyzer** - Detect package manager, Node version, migration tool from project files
3. **File transfer** - Use `lxc file push` for local paths, `git clone` inside container for URLs
4. **Container executor** - Run npm install, database setup, migrations with proper shell initialization
5. **Environment configurator** - Copy .env, optionally update DATABASE_URL for container context

### Critical Pitfalls

1. **Native module architecture mismatch** - NEVER copy node_modules; always exclude during transfer and npm install fresh in container
2. **Node.js version mismatch** - Detect .nvmrc/engines.node BEFORE npm install; use `nvm install` to match
3. **Package manager mismatch** - Detect from lockfile; using npm when project uses pnpm causes version drift
4. **Database doesn't exist** - Create database BEFORE running migrations; Prisma/Drizzle fail with unclear errors otherwise
5. **Non-interactive shell breaks nvm** - Use `bash -l -c` (login shell) or explicit `source ~/.nvm/nvm.sh` for all Node commands

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Core Transfer

**Rationale:** File transfer is the foundation - nothing else works without code in the container.
**Delivers:** Working `sandbox.sh migrate` command that gets code into containers.
**Addresses:** Git clone support, local directory copy, .env preservation.
**Avoids:** Native module architecture mismatch (by excluding node_modules).

Key implementation:
- Add `jq` to container packages (STACK.md requirement)
- Source type detection (git URL vs local path vs GitHub shorthand)
- `lxc file push` for local, `git clone` inside container for URLs
- Always exclude node_modules, .git, dist, .next during local copy

### Phase 2: Node.js Setup

**Rationale:** Dependencies must be installed before database migrations can run (ORM tools need to be available).
**Delivers:** Correct Node.js version and installed dependencies.
**Uses:** nvm (already provisioned), detection patterns from STACK.md.
**Implements:** Project analyzer component.

Key implementation:
- .nvmrc and package.json engines detection
- Package manager detection from lockfiles
- `nvm install` + `nvm use` with login shell
- npm ci / yarn install --frozen-lockfile / pnpm install --frozen-lockfile

### Phase 3: Database Integration

**Rationale:** Many Node.js projects use ORMs that need database setup; this is the expected "just works" behavior.
**Delivers:** Created database, executed migrations, working DATABASE_URL.
**Avoids:** "Database doesn't exist" errors, Prisma non-interactive hang.

Key implementation:
- Create project-specific database (`createdb -U dev <project>`)
- Detect migration tool (Prisma/Drizzle from dependencies)
- Run `prisma migrate deploy` or `drizzle-kit push` (NOT `migrate dev`)
- Update DATABASE_URL in .env if needed

### Phase 4: Polish and CLI Integration

**Rationale:** User experience improvements and full sandbox.sh integration.
**Delivers:** Production-ready migrate command with helpful output.

Key implementation:
- Pre-migration snapshot suggestion
- Migration summary report
- Error messages with recovery instructions
- Help text and usage examples

### Phase Ordering Rationale

- **Phase 1 before 2:** Code must be in container before detecting/installing dependencies
- **Phase 2 before 3:** ORM tools (prisma, drizzle-kit) come from npm install; must exist before running migrations
- **Phase 3 before 4:** Core functionality complete before polish
- **DB creation before migrations:** Pitfall #5 - migrations fail without database

### Research Flags

Phases likely needing deeper research during planning:
- **None identified:** This is a well-documented domain with established patterns

Phases with standard patterns (skip research-phase):
- **All phases:** Git clone, npm install, database migrations, and shell scripting are thoroughly documented
- **Container exec patterns:** Already established in 02/03 scripts, just extend the pattern

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Minimal additions needed; jq is standard, rest already exists |
| Features | HIGH | Universal developer expectations; based on standard workflows |
| Architecture | HIGH | Direct extension of existing codebase patterns |
| Pitfalls | HIGH | Multiple authoritative sources; well-documented failure modes |

**Overall confidence:** HIGH

### Gaps to Address

- **bun support:** Not researched; bun is not installed in containers. If needed, add to v2.
- **TypeORM/Sequelize/Knex:** Detection patterns documented but execution commands not tested. Start with Prisma/Drizzle, add others if requested.
- **Monorepo support:** Not researched. Single-project migration assumed. Defer to v2 if needed.

## Stack Additions

**Required (add to 02-create-container.sh):**
```bash
apt-get install -y -qq jq
```

**Already present (no action):**
- git, curl, nvm, Node.js 22, PostgreSQL, bash 5.x

## Open Questions

1. **Project destination path:** Use `/root/projects/<name>` or `/root/<name>`? Recommend `/root/projects/` for consistency.
2. **Multiple projects per container:** Out of scope per anti-features, but should migrate fail if project already exists, or offer to update?
3. **Git authentication:** For private repos, rely on user's SSH keys or git credential helpers? Document manual setup.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `02-create-container.sh`, `03-provision-container.sh`, `sandbox.sh`
- [Prisma Docker Guide](https://www.prisma.io/docs/guides/docker)
- [Prisma Migrate Deploy](https://www.prisma.io/docs/orm/prisma-client/deployment/deploy-database-changes-with-prisma-migrate)
- [Drizzle Kit Push vs Migrate](https://orm.drizzle.team/docs/drizzle-kit-push)
- [npm package.json engines field](https://docs.npmjs.com/files/package.json/)
- [nvm-sh/nvm GitHub](https://github.com/nvm-sh/nvm)

### Secondary (MEDIUM confidence)
- [Azure Blog: Module compiled against different Node.js version](https://azureossd.github.io/2023/05/31/Troubleshooting-a-Module-was-compiled-against-a-different-Node.js-version-errors/)
- [Semaphore: Dockerizing a Node.js Web Application](https://semaphore.io/community/tutorials/dockerizing-a-node-js-web-application)
- [pnpm: Symlinked node_modules structure](https://pnpm.io/symlinked-node-modules-structure)

---
*Research completed: 2026-02-01*
*Ready for roadmap: yes*
