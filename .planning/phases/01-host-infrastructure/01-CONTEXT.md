# Phase 1: Host Infrastructure - Context

**Gathered:** 2026-02-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Configure VPS with LXD daemon, bridge network (lxdbr0), btrfs storage pool, and UFW firewall rules. The host must be ready to launch LXC containers after this phase. Container creation is a separate phase.

**SACRED CONSTRAINT:** Never break SSH or Tailscale access to the host VPS — this is the recovery path if something goes wrong. All changes must be additive.

</domain>

<decisions>
## Implementation Decisions

### Existing State Handling
- If LXD is already installed: check version, upgrade if older than current stable
- If lxdbr0 bridge already exists: use as-is, don't reconfigure (accept whatever subnet it has)
- If storage pool already exists: use existing pool, don't create new
- Script must be fully idempotent — safe to run multiple times, skip what's already done

### Error Recovery
- Fail fast: if any step fails, stop immediately with clear error message
- No automatic rollback: leave partial state for user to inspect and decide
- Missing prerequisites (e.g., snapd): install automatically without prompting
- Verify each step: confirm LXD is running, network exists, etc. before proceeding to next step

### Network Safety
- Verify SSH connectivity works BEFORE making any network changes
- Host has Tailscale running — must not break it
- UFW rules: additive only — never modify or remove existing rules, only add what's needed for lxdbr0
- NAT: let LXD manage NAT via preseed config (don't add explicit iptables rules ourselves)

### Claude's Discretion
- Specific Ubuntu version compatibility checks
- Exact error messages and formatting
- Which verification commands to use
- Log file location and format

</decisions>

<specifics>
## Specific Ideas

- User emphasized host SSH and Tailscale as "sacred" — treat them as untouchable
- The VPS is an existing server (~8GB RAM) that's already in use
- Prefer LXD's built-in network management over manual iptables

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-host-infrastructure*
*Context gathered: 2026-02-01*
