# Phase 2: Container Creation - Research

**Researched:** 2026-02-01
**Domain:** LXD container creation, TUN device configuration, resource limits, network connectivity
**Confidence:** HIGH

## Summary

LXD container creation is a well-documented process using the `lxc launch` command with Ubuntu images. The standard approach combines container launch, inline configuration for resource limits, and device addition for TUN/Tailscale support. Resource limits support both hard and soft enforcement modes, allowing containers to burst when host resources are available.

The key challenge for this phase is configuring TUN device access for Tailscale in unprivileged containers. LXD's `lxc config device add` command with `unix-char` type successfully adds `/dev/net/tun` access. Combined with `security.nesting=true`, this enables Tailscale to function within containers.

**Primary recommendation:** Use `lxc launch ubuntu:24.04 <name>` followed by `lxc config set` for resource limits and `lxc config device add` for TUN device. Set `limits.memory.enforce=soft` to allow memory bursting. Validate container names against DNS-style pattern (lowercase, hyphens, starts with letter, 2-30 chars) before creation.

## Standard Stack

The established commands and patterns for LXD container creation:

### Core Commands
| Command | Purpose | Why Standard |
|---------|---------|--------------|
| `lxc launch` | Create and start container | Single command for creation + startup |
| `lxc config set` | Set instance configuration | Supports live updates for resource limits |
| `lxc config device add` | Add devices to container | Required for TUN device passthrough |
| `lxc snapshot` | Create container snapshot | Required for backup before deletion |
| `lxc delete` | Remove container | Standard removal command |

### Configuration Options
| Option | Type | Default | Purpose |
|--------|------|---------|---------|
| `limits.memory` | String | 1GiB (VMs) | Memory limit (e.g., "4GB") |
| `limits.memory.enforce` | String | `hard` | `hard` or `soft` - soft allows bursting |
| `limits.memory.swap` | Boolean | `true` | Allow container to use swap |
| `limits.cpu` | String | 1 (VMs) | CPU count or range (e.g., "4" or "0-3") |
| `security.nesting` | Boolean | `false` | Enable nesting (needed for some operations) |

### Device Types for TUN
| Device Type | Options | Purpose |
|-------------|---------|---------|
| `unix-char` | `path=/dev/net/tun` | TUN device access for Tailscale |

**Image Reference:**
```bash
# Official Ubuntu 24.04 LTS image
ubuntu:24.04
```

## Architecture Patterns

### Recommended Script Flow
```
02-create-container.sh
├── 1. Parse and validate container name (DNS-style)
├── 2. Check for reserved names (localhost, host, default, etc.)
├── 3. Check if container exists
│   ├── If exists: prompt to replace
│   ├── If replace: snapshot existing, then delete
│   └── If no replace: exit
├── 4. Launch container (lxc launch ubuntu:24.04 <name>)
├── 5. Configure TUN device (lxc config device add)
├── 6. Set resource limits (memory soft, CPU matching host)
├── 7. Restart container (required for TUN device)
├── 8. Wait for network connectivity (60s timeout with spinner)
├── 9. Install basic packages (curl, git, ssh)
└── 10. Display success with next steps
```

### Pattern 1: DNS-Style Name Validation
**What:** Validate container names match DNS hostname rules
**When to use:** Before any container operations
**Example:**
```bash
# Source: RFC 1123 and Phase 2 CONTEXT.md decisions

validate_container_name() {
    local name="$1"

    # Check length (2-30 chars)
    if [[ ${#name} -lt 2 || ${#name} -gt 30 ]]; then
        log_error "Container name must be 2-30 characters (got ${#name})"
        echo "Example: relay-dev, my-project, test-sandbox"
        return 1
    fi

    # Check DNS-style format: lowercase, hyphens, starts with letter
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ && ! "$name" =~ ^[a-z][a-z0-9]$ ]]; then
        log_error "Container name must:"
        echo "  - Start with a lowercase letter"
        echo "  - Contain only lowercase letters, numbers, and hyphens"
        echo "  - Not end with a hyphen"
        echo "Example: relay-dev, my-project, test-sandbox"
        return 1
    fi

    # Check for reserved names
    local reserved=("default" "host" "localhost" "lxdbr0" "none" "self" "all")
    for r in "${reserved[@]}"; do
        if [[ "$name" == "$r" ]]; then
            log_error "Container name '$name' is reserved"
            echo "Reserved names: ${reserved[*]}"
            return 1
        fi
    done

    return 0
}
```

