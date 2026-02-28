#!/usr/bin/env bash
set -euo pipefail

# tmuxonwatch Server Installer
# Usage: bash install.sh
# Or:    bash <(curl -sSL https://tmuxonwatch.com/install)
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

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-N}"
    local choices="[y/N]"
    local answer=""
    local default_upper
    local answer_lower

    default_upper="$(printf '%s' "$default" | tr '[:lower:]' '[:upper:]')"
    if [[ "$default_upper" == "Y" ]]; then
        choices="[Y/n]"
    fi

    echo -ne "  ${prompt} ${choices} "
    if read -r answer < /dev/tty 2>/dev/null; then
        :
    else
        answer="$default"
    fi

    answer="${answer:-$default}"
    answer_lower="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$answer_lower" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

upsert_managed_block() {
    local file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local body="$4"
    local tmp

    mkdir -p "$(dirname "$file")"
    touch "$file"
    tmp="$(mktemp)"

    awk -v start="$start_marker" -v end="$end_marker" '
        BEGIN { skip = 0 }
        index($0, start) == 1 { skip = 1; next }
        skip && index($0, end) == 1 { skip = 0; next }
        !skip { print $0 }
    ' "$file" > "$tmp"

    mv "$tmp" "$file"
    {
        echo ""
        echo "$start_marker"
        printf "%s\n" "$body"
        echo "$end_marker"
    } >> "$file"
}

