#!/usr/bin/env bash
set -euo pipefail

# tmuxonwatch Server Installer
# Usage: bash install.sh
# Or:    bash <(curl -sSL tmuxonwatch.com/install)
#
# Idempotent — safe to run multiple times.
# Preserves existing auth tokens and configurations.

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Auto-detect script location if run from repo, otherwise default to ~/tmuxonwatch/server
if [[ -f "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/server/main.py" ]]; then
        INSTALL_DIR="$SCRIPT_DIR/server"
    else
        INSTALL_DIR="$HOME/tmuxonwatch/server"
    fi
else
    INSTALL_DIR="$HOME/tmuxonwatch/server"
fi
CONFIG_DIR="$HOME/.config/tmuxonwatch"
PLIST_NAME="com.tmuxonwatch.server"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
PORT=8787

# Legacy paths (for migration from older installs)
OLD_CONFIG_DIR="$HOME/.config/terminalpulse"
OLD_PLIST_NAME="com.terminalpulse.server"
OLD_PLIST_DEST="$HOME/Library/LaunchAgents/$OLD_PLIST_NAME.plist"

info()  { echo -e "${CYAN}=>${RESET} $1"; }
ok()    { echo -e "${GREEN}✓${RESET} $1"; }
warn()  { echo -e "${YELLOW}!${RESET} $1"; }
fail()  { echo -e "${RED}✗ $1${RESET}"; exit 1; }

echo ""
echo -e "${BOLD}tmuxonwatch Server Installer${RESET}"
echo "─────────────────────────────────"
echo ""

# ── Check prerequisites ───────────────────────────────────
info "Checking prerequisites..."

if [[ "$(uname)" != "Darwin" ]]; then
    fail "tmuxonwatch server requires macOS."
fi

