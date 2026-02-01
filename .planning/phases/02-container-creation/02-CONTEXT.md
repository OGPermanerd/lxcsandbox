# Phase 2: Container Creation - Context

**Gathered:** 2026-02-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Create script to launch isolated LXC containers with Ubuntu 24.04, TUN device for Tailscale, resource limits, and basic packages. Users run this with a container name to get a sandbox ready for provisioning. Stack provisioning (Node, Postgres, etc.) is a separate phase.

</domain>

<decisions>
## Implementation Decisions

### Resource Defaults
- Memory: 4GB soft limit (can burst if host has RAM available)
- CPU: Match host cores (use all available)
- Disk: No quota (share btrfs pool freely)
- Swap: Allow swap (use host swap if available)

### Container Naming
- Format: DNS-style (lowercase, hyphens, must start with letter)
- Length: 2-30 characters
- Reserved names: Block system names (default, host, localhost, etc.)
- Invalid name error: Detailed message showing what's wrong + example of valid name

### Existing Container Handling
- If name exists: Prompt "delete existing and create new?"
- No --force flag: Always prompt for destructive operations
- Stopped containers: Same behavior as running (still prompt to replace)
- Before delete: Auto-snapshot the existing container as backup

### Network Wait Behavior
- Timeout: 60 seconds
- Connectivity test: Has IP address AND can ping 8.8.8.8
- On timeout: Fail with error, leave container running for debug
- Progress: Show dots/spinner during wait

### Claude's Discretion
- Exact spinner/progress implementation
- LXD image selection (ubuntu:24.04 vs alternatives)
- Order of TUN device vs resource limit setup
- Exact error message wording (follow detailed pattern)

</decisions>

<specifics>
## Specific Ideas

- Soft memory limit allows bursting which is useful when only one container running
- Auto-snapshot before replace protects against accidental data loss
- DNS-style naming ensures Tailscale MagicDNS compatibility
- Leave failed container running so user can debug network issues

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-container-creation*
*Context gathered: 2026-02-01*