setup_optional_notify_hooks() {
    local notify_py="$1"
    local notify_script="$2"
    local hooks_dir="$CONFIG_DIR/hooks"
    local helper_script="$hooks_dir/notify-send"
    local shell_name shell_rc shell_block marker_start marker_end

    echo ""
    info "Optional setup: automatic command-finished alerts"
    echo "  tmuxonwatch can add a managed hook block to your shell config."
    echo "  This sends a remote push when a tmux command returns to prompt."
    echo "  It only edits your shell config if you approve below."

    if ! prompt_yes_no "Install automatic shell hooks for remote alerts?" "N"; then
        warn "Skipped shell hook setup."
        return
    fi

    mkdir -p "$hooks_dir"
    cat > "$helper_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
TMUXONWATCH_NOTIFY_PY="$notify_py"
TMUXONWATCH_NOTIFY_SCRIPT="$notify_script"
EVENT_ID="\${1:-manual-\$(date +%s)}"
TITLE="\${2:-Task complete}"
MESSAGE="\${3:-Waiting for input.}"
DURATION="\${4:-999}"
if [[ -x "\$TMUXONWATCH_NOTIFY_PY" && -f "\$TMUXONWATCH_NOTIFY_SCRIPT" ]]; then
  "\$TMUXONWATCH_NOTIFY_PY" "\$TMUXONWATCH_NOTIFY_SCRIPT" \\
    --event-id "\$EVENT_ID" \\
    --title "\$TITLE" \\
    --message "\$MESSAGE" \\
    --duration "\$DURATION" >/dev/null 2>&1 || true
fi
EOF
    chmod +x "$helper_script"

    cat > "$hooks_dir/README.md" <<EOF
tmuxonwatch hook helpers
========================

Helper command:
  $helper_script "<event_id>" "<title>" "<message>" "<duration_seconds>"

Examples:
  $helper_script "codex-task-\$(date +%s)" "Codex task complete" "Waiting for your input." "30"
  $helper_script "claude-action-\$(date +%s)" "Claude needs input" "Choose an option in terminal." "15"

Use this helper from any agent/tool hook system (Codex, Claude Code, CI, custom scripts).
EOF

    shell_name="$(basename "${SHELL:-zsh}")"
    case "$shell_name" in
        zsh)
            shell_rc="$HOME/.zshrc"
            shell_block=$(cat <<'EOF'
if [[ -z "${TMUXONWATCH_NOTIFY_HOOKS_INSTALLED:-}" ]]; then
  export TMUXONWATCH_NOTIFY_HOOKS_INSTALLED=1
  export TMUXONWATCH_NOTIFY_PY="__NOTIFY_PY__"
  export TMUXONWATCH_NOTIFY_SCRIPT="__NOTIFY_SCRIPT__"

  _tmuxonwatch_notify_flush() {
    if [[ -x "$TMUXONWATCH_NOTIFY_PY" && -f "$TMUXONWATCH_NOTIFY_SCRIPT" ]]; then
      "$TMUXONWATCH_NOTIFY_PY" "$TMUXONWATCH_NOTIFY_SCRIPT" --flush-only >/dev/null 2>&1 || true
    fi
  }

  _tmuxonwatch_notify_send() {
    local event_id="$1"
    local title="$2"
    local message="$3"
    local duration="$4"
    if [[ -x "$TMUXONWATCH_NOTIFY_PY" && -f "$TMUXONWATCH_NOTIFY_SCRIPT" ]]; then
      "$TMUXONWATCH_NOTIFY_PY" "$TMUXONWATCH_NOTIFY_SCRIPT" \
        --event-id "$event_id" \
        --title "$title" \
        --message "$message" \
        --duration "$duration" >/dev/null 2>&1 || true
    fi
  }

  _tmuxonwatch_preexec_hook() {
    TMUXONWATCH_CMD_START="$(date +%s)"
    TMUXONWATCH_CMD_TEXT="$1"
  }

  _tmuxonwatch_precmd_hook() {
    local exit_code=$?
    local now duration cmd pane title message event_id

    _tmuxonwatch_notify_flush
    [[ -n "${TMUX:-}" ]] || return 0
    [[ -n "${TMUXONWATCH_CMD_START:-}" ]] || return 0

    now="$(date +%s)"
    duration=$((now - TMUXONWATCH_CMD_START))
    cmd="${TMUXONWATCH_CMD_TEXT:-command}"
    pane="$(tmux display-message -p "#{session_name}:#{window_index}:#{window_name}" 2>/dev/null || true)"
    title="${pane:-tmux command finished}"
    message="${cmd} (exit ${exit_code}, ${duration}s)"
    event_id="${pane}|${cmd}|${TMUXONWATCH_CMD_START}|${exit_code}"

    TMUXONWATCH_CMD_START=""
    TMUXONWATCH_CMD_TEXT=""
    _tmuxonwatch_notify_send "$event_id" "$title" "$message" "$duration"
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _tmuxonwatch_preexec_hook
  add-zsh-hook precmd _tmuxonwatch_precmd_hook
fi
EOF
)
            ;;
        bash)
            warn "Bash shell detected; auto-hook install currently targets zsh."
            warn "Helper script created at $helper_script for manual bash integration."
            return
            ;;
        *)
            warn "Unsupported login shell '$shell_name'. Wrote helper at $helper_script."
            return
            ;;
    esac

    shell_block="${shell_block//__NOTIFY_PY__/$notify_py}"
    shell_block="${shell_block//__NOTIFY_SCRIPT__/$notify_script}"
    marker_start="# >>> tmuxonwatch notify hooks >>>"
    marker_end="# <<< tmuxonwatch notify hooks <<<"
    upsert_managed_block "$shell_rc" "$marker_start" "$marker_end" "$shell_block"
    ok "Installed notify hooks in $shell_rc"
    ok "Created hook helper: $helper_script"
}

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
SERVER_FILES="main.py tmux_bridge.py ansi_parser.py requirements.txt notify_event.py"

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

if [[ -f "$INSTALL_DIR/notify_event.py" ]]; then
    chmod +x "$INSTALL_DIR/notify_event.py"
fi

# ── Generate / preserve token ─────────────────────────────
mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_DIR/env" ]]; then
    source "$CONFIG_DIR/env" 2>/dev/null || true
fi

if [[ -n "${TP_TOKEN:-}" && "${TP_TOKEN}" != "changeme" ]]; then
    ok "Using existing auth token"
else
    TP_TOKEN=$("$PYTHON" -c "import secrets; print(secrets.token_urlsafe(32))")
    ok "Generated auth token"
fi

if [[ -n "${TP_NOTIFY_TOKEN:-}" ]]; then
    ok "Using existing notification token"
else
    TP_NOTIFY_TOKEN=$("$PYTHON" -c "import secrets; print(secrets.token_urlsafe(24))")
    ok "Generated notification token"
