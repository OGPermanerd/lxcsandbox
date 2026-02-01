# Project Milestones: Dev Sandbox Infrastructure

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
