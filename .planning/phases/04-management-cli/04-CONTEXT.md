# Phase 4: Management CLI - Discussion Context

**Created:** 2026-02-01
**Phase Goal:** User has simple CLI commands for all sandbox operations

## Decisions from Discussion

### Command Interface Design

| Question | Decision | Rationale |
|----------|----------|-----------|
| Command style | Git-style subcommands | `sandbox.sh create`, `sandbox.sh shell` - familiar, self-documenting |
| Error handling | Show full usage | Display all commands with descriptions on unknown command |

### Create Command Flow

| Question | Decision | Rationale |
|----------|----------|-----------|
| Auth key input | Command argument | `sandbox.sh create mybox tskey-xxx` - explicit, scriptable, matches 03-provision |
| Wait behavior | Wait with progress | Show step-by-step output, return when fully provisioned and Tailscale connected |

### Destructive Operations

| Question | Decision | Rationale |
|----------|----------|-----------|
| Delete confirmation | Interactive yes/no | "Delete container 'mybox'? This cannot be undone. [y/N]" - safe default |
| Safety snapshot on delete | Prompt to snapshot | "Create snapshot before deleting? [Y/n]" - user choice each time |
| Restore behavior | Auto-snapshot current | Save as 'pre-restore-TIMESTAMP' before restoring - reversible |

## Command Summary

Based on requirements MGMT-01 through MGMT-07:

| Command | Usage | Behavior |
|---------|-------|----------|
| `create` | `sandbox.sh create <name> <tailscale-key>` | Run 02 + 03 scripts, wait with progress |
| `shell` | `sandbox.sh shell <name>` | Open bash in container |
| `list` | `sandbox.sh list` | Show all containers with status |
| `snapshot` | `sandbox.sh snapshot <name> [snapshot-name]` | Create named snapshot |
| `restore` | `sandbox.sh restore <name> <snapshot-name>` | Auto-snapshot current, then restore |
| `delete` | `sandbox.sh delete <name>` | Confirm, optionally snapshot, then delete |
| `info` | `sandbox.sh info <name>` | Show container details and Tailscale IP |

## Implementation Notes

- Script delegates to existing `02-create-container.sh` and `03-provision-container.sh`
- All commands validate container name before action
- `--help` flag available on all commands
- Exit codes: 0 = success, 1 = error, 2 = user cancelled

---
*Context captured: 2026-02-01*
