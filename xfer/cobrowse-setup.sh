#!/usr/bin/env bash
# =============================================================================
# Co-Browse Setup for Claude Code CLI + noVNC
# =============================================================================
# Sets up a shared browser environment on a Linux (LXC) container where:
#   - Chromium runs in a virtual framebuffer (Xvfb)
#   - Claude Code CLI can see/interact with the browser via DISPLAY
#   - You connect from your local browser via noVNC over Tailscale
#
# Usage:
#   chmod +x cobrowse-setup.sh
#   sudo ./cobrowse-setup.sh          # Install dependencies
#   ./cobrowse-start.sh               # Start the co-browse session (created by this script)
#   ./cobrowse-stop.sh                # Stop the session
#
# Then open: http://<container-tailscale-ip>:6080/vnc.html
# =============================================================================

set -euo pipefail

# --- Configuration ---
DISPLAY_NUM="${COBROWSE_DISPLAY:-99}"
RESOLUTION="${COBROWSE_RESOLUTION:-1920x1080x24}"
VNC_PORT="${COBROWSE_VNC_PORT:-5900}"
NOVNC_PORT="${COBROWSE_NOVNC_PORT:-6080}"
NOVNC_DIR="/opt/noVNC"
WEBSOCKIFY_DIR="/opt/noVNC/utils/websockify"

echo "=== Co-Browse Environment Setup ==="
echo "Display:    :${DISPLAY_NUM}"
echo "Resolution: ${RESOLUTION}"
echo "VNC Port:   ${VNC_PORT}"
echo "noVNC Port: ${NOVNC_PORT}"
echo ""

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script with sudo for installation."
    exit 1
fi

# --- Detect package manager ---
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
else
    echo "ERROR: Unsupported package manager. Need apt or dnf."
    exit 1
fi

# --- Install dependencies ---
echo ">>> Installing dependencies..."