# Find Python 3.10+ (prefer homebrew, then system)
PYTHON=""
for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 python3 python; do
    if command -v "$candidate" &>/dev/null; then
        version=$("$candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
        major="${version%%.*}"
        minor="${version#*.}"
        if [[ "$major" -ge 3 && "$minor" -ge 10 ]]; then
            PYTHON="$candidate"
            break
        fi
    fi
done

if [[ -z "$PYTHON" ]]; then
    fail "Python 3.10+ required. Install via: brew install python3"
fi
ok "Found $($PYTHON --version)"

if ! command -v tmux &>/dev/null; then
    fail "tmux not found. Install via: brew install tmux"
fi
ok "Found tmux $(tmux -V | awk '{print $2}')"

# ── Detect network address for iOS connectivity ──────────
info "Detecting network address..."

SERVER_HOST=""
BIND_HOST="0.0.0.0"

# 1. Check for Tailscale
if command -v tailscale &>/dev/null; then
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
    TS_STATUS=$(tailscale status --self --json 2>/dev/null || true)
    TS_HOSTNAME=""
    if [[ -n "$TS_STATUS" ]]; then
        TS_HOSTNAME=$("$PYTHON" -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('Self',{}).get('DNSName','').rstrip('.'))" "$TS_STATUS" 2>/dev/null || true)
    fi

    if [[ -n "$TS_IP" ]]; then
        if [[ -n "$TS_HOSTNAME" ]]; then
            SERVER_HOST="$TS_HOSTNAME"
            ok "Tailscale detected: $TS_HOSTNAME ($TS_IP)"
        else
            SERVER_HOST="$TS_IP"
            ok "Tailscale detected: $TS_IP"
        fi
    fi
fi

# 2. Fall back to local network IP
if [[ -z "$SERVER_HOST" ]]; then
    LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
    if [[ -n "$LAN_IP" ]]; then
        SERVER_HOST="$LAN_IP"
        ok "Using local network IP: $LAN_IP"
        warn "Your iPhone must be on the same Wi-Fi network"
        warn "For remote access, install Tailscale: https://tailscale.com"
    fi
fi

# 3. Last resort — localhost (won't work from iPhone)
if [[ -z "$SERVER_HOST" ]]; then
    SERVER_HOST="127.0.0.1"
    warn "No network interface found — using localhost"
    warn "This will NOT work from your iPhone!"
    warn "Install Tailscale (https://tailscale.com) or connect to Wi-Fi"
    echo ""
    echo -ne "  Continue anyway? [y/N] "
    read -r CONTINUE < /dev/tty 2>/dev/null || CONTINUE="y"
    if [[ "${CONTINUE,,}" != "y" ]]; then
        echo ""
        info "Install Tailscale, then re-run this script."
        exit 0
    fi
fi

SERVER_URL="http://${SERVER_HOST}:${PORT}"

# ── Migrate from legacy terminalpulse install ─────────────
if [[ -f "$OLD_CONFIG_DIR/env" && ! -f "$CONFIG_DIR/env" ]]; then
    info "Migrating config from terminalpulse..."
    mkdir -p "$CONFIG_DIR"
    cp "$OLD_CONFIG_DIR/env" "$CONFIG_DIR/env"
    chmod 600 "$CONFIG_DIR/env"
    ok "Migrated auth token from $OLD_CONFIG_DIR"
fi

# Clean up old terminalpulse launchd service if present
if launchctl print "gui/$(id -u)/$OLD_PLIST_NAME" &>/dev/null; then
    info "Removing legacy terminalpulse service..."
    launchctl bootout "gui/$(id -u)/$OLD_PLIST_NAME" 2>/dev/null || true
    rm -f "$OLD_PLIST_DEST"
    ok "Removed legacy service"
fi

# ── Server files ─────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
GITHUB_RAW="https://raw.githubusercontent.com/beneaug/TerminalPulse/main/server"
SERVER_FILES="main.py tmux_bridge.py ansi_parser.py requirements.txt"

# Download/update server files from GitHub (skip if running from repo)
if [[ "$INSTALL_DIR" != *"TerminalPulse"* ]]; then
    info "Downloading server files..."
    for f in $SERVER_FILES; do
        if curl -sSfL "$GITHUB_RAW/$f" -o "$INSTALL_DIR/$f" 2>/dev/null; then
            ok "Downloaded $f"
        else
            if [[ -f "$INSTALL_DIR/$f" ]]; then
                warn "Could not update $f — using existing copy"
            else
                fail "Could not download $f and no existing copy found"
            fi
        fi
    done
else
    info "Running from repo — using local server files at $INSTALL_DIR"
fi

# ── Create / verify virtual environment ───────────────────
VENV_OK=false
if [[ -d "$INSTALL_DIR/.venv" ]]; then
    # Check if existing venv Python is 3.10+
    VENV_PY_VERSION=$("$INSTALL_DIR/.venv/bin/python3" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
    VENV_MAJOR="${VENV_PY_VERSION%%.*}"
    VENV_MINOR="${VENV_PY_VERSION#*.}"
    if [[ "$VENV_MAJOR" -ge 3 && "$VENV_MINOR" -ge 10 ]]; then
        ok "Venv already exists (Python $VENV_PY_VERSION)"
        VENV_OK=true
    else
        warn "Existing venv uses Python $VENV_PY_VERSION (need 3.10+), recreating..."
        rm -rf "$INSTALL_DIR/.venv"
    fi
fi

if [[ "$VENV_OK" == "false" ]]; then
    info "Setting up Python virtual environment..."
    "$PYTHON" -m venv "$INSTALL_DIR/.venv"
    ok "Created venv (Python $("$INSTALL_DIR/.venv/bin/python3" --version | awk '{print $2}'))"
fi

info "Installing dependencies..."
"$INSTALL_DIR/.venv/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt" 2>/dev/null || {
    "$INSTALL_DIR/.venv/bin/pip" install -q fastapi "uvicorn[standard]"
}
# Install qrcode so QR always works in the terminal
"$INSTALL_DIR/.venv/bin/pip" install -q qrcode 2>/dev/null || true
ok "Dependencies installed"

# ── Generate / preserve token ─────────────────────────────
mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_DIR/env" ]]; then
    source "$CONFIG_DIR/env" 2>/dev/null || true
    if [[ -n "${TP_TOKEN:-}" && "${TP_TOKEN}" != "changeme" ]]; then
        ok "Using existing auth token"
    else
        TP_TOKEN=$("$PYTHON" -c "import secrets; print(secrets.token_urlsafe(32))")
        echo "export TP_TOKEN=\"$TP_TOKEN\"" > "$CONFIG_DIR/env"
        chmod 600 "$CONFIG_DIR/env"
        ok "Generated new auth token (old one was invalid)"
    fi
else
    TP_TOKEN=$("$PYTHON" -c "import secrets; print(secrets.token_urlsafe(32))")
    echo "export TP_TOKEN=\"$TP_TOKEN\"" > "$CONFIG_DIR/env"
    chmod 600 "$CONFIG_DIR/env"
    ok "Generated auth token"
fi

# ── Stop existing service gracefully ──────────────────────
if launchctl print "gui/$(id -u)/$PLIST_NAME" &>/dev/null; then
    info "Stopping existing service..."
    launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
    sleep 1
fi

# ── Create launchd plist (binds to 0.0.0.0 for LAN/Tailscale access) ──
info "Installing launchd service..."

cat > "$PLIST_DEST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>source "\$HOME/.config/tmuxonwatch/env" 2>/dev/null; exec "$INSTALL_DIR/.venv/bin/python3" -m uvicorn main:app --host $BIND_HOST --port $PORT</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/tmuxonwatch.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/tmuxonwatch.err.log</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST" 2>/dev/null || launchctl load "$PLIST_DEST" 2>/dev/null
ok "Service installed and started"

# ── Wait for server ───────────────────────────────────────
info "Waiting for server to start..."
SERVER_STARTED=false
for i in $(seq 1 10); do
    if curl -sf "http://127.0.0.1:$PORT/health" > /dev/null 2>&1; then
        ok "Server is running on port $PORT"
        SERVER_STARTED=true
        break
    fi
    sleep 1
done

if [[ "$SERVER_STARTED" == "false" ]]; then
    warn "Server did not start within 10 seconds."
    warn "Check logs: /tmp/tmuxonwatch.err.log"
    if [[ ! -f "$INSTALL_DIR/main.py" ]]; then
        warn "Server files not found at $INSTALL_DIR — copy main.py, tmux_bridge.py, ansi_parser.py there first."
    fi
fi

# ── Output connection info ────────────────────────────────
echo ""
echo "─────────────────────────────────"
echo -e "${BOLD}${GREEN}Installation complete!${RESET}"
echo ""
echo -e "  Server:  ${CYAN}$SERVER_URL${RESET}"
echo -e "  Token:   ${CYAN}$TP_TOKEN${RESET}"
echo -e "  Config:  ${CYAN}$CONFIG_DIR/env${RESET}"
echo -e "  Logs:    ${CYAN}/tmp/tmuxonwatch.{out,err}.log${RESET}"
echo ""

# ── QR code for iOS pairing ──────────────────────────────
# Encode server URL + token as JSON for QR scanning
QR_PAYLOAD="{\"url\":\"$SERVER_URL\",\"token\":\"$TP_TOKEN\"}"

if command -v qrencode &>/dev/null; then
    echo -e "${BOLD}Scan this QR code in the tmux on watch iOS app:${RESET}"
    echo ""
    echo "$QR_PAYLOAD" | qrencode -t ANSIUTF8
    echo ""
elif "$INSTALL_DIR/.venv/bin/python3" -c "import qrcode" 2>/dev/null; then
    echo -e "${BOLD}Scan this QR code in the tmux on watch iOS app:${RESET}"
    echo ""
    "$INSTALL_DIR/.venv/bin/python3" -c "
import sys, qrcode
qr = qrcode.QRCode(border=1)
qr.add_data(sys.argv[1])
qr.print_ascii(invert=True)
" "$QR_PAYLOAD"
    echo ""
elif command -v "$PYTHON" &>/dev/null; then
    "$PYTHON" -c "
import sys
try:
    import qrcode
    qr = qrcode.QRCode(border=1)
    qr.add_data(sys.argv[1])
    qr.print_ascii(invert=True)
except ImportError:
    print('To display QR code: pip3 install qrcode  OR  brew install qrencode')
    print()
    print('Manual setup — enter these in the tmux on watch iOS app:')
    print(f'  Server URL: {sys.argv[2]}')
    print(f'  Token:      {sys.argv[3]}')
" "$QR_PAYLOAD" "$SERVER_URL" "$TP_TOKEN" 2>/dev/null || {
    echo "Manual setup — enter these in the tmux on watch iOS app:"
    echo -e "  Server URL: ${CYAN}$SERVER_URL${RESET}"
    echo -e "  Token:      ${CYAN}$TP_TOKEN${RESET}"
}
else
    echo "Manual setup — enter these in the tmux on watch iOS app:"
    echo -e "  Server URL: ${CYAN}$SERVER_URL${RESET}"
    echo -e "  Token:      ${CYAN}$TP_TOKEN${RESET}"
fi

echo ""
