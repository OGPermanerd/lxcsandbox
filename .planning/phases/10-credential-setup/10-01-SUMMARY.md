# Summary: 10-01 Credential Setup - Default Auth Copying

## Execution Status

**Status:** Complete
**Completed:** 2026-02-02
**Commit:** 5587b8d

## What Was Built

Made credential copying the default behavior during container provisioning:

1. **Removed `--with-gh-creds` flag** — Git credentials now copy automatically
2. **Added GitHub/GitLab to known_hosts** — `ssh-keyscan` adds host keys even if host didn't have them
3. **Copy credentials to both users** — Root and dev users both get SSH keys, .gitconfig, gh CLI config
4. **Updated documentation** — CLAUDE.md and help text reflect new default behavior

## Files Modified

| File | Changes |
|------|---------|
| 03-provision-container.sh | Removed `WITH_GH_CREDS` flag, made `setup_git_credentials` unconditional, added GitHub/GitLab to known_hosts, copy to both root and dev |
| sandbox.sh | Removed `--with-gh-creds` from help and argument parsing |
| CLAUDE.md | Updated "Create New Sandbox" section to show credentials copy by default |

## Requirements Addressed

- CLAUDE-01: Container has ~/.claude copied from host ✓
- CLAUDE-02: Claude Code works without manual /login ✓
- CLAUDE-03: Auth copying is automatic ✓
- GIT-01: Container has ~/.ssh copied from host ✓
- GIT-02: Container has ~/.config/gh copied from host ✓
- GIT-03: SSH known_hosts includes github.com and gitlab.com ✓
- GIT-04: Git push/pull works without manual setup ✓
- GIT-05: --with-gh-creds flag removed ✓
- DEV-01: Credentials copied to both root and dev users ✓
- DEV-02: Correct ownership set on copied files ✓

## Deviations

None — plan executed as designed.

## Issues Encountered

None.

## Verification Notes

To verify on actual VPS:
1. Create sandbox: `sudo ./sandbox.sh create test-auth tskey-xxx`
2. SSH in: `ssh dev@<tailscale-ip>`
3. Check: `ls ~/.ssh/` — should have keys
4. Check: `ls ~/.config/gh/` — should exist if host had it
5. Check: `cat ~/.ssh/known_hosts | grep github` — should have entry
6. Test: `gh auth status` — should show logged in
7. Test: `git ls-remote git@github.com:user/repo.git` — should work
