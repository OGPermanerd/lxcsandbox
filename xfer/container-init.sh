#!/usr/bin/env bash
# =============================================================================
# Container Init Script for Claude Code CLI Dev Environment
# =============================================================================
# Run this on a fresh LXC container to provision:
#   1. Co-browse environment (Xvfb + x11vnc + noVNC + Chromium)
#   2. Clipboard bridge (tsclip integration)
#   3. CLAUDE.md with co-browse and clipboard instructions
#
# Prerequisites:
#   - Tailscale installed and connected on the container
#   - A tsclip server running somewhere on the tailnet
#
# Usage:
#   sudo ./container-init.sh [--tsclip-host <ip_or_hostname>] [--tsclip-port <port>] [--user <username>]
#
# Examples:
#   sudo ./container-init.sh
#   sudo ./container-init.sh --tsclip-host 100.68.60.121 --tsclip-port 9876
#   sudo ./container-init.sh --tsclip-host 100.68.60.121 --user dev
# =============================================================================

set -euo pipefail

# --- Defaults ---
TSCLIP_HOST="${TSCLIP_HOST:-100.68.60.121}"
TSCLIP_PORT="${TSCLIP_PORT:-9876}"
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(whoami)}}"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tsclip-host) TSCLIP_HOST="$2"; shift 2 ;;
        --tsclip-port) TSCLIP_PORT="$2"; shift 2 ;;
        --user)        TARGET_USER="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: sudo $0 [--tsclip-host <ip>] [--tsclip-port <port>] [--user <username>]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

TSCLIP_URL="http://${TSCLIP_HOST}:${TSCLIP_PORT}"
TARGET_HOME=$(eval echo ~${TARGET_USER})

echo "=== Container Init for Claude Code CLI ==="
echo "User:       ${TARGET_USER}"
echo "Home:       ${TARGET_HOME}"
echo "tsclip:     ${TSCLIP_URL}"
echo ""

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run with sudo"
    exit 1
fi

# =============================================================================
# 1. Co-Browse Environment
# =============================================================================
echo ">>> [1/3] Setting up co-browse environment..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COBROWSE_SETUP="${SCRIPT_DIR}/cobrowse-setup.sh"

if [[ -f "$COBROWSE_SETUP" ]]; then
    bash "$COBROWSE_SETUP"
else
    echo "ERROR: cobrowse-setup.sh not found at ${COBROWSE_SETUP}"
    echo "       Place it alongside this script and re-run."
    exit 1
fi

# =============================================================================
# 2. Clipboard Bridge
# =============================================================================
echo ""
echo ">>> [2/3] Setting up clipboard bridge..."

# Create clip/getclip commands
cat > /usr/local/bin/clip << CLIPEOF
#!/usr/bin/env bash
# Send stdin to tsclip server
curl -s -X POST -d @- "${TSCLIP_URL}/copy"
CLIPEOF
chmod +x /usr/local/bin/clip

cat > /usr/local/bin/getclip << GETCLIPEOF
#!/usr/bin/env bash
# Read from tsclip server
curl -s "${TSCLIP_URL}/paste"
GETCLIPEOF
chmod +x /usr/local/bin/getclip

# Add tsclip env to bashrc if not present
BASHRC="${TARGET_HOME}/.bashrc"
if ! grep -q "TSCLIP" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << RCEOF

# TSCLIP - shared clipboard bridge
export TSCLIP_URL="${TSCLIP_URL}"
RCEOF
fi

echo "    Installed: /usr/local/bin/clip, /usr/local/bin/getclip"

# =============================================================================
# 3. CLAUDE.md
# =============================================================================
echo ""
echo ">>> [3/3] Writing CLAUDE.md..."

# Detect Tailscale hostname and IP
TS_HOSTNAME=""
TS_IP=""
if command -v tailscale &>/dev/null; then
    TS_HOSTNAME=$(tailscale status --self=true --peers=false 2>/dev/null | awk '{print $2}' || true)
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
fi

CLAUDE_MD="${TARGET_HOME}/CLAUDE.md"