### Pattern 2: Container Creation with Resource Limits
**What:** Create container with soft memory limits and CPU matching host
**When to use:** Initial container creation
**Example:**
```bash
# Source: LXD documentation - instance options

create_container() {
    local name="$1"
    local image="${2:-ubuntu:24.04}"

    log_step "Launching container from $image..."
    lxc launch "$image" "$name"

    # Get host CPU count
    local host_cpus
    host_cpus=$(nproc)

    log_step "Setting resource limits..."

    # Soft memory limit (4GB, can burst if available)
    lxc config set "$name" limits.memory=4GB
    lxc config set "$name" limits.memory.enforce=soft

    # Allow swap usage
    lxc config set "$name" limits.memory.swap=true

    # Match host CPUs
    lxc config set "$name" limits.cpu="$host_cpus"

    log_info "Resource limits: 4GB soft memory, $host_cpus CPUs"
}
```

### Pattern 3: TUN Device for Tailscale
**What:** Add TUN device to enable Tailscale VPN in container
**When to use:** After container creation, before restart
**Example:**
```bash
# Source: Tailscale docs + LXD unix-char device reference

configure_tun_device() {
    local name="$1"

    log_step "Configuring container for Tailscale..."

    # Enable nesting (needed for some container operations)
    lxc config set "$name" security.nesting=true

    # Add TUN device for Tailscale
    lxc config device add "$name" tun unix-char path=/dev/net/tun

    log_info "TUN device added"
}
```

### Pattern 4: Snapshot Before Replace
**What:** Create automatic backup snapshot before deleting existing container
**When to use:** When user confirms replacement of existing container
**Example:**
```bash
# Source: LXD snapshot documentation

handle_existing_container() {
    local name="$1"

    if lxc info "$name" &> /dev/null; then
        echo ""
        read -p "Container '$name' already exists. Delete and create new? (y/N): " confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Cancelled"
            exit 0
        fi

        # Create backup snapshot with timestamp
        local snap_name="backup-$(date +%Y%m%d-%H%M%S)"
        log_step "Creating backup snapshot: $name/$snap_name"

        # Stop container if running (snapshot works on running but cleaner stopped)
        if [[ "$(lxc info "$name" | grep 'Status:' | awk '{print $2}')" == "RUNNING" ]]; then
            lxc stop "$name" --timeout 30
        fi

        lxc snapshot "$name" "$snap_name"
        log_info "Snapshot created: $name/$snap_name"

        # Now delete
        log_step "Deleting existing container..."
        lxc delete "$name" --force
        log_info "Container deleted"
    fi
}
```

