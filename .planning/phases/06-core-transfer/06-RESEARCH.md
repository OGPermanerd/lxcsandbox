# Phase 6: Core Transfer - Research

**Researched:** 2026-02-01
**Domain:** File transfer to LXC containers (git clone + local copy with rsync-style exclusions)
**Confidence:** HIGH

## Summary

Phase 6 focuses on transferring project source code into LXC containers. The phase handles two source types: git repositories (via git clone) and local directories (via lxc file push/tar pipe). The key technical decisions involve source type detection, branch/tag specification for git, and exclusion patterns for local copies.

Research confirms that the standard approach is:
1. Detect source type via URL pattern matching (git URLs start with https://, git@, ssh://, or git://)
2. Clone git repos directly inside the container using `git clone --branch` for branch/tag specification
3. Transfer local directories via tar pipe with `--exclude` flags for node_modules and .git
4. Copy .env files as a separate explicit operation

**Primary recommendation:** Use tar-pipe transfer method (`tar -c | lxc exec tar -x`) for local directories - it handles permissions, symlinks, and exclusions better than `lxc file push -r`.

## Standard Stack

The established tools for this domain:

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| git | system apt | Clone repositories | Already installed in container (02-create-container.sh) |
| tar | system | Archive/extract with exclusions | Handles symlinks, permissions correctly; supports exclude |
| lxc file push | LXD native | Push individual files | Best for single files like .env |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| rsync | 3.x apt | Incremental sync with exclusions | If re-migration becomes a feature (not Phase 6 scope) |
| bash regex | 5.x system | URL pattern detection | Detect git vs local source |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| tar pipe | lxc file push -r | lxc file push struggles with symlinks and permission preservation |
| tar pipe | rsync over SSH | Requires SSH setup in container, more complex |
| git clone inside container | git clone on host then push | Extra transfer step, wastes bandwidth |

**No additional packages needed:** All required tools (git, tar, bash) are already available.

## Architecture Patterns

### Recommended Script Structure
```
04-migrate-project.sh
  |
  +-- Source Detection
  |     +-- detect_source_type() -> "git" | "local" | "unknown"
  |     +-- validate_git_url()
  |     +-- validate_local_path()
  |
  +-- Transfer Operations
  |     +-- clone_git_repository()
  |     +-- copy_local_directory()
  |
  +-- Environment Handling
        +-- copy_env_file()
```

### Pattern 1: Source Type Detection
**What:** Determine if source is git URL or local directory path
**When to use:** First step in migrate script
**Example:**
```bash
# Source: Official git documentation (git-scm.com/docs/git-clone)
detect_source_type() {
    local source="$1"

    # Git URL patterns (HTTPS, SSH, git protocol)
    if [[ "$source" =~ ^https?://.*\.git$ ]] || \
       [[ "$source" =~ ^https?://github\.com/ ]] || \
       [[ "$source" =~ ^https?://gitlab\.com/ ]] || \
       [[ "$source" =~ ^https?://bitbucket\.org/ ]] || \
       [[ "$source" =~ ^git@ ]] || \
       [[ "$source" =~ ^ssh:// ]] || \
       [[ "$source" =~ ^git:// ]]; then
        echo "git"
        return 0
    fi

    # Local directory (absolute or relative path that exists)
    if [[ -d "$source" ]]; then
        echo "local"
        return 0
    fi

    echo "unknown"
    return 1
}
```

### Pattern 2: Git Clone with Branch
**What:** Clone repository inside container with optional branch/tag
**When to use:** Source is a git URL
**Example:**
```bash
# Source: git-scm.com/docs/git-clone (--branch option)
clone_git_repository() {
    local container="$1"
    local repo_url="$2"
    local dest_dir="$3"
    local branch="${4:-}"  # Optional branch/tag

    log_info "Cloning repository into container..."

    if [[ -n "$branch" ]]; then
        # Clone specific branch or tag
        lxc exec "$container" -- bash -c "
            git clone --branch '$branch' '$repo_url' '$dest_dir'
        "
    else
        # Clone default branch
        lxc exec "$container" -- bash -c "
            git clone '$repo_url' '$dest_dir'
        "
    fi

    # Verify clone succeeded
    if ! lxc exec "$container" -- test -d "$dest_dir/.git"; then
        log_error "Git clone failed - no .git directory found"
        return 1
    fi

    log_info "Repository cloned to $dest_dir"
}
```

### Pattern 3: Local Directory Transfer with Exclusions
**What:** Copy local project to container, excluding node_modules and .git
**When to use:** Source is a local directory path
**Example:**
```bash
# Source: linuxvox.com/blog/how-to-exclude-files-and-directories-with-rsync/
# Tar approach chosen over lxc file push for better handling
copy_local_directory() {
    local source_dir="$1"
    local container="$2"
    local dest_dir="$3"

    log_info "Copying project files (excluding node_modules, .git)..."

    # Create destination directory
    lxc exec "$container" -- mkdir -p "$dest_dir"

    # Use tar pipe for reliable transfer with exclusions
    # Excludes per requirements: node_modules, .git
    # Also exclude common build artifacts to speed transfer
    tar -C "$source_dir" \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='.next' \
        --exclude='.nuxt' \
        --exclude='.cache' \
        --exclude='coverage' \
        -cf - . | lxc exec "$container" -- tar -C "$dest_dir" -xf -

    log_info "Project copied to $container:$dest_dir"
}
```

### Pattern 4: .env File Copy
**What:** Copy .env file separately (it may be outside the project or gitignored)
**When to use:** After main transfer, if .env exists in source
**Example:**
```bash
# Source: dotenvx.com/docs/env-file (env file handling best practices)
copy_env_file() {
    local source_dir="$1"
    local container="$2"
    local dest_dir="$3"

    # Check for .env file in source
    if [[ -f "$source_dir/.env" ]]; then
        log_info "Copying .env file..."
        lxc file push "$source_dir/.env" "$container/$dest_dir/.env"
        log_info ".env copied to container"
    else
        log_warn "No .env file found in source"
        # Check for .env.example (handled in later phases)
        if [[ -f "$source_dir/.env.example" ]]; then
            log_info ".env.example exists - can be copied as .env in later phase"
        fi
    fi
}
```

### Anti-Patterns to Avoid
- **Copying node_modules:** Never transfer node_modules - it contains platform-specific binaries that won't work across OS/arch boundaries
- **Using lxc file push -r for directories:** Has issues with symlinks and permission preservation; tar pipe is more reliable
- **Cloning on host then pushing:** Wastes bandwidth; clone directly inside container
- **Shallow clone by default:** Breaks many git operations; only use --depth 1 for CI scenarios

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Git URL validation | Custom regex | Pattern match for known prefixes | Git URL formats are standardized |
| File transfer with excludes | Custom file walking | tar --exclude | Handles edge cases (symlinks, perms) |
| Branch/tag cloning | git clone + git checkout | git clone --branch | Single atomic operation |

**Key insight:** File transfer is deceptively complex. Use tar which handles symlinks, permissions, and sparse files correctly.

## Common Pitfalls

### Pitfall 1: lxc file push Trailing Slash
**What goes wrong:** `lxc file push file.txt container/path` fails with error about path
**Why it happens:** lxc file push requires trailing slash for directory destinations
**How to avoid:** Always use `container/path/` (trailing slash) for directory targets
**Warning signs:** "Error: not a directory" messages

### Pitfall 2: Git URL Without .git Extension
**What goes wrong:** Some git URLs work without .git extension; detection regex may miss them
**Why it happens:** GitHub/GitLab accept both `repo` and `repo.git` URLs
**How to avoid:** Match known hosts (github.com, gitlab.com) even without .git suffix
**Warning signs:** Valid git URLs detected as "unknown" source type

### Pitfall 3: Relative Path Resolution
**What goes wrong:** User passes `./myproject` and script can't find it
**Why it happens:** Relative paths depend on current working directory
**How to avoid:** Convert to absolute path: `source_dir=$(cd "$source" && pwd)`
**Warning signs:** "Directory not found" for paths that exist

### Pitfall 4: Large Transfers Without Progress
**What goes wrong:** Long transfers appear frozen with no output
**Why it happens:** tar pipe is silent by default
**How to avoid:** Add -v to tar or use pv for progress; warn user about large transfers
**Warning signs:** Script hangs for minutes on large projects

### Pitfall 5: Branch vs Tag Ambiguity
**What goes wrong:** `--branch v1.0.0` clones tag in detached HEAD state (expected but surprising)
**Why it happens:** git clone --branch works for both branches and tags
**How to avoid:** Document that tags result in detached HEAD; create branch if needed for development
**Warning signs:** "You are in 'detached HEAD' state" warning after clone

## Code Examples

Verified patterns from official sources:

### Complete Source Detection
```bash
# Source: git-scm.com/docs/git-clone (URL formats section)
detect_source_type() {
    local source="$1"

    # Empty check
    if [[ -z "$source" ]]; then
        echo "unknown"
        return 1
    fi

    # Git URL patterns
    # HTTPS: https://github.com/user/repo.git
    # SSH: git@github.com:user/repo.git
    # Git protocol: git://github.com/user/repo.git
    # SSH explicit: ssh://git@github.com/user/repo.git
    if [[ "$source" =~ ^https?:// ]] && [[ "$source" =~ (\.git$|github\.com|gitlab\.com|bitbucket\.org) ]]; then
        echo "git"
        return 0
    fi

    if [[ "$source" =~ ^git@ ]] || \
       [[ "$source" =~ ^ssh:// ]] || \
       [[ "$source" =~ ^git:// ]]; then
        echo "git"
        return 0
    fi

    # Local path (must exist)
    if [[ -d "$source" ]]; then
        echo "local"
        return 0
    fi

    # Could be a git URL without .git suffix - try to verify
    if [[ "$source" =~ ^https?:// ]]; then
        # Could be git, return git and let clone fail if not
        echo "git"
        return 0
    fi

    echo "unknown"
    return 1
}
```

### Validate Git URL Accessibility
```bash
# Source: labex.io/tutorials/git-how-to-validate-git-repository-url
validate_git_url() {
    local url="$1"

    # Use git ls-remote to check if URL is accessible
    # This verifies the repository exists and is reachable
    if git ls-remote "$url" HEAD &>/dev/null; then
        return 0
    else
        log_error "Cannot access git repository: $url"
        echo "Check that:"
        echo "  - The URL is correct"
        echo "  - You have access to the repository"
        echo "  - SSH keys are configured (for git@ URLs)"
        return 1
    fi
}
```

### Derive Project Name from Source
```bash
# Extract project name from git URL or local path
derive_project_name() {
    local source="$1"

    # From git URL: https://github.com/user/my-project.git -> my-project
    if [[ "$source" =~ \.git$ ]]; then
        basename "$source" .git
        return 0
    fi

    # From git URL without .git: https://github.com/user/my-project -> my-project
    if [[ "$source" =~ ^https?:// ]] || [[ "$source" =~ ^git@ ]]; then
        basename "$source"
        return 0
    fi

    # From local path: /path/to/my-project -> my-project
    basename "$(cd "$source" && pwd)"
}
```

### Full Transfer Function with Error Handling
```bash
transfer_project() {
    local container="$1"
    local source="$2"
    local branch="${3:-}"

    local source_type
    source_type=$(detect_source_type "$source")

    local project_name
    project_name=$(derive_project_name "$source")
    local dest_dir="/root/projects/$project_name"

    log_info "Transferring project: $project_name"
    log_info "Source type: $source_type"
    log_info "Destination: $dest_dir"

    # Create projects directory
    lxc exec "$container" -- mkdir -p /root/projects

    case "$source_type" in
        git)
            clone_git_repository "$container" "$source" "$dest_dir" "$branch"
            ;;
        local)
            copy_local_directory "$source" "$container" "$dest_dir"
            # For local copy, also copy .env if it exists
            copy_env_file "$source" "$container" "$dest_dir"
            ;;
        *)
            log_error "Unknown source type: $source"
            log_error "Source must be a git URL or existing local directory"
            return 1
            ;;
    esac

    # Verify transfer
    if ! lxc exec "$container" -- test -d "$dest_dir"; then
        log_error "Transfer failed - destination directory not created"
        return 1
    fi

    log_info "Transfer complete: $dest_dir"
    echo "$dest_dir"  # Return the destination path
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| scp/rsync to container | lxc file push / tar pipe | LXD 3.0+ | No SSH needed, simpler setup |
| git clone + checkout | git clone --branch | Git 1.7.10+ | Single atomic operation |
| Manual node_modules cleanup | Never copy node_modules | Always | Prevents cross-platform bugs |

**Deprecated/outdated:**
- Using `lxc file push -r` for large directories: Known to have issues with symlinks and permissions in unprivileged containers

## Open Questions

Things that couldn't be fully resolved:

1. **GitHub shorthand support (owner/repo)**
   - What we know: Could expand to https://github.com/owner/repo.git
   - What's unclear: Is this needed for v1.1 or can users provide full URLs?
   - Recommendation: Defer to Phase 9 (CLI polish) if desired; full URLs work now

2. **SSH key passthrough for private repos**
   - What we know: git@ URLs require SSH keys; host keys must be available
   - What's unclear: How to handle SSH agent forwarding to container
   - Recommendation: Document that private repos via SSH require manual key setup; suggest HTTPS with token instead

3. **Progress indication for large transfers**
   - What we know: tar pipe is silent; users may think script is frozen
   - What's unclear: Best UX for showing progress without pv dependency
   - Recommendation: Add log message before transfer with size estimate; consider pv as optional enhancement

## Sources

### Primary (HIGH confidence)
- [Git Clone Documentation](https://git-scm.com/docs/git-clone) - --branch option, URL formats
- [LXC File Push Documentation](https://documentation.ubuntu.com/lxd/latest/reference/manpages/lxc/file/push/) - Push syntax and flags

### Secondary (MEDIUM confidence)
- [Rsync Exclude Best Practices](https://linuxvox.com/blog/how-to-exclude-files-and-directories-with-rsync/) - Exclusion patterns
- [GitHub Gist: rsync backup excluding node_modules](https://gist.github.com/spyesx/0edd62936600ffe7ca0b5c27bc7d080c) - node_modules exclusion
- [Linux Containers Forum: File Transfer](https://discuss.linuxcontainers.org/t/rsync-files-into-container-from-host/822) - tar pipe approach

### Tertiary (LOW confidence)
- [LabEx: Validate Git Repository URL](https://labex.io/tutorials/git-how-to-validate-git-repository-url-434201) - git ls-remote validation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools are system utilities with stable APIs
- Architecture: HIGH - Patterns derived from official documentation
- Pitfalls: MEDIUM - Based on community reports and prior research docs

**Research date:** 2026-02-01
**Valid until:** 2026-04-01 (stable domain, 60 days)

---

## Appendix: Requirements Mapping

| Requirement | Technical Approach | Verified |
|-------------|-------------------|----------|
| SRC-01: Git URL source | detect_source_type() + clone_git_repository() | Yes |
| SRC-02: Local directory source | detect_source_type() + copy_local_directory() | Yes |
| SRC-03: --branch flag | git clone --branch parameter | Yes |
| SRC-04: Clone to /root/projects/<name> | dest_dir="/root/projects/$project_name" | Yes |
| SRC-05: rsync-style exclude | tar --exclude='node_modules' --exclude='.git' | Yes |
| ENV-01: Copy .env file | copy_env_file() function | Yes |
| ENV-05: Preserve existing env vars | Only copy .env, don't modify container env | Yes |

All Phase 6 requirements have clear technical implementations identified.
