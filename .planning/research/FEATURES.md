# Feature Landscape: Node.js Project Migration

**Domain:** Developer environment migration (Node.js + PostgreSQL into LXC containers)
**Researched:** 2026-02-01
**Overall confidence:** HIGH (well-established patterns, existing v1.0 infrastructure)

## Context

This research focuses on what features developers expect when migrating existing Node.js projects (with PostgreSQL databases and .env configuration) into isolated LXC containers. The target user is a developer who has:
- An existing Node.js project (local directory or git repository)
- PostgreSQL database requirements
- Environment variables in .env files
- Possibly migration files (Prisma, Drizzle, or raw SQL)

The infrastructure already provides: container creation, shell access, snapshot/restore. This milestone adds project migration capabilities.

---

## Table Stakes

Features users expect. Missing any of these makes migration feel incomplete or broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Git clone support** | Most projects are in git repos; users expect `sandbox migrate <url>` | Low | Use `git clone` with optional branch/tag |
| **Local directory copy** | Some projects are local-only or have uncommitted changes | Low | Use `rsync` or `lxc file push` |
| **npm install automation** | Every Node.js project needs dependencies installed post-clone | Low | Detect package.json, run `npm install` |
| **.env file preservation** | Environment variables are essential; losing them breaks the app | Low | Copy .env to container, warn if missing |
| **Database creation** | PostgreSQL projects need a database to exist | Low | Create database with project name |
| **Working directory setup** | Project should land in a predictable location | Low | `/root/projects/<name>` or `/home/dev/<name>` |
| **Basic validation output** | User needs to know migration succeeded or failed | Low | Exit codes, success/error messages |
| **yarn/pnpm detection** | Many projects don't use npm; lock file indicates preference | Low | Check for yarn.lock or pnpm-lock.yaml |

### Rationale

These are the minimum steps any developer would manually perform when setting up a project in a new environment:
1. Get the code (clone or copy)
2. Install dependencies (`npm install`)
3. Set up environment variables (copy .env)
4. Create a database

If the migration command doesn't do these, users will immediately have to shell in and do them manually, defeating the purpose of automation.

---

## Differentiators

Features that set the migration apart from a basic "copy files and pray" approach. Not strictly required, but significantly improve the experience.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Migration runner detection** | Auto-detect Prisma/Drizzle/SQL and run migrations | Medium | Check for prisma/, drizzle/, migrations/ |
| **DATABASE_URL auto-generation** | Set correct PostgreSQL connection string for container | Low | Template: `postgresql://dev:dev@localhost:5432/<dbname>` |
| **.nvmrc respect** | Use project's specified Node version if different from default | Medium | Parse .nvmrc, run `nvm install` if needed |
| **Post-migration health check** | Verify the app can start (npm start or npm run dev) | Medium | Run with timeout, check exit code |
| **Pre-migration snapshot** | Auto-snapshot before migration for easy rollback | Low | Already have snapshot capability |
| **Migration report** | Summary of what was detected, copied, and configured | Low | Structured output showing actions taken |
| **Branch/tag support for git** | Clone specific branch or tag, not just default | Low | `git clone -b <branch>` |
| **.env.example fallback** | If no .env exists but .env.example does, copy it | Low | Common pattern for new developers |
| **Idempotent re-migration** | Running migrate twice doesn't break things | Medium | Check if project exists, offer options |

### Rationale

These features address common friction points in project setup:
- **Migration detection** saves the step of "now run `npx prisma migrate deploy`"
- **DATABASE_URL generation** prevents the "connection refused" errors from wrong localhost assumptions
- **.nvmrc respect** prevents version mismatch errors that are hard to debug
- **Health check** gives immediate feedback that the migration actually worked

---

## Anti-Features

Features to deliberately NOT build. These add complexity without proportional value, or actively harm the user experience.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Interactive setup wizard** | Breaks scriptability, conflicts with Claude Code automation | Use argument flags; non-interactive by default |
| **Production data migration** | Dangerous, security concern, out of scope for dev sandboxes | Fresh database with schema migrations only |
| **Secret management integration** | Over-engineering; .env files work for dev environments | Copy .env as-is; user manages secrets |
| **Custom migration framework support** | Endless variations; diminishing returns | Support Prisma, Drizzle, raw SQL; document manual steps for others |
| **Multi-project container** | Defeats isolation purpose; creates complexity | One project per container (existing design) |
| **Automatic port detection** | Containers have isolated networking; ports don't conflict | Use standard ports (3000, 5432); document how to change |
| **Docker Compose translation** | LXC is not Docker; fundamentally different model | Provision native services; ignore docker-compose.yml |
| **Remote database migration** | Security risk; network complexity | Local database only; fresh dev data |
| **CI/CD integration** | Out of scope for sandbox infrastructure | Document manual integration patterns |
| **Automatic dependency updates** | Risk of breaking changes; user should control versions | Install what's in package-lock.json exactly |

