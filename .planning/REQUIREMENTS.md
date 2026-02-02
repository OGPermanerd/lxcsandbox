# Requirements: v1.2 Auth & Polish

**Defined:** 2026-02-02
**Core Value:** Auth should "just work" — no manual setup needed in new containers

## v1.2 Requirements

Requirements for fixing authentication issues discovered during real-world usage.

### Claude Code Auth (CLAUDE)

- [ ] **CLAUDE-01**: Container has ~/.claude directory copied from host (if exists)
- [ ] **CLAUDE-02**: Claude Code works without manual `/login` in new containers
- [ ] **CLAUDE-03**: Auth copying is automatic during container creation

### Git Auth (GIT)

- [ ] **GIT-01**: Container has ~/.ssh directory copied from host (if exists)
- [ ] **GIT-02**: Container has ~/.config/gh directory copied from host (if exists)
- [ ] **GIT-03**: SSH known_hosts includes github.com and gitlab.com
- [ ] **GIT-04**: Git push/pull works without manual credential setup
- [ ] **GIT-05**: `--with-gh-creds` flag removed (credential copying is default)

### Dev User (DEV)

- [ ] **DEV-01**: Credentials copied to both root and dev users
- [ ] **DEV-02**: Correct ownership set on copied credential files

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CLAUDE-01 | Phase 10 | Pending |
| CLAUDE-02 | Phase 10 | Pending |
| CLAUDE-03 | Phase 10 | Pending |
| GIT-01 | Phase 10 | Pending |
| GIT-02 | Phase 10 | Pending |
| GIT-03 | Phase 10 | Pending |
| GIT-04 | Phase 10 | Pending |
| GIT-05 | Phase 10 | Pending |
| DEV-01 | Phase 10 | Pending |
| DEV-02 | Phase 10 | Pending |

## Out of Scope

| Feature | Reason |
|---------|--------|
| API key management | Credentials copied as-is, not managed |
| Token refresh automation | User handles token expiry on host |
| Multiple git identities | Copy what exists, don't manage profiles |

## Coverage Summary

- **Total requirements:** 10
- **Phase 10 (Credential Setup):** 10 requirements

---
*Created: 2026-02-02 for v1.2 milestone*