### Pattern 5: Network Connectivity Wait with Spinner
**What:** Wait for container to get IP and internet connectivity
**When to use:** After container restart, before package installation
**Example:**
```bash
# Source: Bash spinner patterns + CONTEXT.md decisions

wait_for_network() {
    local name="$1"
    local timeout="${2:-60}"
    local elapsed=0
    local spinstr='|/-\'

    log_step "Waiting for container networking..."

    while [[ $elapsed -lt $timeout ]]; do
        # Check if container has IP address
        local ip
        ip=$(lxc list "$name" --format csv -c 4 2>/dev/null | cut -d' ' -f1)

        if [[ -n "$ip" && "$ip" != "" ]]; then
            # Has IP, now check internet connectivity
            if lxc exec "$name" -- ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
                printf "\r\033[K"  # Clear spinner line
                log_info "Network connectivity confirmed (IP: $ip)"
                return 0
            fi
        fi

        # Show spinner
        local temp=${spinstr#?}
        printf "\r  [%c] Waiting for network... (%ds/%ds)" "$spinstr" "$elapsed" "$timeout"
        spinstr=$temp${spinstr%"$temp"}

        sleep 1
        ((elapsed++))
    done

    printf "\r\033[K"  # Clear spinner line
    log_error "Network connectivity failed after ${timeout} seconds"
    echo "Container is running for debugging:"
    echo "  lxc exec $name -- bash"
    echo "  lxc exec $name -- ip addr"
    echo "  lxc exec $name -- ping 8.8.8.8"
    return 1
}
```

### Pattern 6: Basic Package Installation
**What:** Install essential packages in container
**When to use:** After network connectivity confirmed
**Example:**
```bash
# Source: Existing 02-create-container.sh + CONTEXT.md

install_basic_packages() {
    local name="$1"

    log_step "Installing basic packages..."

    lxc exec "$name" -- bash -c '
        # Wait for apt to be available (cloud-init might be running)
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
            sleep 1
        done

        # Update package lists
        apt-get update -qq

        # Install essential packages
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            ca-certificates \
            curl \
            git \
            openssh-server \
            sudo

        # Enable SSH
        systemctl enable ssh
        systemctl start ssh
    '

    log_info "Basic packages installed"
}
```

### Anti-Patterns to Avoid

- **Not stopping container before snapshot:** While snapshots work on running containers, stopping first is cleaner and faster
- **Using `--force` flag for deletion without prompt:** Always prompt for destructive operations
- **Hardcoding CPU count:** Use `nproc` to match host
- **Using hard memory limits when soft is intended:** Explicitly set `limits.memory.enforce=soft`
- **Not waiting for cloud-init:** Container may still be initializing; check apt lock before package operations
- **Busy-wait loop without sleep:** Always include sleep in wait loops to avoid CPU spin

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Container image selection | Custom image download | `ubuntu:24.04` alias | LXD handles image caching, updates |
| Resource limit configuration | Custom cgroup manipulation | `lxc config set limits.*` | LXD handles cgroup v1/v2 differences |
| TUN device passthrough | Manual mknod + mount | `lxc config device add unix-char` | LXD handles permissions, cleanup |
| Container state detection | Parse `lxc info` output | `lxc list --format csv` columns | Structured output, reliable parsing |
| Snapshot naming | Manual timestamp generation | `date +%Y%m%d-%H%M%S` pattern | Standard, sortable format |

**Key insight:** LXD's `lxc config` commands abstract away the complexity of cgroups, device permissions, and container internals. Use them instead of trying to configure raw LXC parameters.

## Common Pitfalls

### Pitfall 1: Container Restart After TUN Device Addition
**What goes wrong:** TUN device not available inside container
**Why it happens:** Device configuration applied but container not restarted
**How to avoid:** Always restart container after adding TUN device
**Warning signs:** `tailscale up` fails with "TUN device not found"
```bash
# Required after device add
lxc restart "$name"
```

### Pitfall 2: Hard Memory Limit Causing OOM
**What goes wrong:** Container processes killed when exceeding 4GB
**Why it happens:** Default `limits.memory.enforce=hard`
**How to avoid:** Explicitly set `limits.memory.enforce=soft`
**Warning signs:** Processes die unexpectedly, `dmesg` shows OOM killer

### Pitfall 3: cloud-init Holding apt Lock
**What goes wrong:** `apt-get` fails with lock error
**Why it happens:** Ubuntu cloud images run cloud-init on first boot, which uses apt
**How to avoid:** Wait for lock release before apt operations
**Warning signs:** "Could not get lock /var/lib/dpkg/lock-frontend"
```bash
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 1
done
```