if [[ "$PKG_MGR" == "apt" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq \
        xvfb \
        x11vnc \
        xdotool \
        xterm \
        mousepad \
        imagemagick \
        git \
        python3 \
        python3-numpy \
        procps \
        net-tools \
        curl \
        ca-certificates \
        fonts-liberation \
        fonts-noto-color-emoji \
        dbus-x11 \
        2>/dev/null
    # Chromium: try chromium-browser first, fall back to chromium or snap
    apt-get install -y -qq chromium-browser 2>/dev/null \
        || apt-get install -y -qq chromium 2>/dev/null \
        || snap install chromium 2>/dev/null \
        || echo "WARNING: Could not install Chromium. Install manually."
elif [[ "$PKG_MGR" == "dnf" ]]; then
    dnf install -y \
        xorg-x11-server-Xvfb \
        x11vnc \
        chromium \
        xdotool \
        xterm \
        mousepad \
        ImageMagick \
        git \
        python3 \
        python3-numpy \
        procps-ng \
        net-tools \
        curl \
        ca-certificates \
        google-noto-emoji-color-fonts \
        dbus-x11 \
        2>/dev/null
fi

# --- Install noVNC ---
echo ">>> Installing noVNC..."
if [[ ! -d "$NOVNC_DIR" ]]; then
    git clone --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR"
    git clone --depth 1 https://github.com/novnc/websockify.git "$WEBSOCKIFY_DIR"
else
    echo "    noVNC already installed at $NOVNC_DIR"
fi

# --- Create start script ---
CALLER_HOME=$(eval echo ~${SUDO_USER:-$USER})
START_SCRIPT="${CALLER_HOME}/cobrowse-start.sh"

cat > "$START_SCRIPT" << 'STARTEOF'
#!/usr/bin/env bash
# =============================================================================
# Start Co-Browse Session
# =============================================================================
set -euo pipefail

DISPLAY_NUM="${COBROWSE_DISPLAY:-99}"
RESOLUTION="${COBROWSE_RESOLUTION:-1920x1080x24}"
VNC_PORT="${COBROWSE_VNC_PORT:-5900}"
NOVNC_PORT="${COBROWSE_NOVNC_PORT:-6080}"
NOVNC_DIR="/opt/noVNC"
PIDDIR="${HOME}/.cobrowse"

mkdir -p "$PIDDIR"

export DISPLAY=":${DISPLAY_NUM}"

# --- Kill any existing session ---
if [[ -f "$PIDDIR/xvfb.pid" ]]; then
    echo "Stopping existing session..."
    bash "$(dirname "$0")/cobrowse-stop.sh" 2>/dev/null || true
    sleep 1
fi

echo "=== Starting Co-Browse Session ==="

# --- Start Xvfb ---
echo ">>> Starting Xvfb on :${DISPLAY_NUM} (${RESOLUTION})..."
Xvfb ":${DISPLAY_NUM}" -screen 0 "${RESOLUTION}" -ac +extension GLX +render -noreset &
XVFB_PID=$!
echo $XVFB_PID > "$PIDDIR/xvfb.pid"
sleep 1

# Verify Xvfb is running
if ! kill -0 $XVFB_PID 2>/dev/null; then
    echo "ERROR: Xvfb failed to start"
    exit 1
fi

# --- Start dbus (needed by Chromium) ---
if command -v dbus-launch &>/dev/null; then
    eval $(dbus-launch --sh-syntax)
    echo $DBUS_SESSION_BUS_PID > "$PIDDIR/dbus.pid" 2>/dev/null || true
fi

# --- Start x11vnc ---
echo ">>> Starting x11vnc on port ${VNC_PORT}..."
x11vnc \
    -display ":${DISPLAY_NUM}" \
    -nopw \
    -listen 0.0.0.0 \
    -rfbport "${VNC_PORT}" \
    -shared \
    -forever \
    -noxdamage \
    -cursor most \
    -bg \
    -o "$PIDDIR/x11vnc.log"
sleep 1

# Get x11vnc PID
pgrep -f "x11vnc.*:${DISPLAY_NUM}" > "$PIDDIR/x11vnc.pid" 2>/dev/null || true

# --- Start noVNC via websockify directly ---
echo ">>> Starting noVNC on port ${NOVNC_PORT}..."
cd "$NOVNC_DIR"
python3 utils/websockify/run --web . --heartbeat 30 ${NOVNC_PORT} localhost:${VNC_PORT} &
NOVNC_PID=$!
echo $NOVNC_PID > "$PIDDIR/novnc.pid"
sleep 1

# --- Launch Chromium ---
echo ">>> Launching Chromium..."
CHROMIUM_BIN=""
for bin in chromium-browser chromium google-chrome /snap/bin/chromium; do
    if command -v "$bin" &>/dev/null || [[ -x "$bin" ]]; then
        CHROMIUM_BIN="$bin"
        break
    fi
done

if [[ -z "$CHROMIUM_BIN" ]]; then
    echo "WARNING: No Chromium/Chrome found. You can launch a browser manually."
else
    $CHROMIUM_BIN \
        --no-sandbox \
        --disable-gpu \
        --disable-dev-shm-usage \
        --disable-software-rasterizer \
        --window-size=1920,1080 \
        --start-maximized \
        --no-first-run \
        --disable-default-apps \
        --disable-extensions \
        "about:blank" &
    CHROMIUM_PID=$!
    echo $CHROMIUM_PID > "$PIDDIR/chromium.pid"
fi

sleep 2

# --- Get Tailscale IP ---
TS_IP=""
if command -v tailscale &>/dev/null; then
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
fi

echo ""
echo "=========================================="
echo "  Co-Browse Session Ready!"
echo "=========================================="
echo ""
echo "  noVNC URL:  http://${TS_IP:-<container-ip>}:${NOVNC_PORT}/vnc.html"
echo "  VNC Port:   ${VNC_PORT}"
echo "  Display:    :${DISPLAY_NUM}"
echo ""
echo "  For Claude Code CLI, ensure:"
echo "    export DISPLAY=:${DISPLAY_NUM}"
echo ""
echo "  Stop with:  ~/cobrowse-stop.sh"
echo "=========================================="

# --- Write env file for Claude Code ---
cat > "$PIDDIR/env" << EOF
export DISPLAY=:${DISPLAY_NUM}
EOF

# --- Append DISPLAY to shell profile if not already set ---
PROFILE="${HOME}/.bashrc"
if ! grep -q "COBROWSE DISPLAY" "$PROFILE" 2>/dev/null; then
    echo "" >> "$PROFILE"
    echo "# COBROWSE DISPLAY - auto-set for Claude Code" >> "$PROFILE"
    echo 'export DISPLAY=:'"${DISPLAY_NUM}" >> "$PROFILE"
fi

STARTEOF

chmod +x "$START_SCRIPT"

# --- Create stop script ---
STOP_SCRIPT="${CALLER_HOME}/cobrowse-stop.sh"

cat > "$STOP_SCRIPT" << 'STOPEOF'
#!/usr/bin/env bash
# =============================================================================
# Stop Co-Browse Session
# =============================================================================
set -uo pipefail

PIDDIR="${HOME}/.cobrowse"

echo "=== Stopping Co-Browse Session ==="

for svc in chromium novnc x11vnc dbus xvfb; do
    PIDFILE="$PIDDIR/${svc}.pid"
    if [[ -f "$PIDFILE" ]]; then
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo ">>> Stopping ${svc} (PID ${PID})..."
            kill "$PID" 2>/dev/null || true
        fi
        rm -f "$PIDFILE"
    fi
done

# Cleanup any remaining orphans
pkill -f "Xvfb :${COBROWSE_DISPLAY:-99}" 2>/dev/null || true
pkill -f "x11vnc.*:${COBROWSE_DISPLAY:-99}" 2>/dev/null || true
pkill -f "novnc_proxy" 2>/dev/null || true
pkill -f "websockify.*6080" 2>/dev/null || true

echo "Session stopped."
STOPEOF

chmod +x "$STOP_SCRIPT"

# --- Ownership ---
chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$START_SCRIPT" "$STOP_SCRIPT" 2>/dev/null || true

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Start session:    ~/cobrowse-start.sh"
echo "  2. Open in browser:  http://<tailscale-ip>:${NOVNC_PORT}/vnc.html"
echo "  3. Run Claude Code:  (DISPLAY is auto-exported in .bashrc)"
echo "  4. Stop session:     ~/cobrowse-stop.sh"
echo ""
echo "Optional env vars (set before running cobrowse-start.sh):"
echo "  COBROWSE_DISPLAY=99       Virtual display number"
echo "  COBROWSE_RESOLUTION=1920x1080x24"
echo "  COBROWSE_VNC_PORT=5900"
echo "  COBROWSE_NOVNC_PORT=6080"
echo ""
