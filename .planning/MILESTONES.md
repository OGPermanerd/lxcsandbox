# Project Milestones: Dev Sandbox Infrastructure

## v1.2 Auth & Polish (Shipped: 2026-02-02)

**Delivered:** Fixed authentication issues so Claude Code and git work out-of-the-box in new containers.

**Phases completed:** 10 (1 plan total)

**Key accomplishments:**

- Made credential copying default behavior (removed --with-gh-creds flag)
- Git credentials (SSH keys, .gitconfig, gh CLI) copy automatically from host
- Claude Code credentials (~/.claude) copy automatically from host
- GitHub and GitLab host keys added to known_hosts automatically
- Credentials copied to both root and dev users

**Stats:**

- 3 files modified
- 74 lines added, 42 removed
- 1 phase, 1 plan
- Same day completion

**Git range:** `9f0ba6a` → `c0b1608`

**What's next:** Integration testing on actual Hetzner VPS

---

## v1.1 Project Migration (Shipped: 2026-02-02)

**Delivered:** Project migration capabilities to move existing Node.js projects into containerized sandboxes with automated environment setup.

**Phases completed:** 6-9 (4 plans total)

**Key accomplishments:**

- Project transfer from git URLs and local directories
- Package manager detection (npm/yarn/pnpm) and dependency installation
- Database creation and migration execution (Prisma/Drizzle/raw SQL)
- Monorepo build support
- Pre-migration snapshots for safety

**Stats:**

- 1 new script (04-migrate-project.sh)
- 27 requirements shipped
- 4 phases, 4 plans

**Git range:** `27fda54` → `4154c33`

**What's next:** v1.2 Auth & Polish

---

## v1.0 Dev Sandbox Infrastructure (Shipped: 2026-02-01)

**Delivered:** Complete LXC-based sandbox infrastructure with Tailscale networking, full dev stack (Node.js, PostgreSQL, Playwright, Claude Code), and unified management CLI.

**Phases completed:** 1-5 (5 plans total)

**Key accomplishments:**

- Idempotent host setup with preseed-based LXD configuration
- Container creation with TUN device passthrough for Tailscale VPN
- Full dev stack provisioning (Node.js 22, PostgreSQL, Playwright, Claude Code)
- Unified sandbox.sh CLI with safety features (auto-snapshots, confirmation prompts)
- Defensive checks (LXD availability, TUN validation) and dead code cleanup

**Stats:**

- 4 shell scripts created
- 1,428 lines of bash
- 5 phases, 5 plans
- 1 day from start to ship

**Git range:** `c95e7ff` → `27fda54`

**What's next:** Integration testing on actual Hetzner VPS with Tailscale

---

*Milestones track shipped versions. For current work, see .planning/ROADMAP.md*