fi

cat > "$CONFIG_DIR/env" << ENVFILE
export TP_TOKEN="$TP_TOKEN"
export TP_NOTIFY_TOKEN="$TP_NOTIFY_TOKEN"
ENVFILE
chmod 600 "$CONFIG_DIR/env"

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

# Verify that the expected API surface is available (helps catch stale local files
# when network download falls back to existing copies).
if [[ "$SERVER_STARTED" == "true" ]]; then
    if curl -sf -H "Authorization: Bearer $TP_TOKEN" "http://127.0.0.1:$PORT/windows" > /dev/null 2>&1; then
        ok "Server API check passed (/windows available)"
    else
        warn "Server API check failed: /windows endpoint unavailable."
        warn "Your local server files may be outdated; rerun installer with network access."
    fi
fi

# Optional: hook shell prompt return to automatic remote push notifications.
setup_optional_notify_hooks "$INSTALL_DIR/.venv/bin/python3" "$INSTALL_DIR/notify_event.py"

# ── Output connection info ────────────────────────────────
echo ""
echo "─────────────────────────────────"
echo -e "${BOLD}${GREEN}Installation complete!${RESET}"
echo ""
echo -e "  Server:  ${CYAN}$SERVER_URL${RESET}"
echo -e "  Token:   ${CYAN}$TP_TOKEN${RESET}"
echo -e "  Notify:  ${CYAN}$TP_NOTIFY_TOKEN${RESET}"
echo -e "  Config:  ${CYAN}$CONFIG_DIR/env${RESET}"
echo -e "  Logs:    ${CYAN}/tmp/tmuxonwatch.{out,err}.log${RESET}"
echo ""

# ── QR code for iOS pairing ──────────────────────────────
# Encode server URL + token as JSON for QR scanning
NOTIFY_WEBHOOK_URL="https://www.tmuxonwatch.com/api/webhook"
NOTIFY_REGISTER_URL="https://www.tmuxonwatch.com/api/push/register"
NOTIFY_UNREGISTER_URL="https://www.tmuxonwatch.com/api/push/unregister"
QR_PAYLOAD="{\"url\":\"$SERVER_URL\",\"token\":\"$TP_TOKEN\",\"notifyToken\":\"$TP_NOTIFY_TOKEN\",\"notifyWebhook\":\"$NOTIFY_WEBHOOK_URL\",\"notifyRegister\":\"$NOTIFY_REGISTER_URL\",\"notifyUnregister\":\"$NOTIFY_UNREGISTER_URL\"}"

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
    print(f'  Notify:     {sys.argv[4]}')
    print(f'  Webhook:    {sys.argv[5]}')
    print(f'  Unregister: {sys.argv[6]}')
" "$QR_PAYLOAD" "$SERVER_URL" "$TP_TOKEN" "$TP_NOTIFY_TOKEN" "$NOTIFY_WEBHOOK_URL" "$NOTIFY_UNREGISTER_URL" 2>/dev/null || {
    echo "Manual setup — enter these in the tmux on watch iOS app:"
    echo -e "  Server URL: ${CYAN}$SERVER_URL${RESET}"
    echo -e "  Token:      ${CYAN}$TP_TOKEN${RESET}"
    echo -e "  Notify:     ${CYAN}$TP_NOTIFY_TOKEN${RESET}"
    echo -e "  Webhook:    ${CYAN}$NOTIFY_WEBHOOK_URL${RESET}"
    echo -e "  Unregister: ${CYAN}$NOTIFY_UNREGISTER_URL${RESET}"
}
else
    echo "Manual setup — enter these in the tmux on watch iOS app:"
    echo -e "  Server URL: ${CYAN}$SERVER_URL${RESET}"
    echo -e "  Token:      ${CYAN}$TP_TOKEN${RESET}"
    echo -e "  Notify:     ${CYAN}$TP_NOTIFY_TOKEN${RESET}"
    echo -e "  Webhook:    ${CYAN}$NOTIFY_WEBHOOK_URL${RESET}"
    echo -e "  Unregister: ${CYAN}$NOTIFY_UNREGISTER_URL${RESET}"
fi

echo ""
