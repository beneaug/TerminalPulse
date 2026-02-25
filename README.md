# TerminalPulse

**Live tmux terminal on your Apple Watch.**

TerminalPulse captures your tmux session output with full ANSI color support and streams it to your iPhone and Apple Watch in real time. Get notified when long-running commands finish — right on your wrist.

## Features

- **Live terminal output** — Full ANSI color rendering (256-color + true color)
- **Apple Watch app** — See your terminal from your wrist, auto-refreshes
- **Command-finished notifications** — Haptic buzz when a command completes
- **Session switching** — Multiple tmux sessions, switch between them
- **Color themes** — Default, Solarized Dark, Dracula, Gruvbox
- **Background polling** — Keeps updating even when the app is backgrounded
- **Local & Tailscale** — Works on LAN or over Tailscale for remote access

## Requirements

- **Server**: macOS with Python 3.10+ and tmux
- **iOS app**: iPhone running iOS 17.0+
- **Watch app**: Apple Watch running watchOS 10.0+

## Quick Start

### 1. Install the server

On the Mac where tmux is running:

```bash
bash install.sh
```

The installer will:
- Set up a Python virtual environment
- Install FastAPI + Uvicorn
- Generate a secure auth token
- Create and start a launchd service
- Display a QR code for pairing

### 2. Connect the iOS app

Open TerminalPulse on your iPhone:
- Scan the QR code from the install script, **or**
- Enter the server URL and token manually in Settings

### 3. Put it on your wrist

The Watch app receives data from the iPhone automatically via WatchConnectivity. Just open the app on your Watch.

## Architecture

```
┌─────────────┐    HTTP/JSON    ┌──────────────┐   WatchConnectivity   ┌─────────────┐
│  tmux pane   │ ──────────────▶│  iPhone app   │──────────────────────▶│  Watch app   │
│              │    /capture     │              │                       │              │
│ Python       │◀── polling ────│ PollingService│                       │ PhoneBridge  │
│ FastAPI      │                │              │                       │              │
│ (port 8787)  │                │ Notifications │                       │ Haptics      │
└─────────────┘                └──────────────┘                       └─────────────┘
```

**Server** (`server/`): FastAPI app that captures tmux pane output via `tmux capture-pane`, parses ANSI escape sequences into structured runs, and serves them as JSON.

**iPhone app**: Polls the server at configurable intervals, renders colored terminal output using `AttributedString`, detects command completion (prompt reappears), sends notifications, and bridges data to Watch.

**Watch app**: Receives payloads from iPhone via WatchConnectivity, renders terminal output, provides haptic feedback on command completion and reconnection.

## Server API

| Endpoint | Auth | Description |
|----------|------|-------------|
| `GET /health` | No | Server status, hostname, tmux availability |
| `GET /capture?lines=80&target=session:window` | Bearer | Capture pane output with ANSI parsing |
| `GET /sessions` | Bearer | List all tmux sessions |
| `GET /windows?session=name` | Bearer | List windows (optionally scoped to one session) |
| `POST /send-keys` | Bearer | Send literal text or an allowed special key to tmux |
| `POST /switch-window` | Bearer | Switch to next/previous tmux window |

## Configuration

### Server

Token is stored in `~/.config/tmuxonwatch/env`:

```bash
export TP_TOKEN="your-secure-token-here"
```

The launchd service sources this file on startup. To change the token:

```bash
# Generate a new token
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Edit the env file
vim ~/.config/tmuxonwatch/env

# Restart the service
launchctl kickstart -k gui/$(id -u)/com.tmuxonwatch.server
```

### iOS App Settings

- **Server URL**: HTTP endpoint (e.g., `http://127.0.0.1:8787`)
- **Auth Token**: Stored in iOS Keychain
- **Poll Interval**: 2–120 seconds (default: 10s)
- **Font Size**: 8–16pt (iPhone), 7–12pt (Watch)
- **Color Theme**: Default, Solarized Dark, Dracula, Gruvbox
- **Notifications**: Toggle command-finished alerts

## Remote Access via Tailscale

For monitoring terminals remotely:

1. Install [Tailscale](https://tailscale.com) on both your Mac and iPhone
2. Use your machine's Tailscale hostname as the server URL:
   ```
   http://my-mac.tail1234.ts.net:8787
   ```
3. The app allows plain HTTP to `.ts.net` domains (configured in ATS exceptions)

## FAQ

**Does this work without tmux?**
No. TerminalPulse captures output from tmux panes. If you don't use tmux, this app isn't for you.

**Does it need to be on the same network?**
The installer-managed launchd service binds to `0.0.0.0` so iPhone/watch clients can connect over LAN or Tailscale. If you run `python server/main.py` directly, it binds to `127.0.0.1` unless you pass a different host.

**How much battery does it use on the Watch?**
The Watch app only receives data when the iPhone pushes updates. It doesn't poll independently. Battery impact is minimal — comparable to other WatchConnectivity apps.

**Can I see scrollback history?**
The `lines` parameter controls how many lines to capture (default: 80). You can increase this, but Watch screens are small.

## Project Structure

```
TerminalPulse/
├── server/
│   ├── main.py              # FastAPI server
│   ├── tmux_bridge.py       # tmux subprocess wrappers
│   ├── ansi_parser.py       # ANSI SGR → structured runs
│   └── requirements.txt
├── TerminalPulse/
│   ├── Shared/              # Shared between iOS + Watch
│   │   ├── Models.swift
│   │   ├── TerminalColors.swift
│   │   └── RunsRenderer.swift
│   ├── TerminalPulse/       # iPhone target
│   │   ├── Services/
│   │   │   ├── APIClient.swift
│   │   │   ├── PollingService.swift
│   │   │   ├── WatchBridge.swift
│   │   │   ├── NotificationService.swift
│   │   │   ├── CaptureCache.swift
│   │   │   └── KeychainService.swift
│   │   ├── TerminalView.swift
│   │   ├── SettingsView.swift
│   │   └── OnboardingView.swift
│   └── TerminalPulseWatch/  # Watch target
│       ├── WatchTerminalView.swift
│       └── PhoneBridge.swift
├── install.sh               # Server installer
└── README.md
```

## License

Copyright (c) 2026 August Benedikt. All rights reserved.