### Pitfall 4: Network Check Without IP Verification
**What goes wrong:** Ping succeeds but container has no usable IP
**Why it happens:** Checking only ping, not IP assignment
**How to avoid:** Check BOTH IP address exists AND ping works
**Warning signs:** Container appears connected but SSH/HTTP fails

### Pitfall 5: Deleting Container With Snapshots Attached
**What goes wrong:** Delete fails or requires multiple attempts
**Why it happens:** LXD protects containers with snapshots
**How to avoid:** Use `--force` flag when confirmed, or delete snapshots first
**Warning signs:** "Error: The instance has snapshots"

### Pitfall 6: Accepting Invalid Container Names
**What goes wrong:** Container created but Tailscale MagicDNS fails
**Why it happens:** Names not validated against DNS rules
**How to avoid:** Validate DNS-style naming before creation
**Warning signs:** Container works but `name.tailnet.ts.net` doesn't resolve

## Code Examples

Verified patterns from official sources:

### Complete Container Creation Sequence
```bash
# Source: LXD documentation + Phase 2 requirements

CONTAINER_NAME="relay-dev"

# 1. Launch container
lxc launch ubuntu:24.04 "$CONTAINER_NAME"

# 2. Configure TUN device
lxc config set "$CONTAINER_NAME" security.nesting=true
lxc config device add "$CONTAINER_NAME" tun unix-char path=/dev/net/tun

# 3. Set soft memory limit
lxc config set "$CONTAINER_NAME" limits.memory=4GB
lxc config set "$CONTAINER_NAME" limits.memory.enforce=soft
lxc config set "$CONTAINER_NAME" limits.memory.swap=true

# 4. Set CPU limit (match host)
lxc config set "$CONTAINER_NAME" limits.cpu=$(nproc)

# 5. Restart to apply device config
lxc restart "$CONTAINER_NAME"

# 6. Wait for networking
sleep 5  # Allow restart to complete
for i in {1..60}; do
    if lxc exec "$CONTAINER_NAME" -- ping -c 1 8.8.8.8 &>/dev/null; then
        break
    fi
    sleep 1
done
```

### Snapshot and Delete Sequence
```bash
# Source: LXD snapshot documentation

CONTAINER_NAME="relay-dev"
SNAPSHOT_NAME="backup-$(date +%Y%m%d-%H%M%S)"

# Create snapshot (container can be running or stopped)
lxc snapshot "$CONTAINER_NAME" "$SNAPSHOT_NAME"

# Verify snapshot
lxc info "$CONTAINER_NAME" | grep -A5 "Snapshots:"

# Delete container (with snapshots)
lxc delete "$CONTAINER_NAME" --force

# To restore from snapshot (if container recreated):
# 1. Create new container
# 2. lxc restore "$CONTAINER_NAME" "$SNAPSHOT_NAME"
```

### Get Container IP Address
```bash
# Source: LXD lxc list documentation

CONTAINER_NAME="relay-dev"

# Get IPv4 address (format: "10.10.10.5 (eth0)")
IP_FULL=$(lxc list "$CONTAINER_NAME" --format csv -c 4)

# Extract just the IP
IP=$(echo "$IP_FULL" | cut -d' ' -f1)

echo "Container IP: $IP"
```