# Only write if it doesn't exist — don't overwrite user customizations
if [[ -f "$CLAUDE_MD" ]]; then
    echo "    CLAUDE.md already exists at ${CLAUDE_MD} — skipping."
    echo "    To regenerate, delete it and re-run this script."
else
    cat > "$CLAUDE_MD" << CLAUDEEOF
# Claude Code CLI — Container Environment

## Container Info
- Tailscale hostname: ${TS_HOSTNAME:-<unknown>}
- Tailscale IP: ${TS_IP:-<unknown>}

## Co-Browse Environment
A shared Chromium browser runs on virtual display :99, accessible to both you and the user.
- The user sees the browser via noVNC at http://${TS_IP:-<container-ip>}:6080/vnc.html
- You can interact with it using DISPLAY=:99 and standard X11 tools

**Starting a co-browse session:**
\`\`\`bash
~/cobrowse-start.sh    # starts Xvfb, x11vnc, noVNC, and Chromium
~/cobrowse-stop.sh     # stops everything
\`\`\`

**Browser interaction tools:**
\`\`\`bash
export DISPLAY=:99
import -window root /tmp/screenshot.png    # full screen capture
xdotool key ctrl+l                          # focus URL bar
xdotool type "https://example.com"          # type a URL
xdotool key Return                          # press Enter
xdotool mousemove 500 300                   # move mouse
xdotool click 1                             # left click
xdotool key ctrl+a                          # select all
xdotool key ctrl+c                          # copy
xdotool key ctrl+v                          # paste
xdotool key Tab                             # move between fields
\`\`\`

**Rules:**
- Always take a screenshot first to understand the current browser state before interacting
- Narrate what you're doing so the user can follow along in noVNC
- Pause between actions to let pages load (sleep 1-2 seconds)
- The user can also interact with the browser at any time — check the screen state before acting
- For sensitive fields (passwords, API keys), ask the user to type them directly via noVNC rather than handling credentials yourself

## Clipboard Bridge
A shared clipboard server runs at ${TSCLIP_URL} on the Tailscale network.

**To send text to the user (URLs, config values, tokens, commands for their browser):**
  echo "value" | clip

**To read text the user has pasted from their local machine:**
  getclip

**Rules:**
- Use the co-browse environment when possible instead of clipboard for visual tasks
- For non-browser text exchange, use clip/getclip as before
- When you need the user to provide a value (API key, token, etc), tell them to paste it in the browser UI at ${TSCLIP_URL} then use getclip to retrieve it
- For multi-line content, use printf with literal \\n newlines, NOT echo. Example:
  printf "## Step 1\\nGo to console.cloud.google.com\\n\\n## Step 2\\nClick Create Credentials\\n" | clip

## Clipboard formatting
When sending multi-line instructions to clip, use printf with literal \\n newlines, NOT echo. Example:
  printf "## Step 1\\nGo to console.cloud.google.com\\n\\n## Step 2\\nClick Create Credentials\\n" | clip
This preserves line breaks in the browser UI so the user can read the instructions.
CLAUDEEOF

    chown "${TARGET_USER}:${TARGET_USER}" "$CLAUDE_MD"
    echo "    Written to ${CLAUDE_MD}"
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo "=========================================="
echo "  Container Init Complete!"
echo "=========================================="
echo ""
echo "  Quick start:"
echo "    1. su - ${TARGET_USER}"
echo "    2. ~/cobrowse-start.sh"
echo "    3. Open http://${TS_IP:-<tailscale-ip>}:6080/vnc.html"
echo "    4. Run: claude   (Claude Code CLI)"
echo ""
echo "  Clipboard test:"
echo "    echo 'hello' | clip     # send to local clipboard"
echo "    getclip                  # read from local clipboard"
echo ""
echo "  Files created:"
echo "    ~/cobrowse-start.sh     # start co-browse session"
echo "    ~/cobrowse-stop.sh      # stop co-browse session"
echo "    ~/CLAUDE.md             # Claude Code instructions"
echo "    /usr/local/bin/clip     # clipboard send"
echo "    /usr/local/bin/getclip  # clipboard receive"
echo "=========================================="