### Rationale

The goal is **isolated development sandboxes**, not a general-purpose deployment tool. Each anti-feature either:
- Increases complexity disproportionately (wizard, CI/CD)
- Creates security risks (production data, remote DB)
- Conflicts with the core isolation design (multi-project)
- Solves problems that don't exist in this context (port detection)

---

## Feature Dependencies

```
git clone OR local copy
        │
        ▼
    npm install ◄─── yarn/pnpm detection
        │
        ▼
    .env copy ◄─── .env.example fallback
        │
        ▼
    createdb
        │
        ▼
    DATABASE_URL generation
        │
        ▼
    migration runner ◄─── Prisma/Drizzle/SQL detection
        │
        ▼
    health check (optional)
        │
        ▼
    migration report
```

**Critical path:** git/copy -> npm install -> .env -> createdb -> migrations

**Optional paths:** .nvmrc (before npm install), health check (after migrations)

---

## MVP Recommendation

For the initial `sandbox.sh migrate` command, prioritize:

### Must Have (Phase 1)
1. **Git clone support** with branch option
2. **Local directory copy** support
3. **npm/yarn/pnpm detection and install**
4. **.env file copy**
5. **Database creation**
6. **DATABASE_URL environment variable**
7. **Basic success/error output**

### Should Have (Phase 1 or 2)
8. **Prisma migration detection and execution**
9. **Drizzle migration detection and execution**
10. **Pre-migration snapshot**
11. **Migration summary report**

### Nice to Have (Phase 2+)
12. **.nvmrc version detection**
13. **Health check**
14. **Raw SQL migrations support**
15. **Idempotent re-migration handling**

### Defer to Future Milestone
- .env.example fallback (edge case)
- Multiple migration framework support beyond Prisma/Drizzle

---

## User Workflow Expectations

Based on research, developers expect this workflow:

```bash
# Simple case: clone and migrate
sandbox.sh migrate relay-dev https://github.com/user/relay-app.git

# With branch
sandbox.sh migrate relay-dev https://github.com/user/relay-app.git --branch develop

# Local directory
sandbox.sh migrate relay-dev /path/to/local/project

# Expected output:
# Cloning https://github.com/user/relay-app.git...
# Detected: Node.js (npm), PostgreSQL (Prisma)
# Installing dependencies...
# Creating database: relay_dev
# Running migrations...
# Migration complete!
#
# Next steps:
#   sandbox.sh shell relay-dev
#   cd /root/projects/relay-app
#   npm run dev
```

**Key expectations:**
- Single command to fully set up a project
- Clear indication of what was detected and done
- Obvious next steps for starting development
- No manual steps required for common cases

---

## Sources

Research compiled from:
- [Node.js Version Migration Best Practices](https://nodejs.org/en/learn/getting-started/userland-migrations)
- [Smashing Magazine: Express API Backend Setup with PostgreSQL](https://www.smashingmagazine.com/2020/04/express-api-backend-project-postgresql/)
- [GitHub Community: Git Clone vs Directory Copy](https://github.com/orgs/community/discussions/53148)
- [Medium: .env Security Best Practices](https://medium.com/@jinvishal2011/the-complete-guide-to-environment-variables-security-implementation-and-best-practices-8a5202afeca1)
- [Fishtank: .env Version Control Best Practices](https://www.getfishtank.com/insights/best-practices-for-committing-env-files-to-version-control)
- [Hostman: PostgreSQL Migration Guide](https://hostman.com/tutorials/how-to-migrate-a-postgresql-database/)
- [Garden.io: Developer Onboarding Tools](https://garden.io/blog/developer-onboarding)
- [Coder: Automated Developer Onboarding](https://coder.com/blog/automate-developer-onboarding-with-coder)
- [Dev.to: Auto-install NPM Dependencies on Git Pull](https://dev.to/zirkelc/automatically-install-npm-dependencies-on-git-pull-bg0)

Confidence levels:
- Table stakes: HIGH (universal developer expectations)
- Differentiators: MEDIUM-HIGH (based on common patterns)
- Anti-features: HIGH (based on project scope and existing design decisions)