### Reserved Name List
```bash
# Source: LXD common reserved names + networking defaults

RESERVED_NAMES=(
    "default"      # LXD default profile
    "host"         # Refers to host system
    "localhost"    # Loopback name
    "lxdbr0"       # Default bridge name
    "none"         # Keyword in LXD
    "self"         # Self-reference
    "all"          # Keyword in LXD
    "container"    # Generic, confusing
    "lxc"          # Confusing with tooling
    "lxd"          # Confusing with tooling
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual cgroup config | `lxc config set limits.*` | LXD 2.0 (2016) | Abstracts cgroup v1/v2 differences |
| `lxc launch -c` for each config | Multiple `lxc config set` calls | Still valid | Both work, separate calls more readable |
| Fixed CPU count | `nproc` for host matching | Best practice | Containers can use all host CPUs |
| Hard memory limits only | `limits.memory.enforce=soft` | LXD 2.0+ | Allows bursting when resources available |
| Raw LXC config for TUN | `lxc config device add unix-char` | LXD 3.0+ | Cleaner, supported, hotpluggable |

**Deprecated/outdated:**
- **Editing raw.lxc for TUN device:** While possible, `unix-char` device type is preferred
- **cgroup v1 specific configuration:** LXD abstracts this; use `limits.*` options
- **Manual device node creation:** LXD handles this with device add

## Open Questions

Things that couldn't be fully resolved:

1. **TUN device hotplug on restart**
   - What we know: Device must be added, container restarted for activation
   - What's unclear: Can device be hotplugged without restart in newer LXD?
   - Recommendation: Always restart after adding TUN device (documented behavior)

2. **Stateful snapshots for backup**
   - What we know: `--stateful` captures running state but has CRIU dependencies
   - What's unclear: Reliability with systemd in containers
   - Recommendation: Use regular snapshots (not stateful) for backup before deletion

3. **IP assignment timing**
   - What we know: DHCP from lxdbr0 usually completes in 1-5 seconds
   - What's unclear: Maximum reasonable wait time for slow systems
   - Recommendation: 60 second timeout as per CONTEXT.md decision, leave running for debug

## Sources

### Primary (HIGH confidence)
- [How to create instances - LXD documentation](https://documentation.ubuntu.com/lxd/latest/howto/instances_create/) - Container creation commands
- [Instance options - LXD documentation](https://documentation.ubuntu.com/lxd/latest/reference/instance_options/) - Memory and CPU limits configuration
- [lxc snapshot - LXD documentation](https://documentation.ubuntu.com/lxd/latest/reference/manpages/lxc/snapshot/) - Snapshot command syntax
- [lxc list - LXD documentation](https://documentation.ubuntu.com/lxd/latest/reference/manpages/lxc/list/) - Column format for IP retrieval
- [Tailscale in LXC containers](https://tailscale.com/kb/1130/lxc-unprivileged) - TUN device requirements

### Secondary (MEDIUM confidence)
- [LXD 2.0: Resource control](https://ubuntu.com/blog/lxd-2-0-resource-control-412) - Soft vs hard memory limits
- [How to Display a Spinner for Long Running Tasks in Bash](https://www.baeldung.com/linux/bash-show-spinner-long-tasks) - Spinner patterns
- [RFC 1123 hostname validation](https://datatracker.ietf.org/doc/html/rfc1123) - DNS naming rules

### Tertiary (LOW confidence)
- Linux Containers Forum discussions on TUN device issues - Edge case handling

## Metadata

**Confidence breakdown:**
- Container creation commands: HIGH - Official LXD documentation
- Resource limits (soft memory): HIGH - Official documentation with clear examples
- TUN device configuration: HIGH - Multiple verified sources including Tailscale official docs
- Naming validation: MEDIUM - Based on RFC 1123, adapted for container context
- Spinner/wait patterns: MEDIUM - Community best practices

**Research date:** 2026-02-01
**Valid until:** ~90 days (LXD stable, patterns unlikely to change)

**User context constraints applied:**
- Memory: 4GB soft limit researched
- CPU: Host matching via `nproc` researched
- Disk: No quota (not researched - deferred)
- Swap: Allow swap researched (`limits.memory.swap=true`)
- Container naming: DNS-style pattern researched
- Reserved names: List compiled
- Invalid name error: Detailed message pattern provided
- Existing container: Prompt + snapshot + delete pattern researched
- Network timeout: 60 seconds with spinner researched
- Connectivity test: IP check + ping pattern researched
- On timeout: Fail with debug info pattern provided
