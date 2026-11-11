# Explicit task events, from any tool

The terminal remains the product's source of context. `server/event_adapter.py`
is a small, stdlib-only interoperability entry point: a tool, CI job, or wrapper
can report an outcome without tmuxonwatch knowing its private state or executing
its commands. It adds no daemon, subscription, agent account, or configuration
changes. The adapter itself is free interoperability infrastructure; existing
app purchase and remote notification setup requirements are unchanged.

## Try it without sending anything

From the checkout (Python 3.10+):

```sh
python3 server/event_adapter.py --dry-run \
  --outcome completed --event-id build-run-42 --source my-tool
```

Or pass one UTF-8 JSON object on stdin:

```sh
printf '%s\n' '{"version":1,"outcome":"attention-needed","event_id":"run-42-question-1","source":"my-tool","session_id":"session-7","target":"work:0.1"}' \
  | python3 server/event_adapter.py --dry-run
```

Dry-run prints normalized JSON and does not load credentials, write state, invoke
the sender, or contact the network. Remove `--dry-run` to invoke the existing
sibling `notify_event.py`, which uses the user's existing notification setup.
The adapter must remain alongside that sender; do not copy it alone. This guide
does not install hooks or edit agent settings. The installer copies both helpers;
examples use checkout paths, which you can replace with your installed server path.

## Version 1 contract

- `version`: optional integer `1`.
- `outcome`: required, exactly `completed`, `failed`, or `attention-needed`.
- `event_id`: required nonempty caller-issued occurrence ID. Use a job/turn ID
  plus a per-occurrence suffix where appropriate. Reuse the same ID on retries;
  use a new ID for the next occurrence. Do not use a session ID alone for every
  turn, or generate a new random ID on each retry.
- `source`, `session_id`, `target`: optional strings. These are identity metadata,
  not commands or paths to read. Target is informational only: it does not switch
  panes or deep-link the Watch into a session.

All fields above are strings except `version`. Strings are limited to 256
characters, with no surrounding whitespace or control/format characters. Input
is capped at 64 KiB. Malformed JSON, duplicate JSON keys, unsupported versions,
unknown outcomes, missing IDs, and invalid fields exit 2 before calling the
sender. This is deliberately not a generic pass-through webhook.

CLI fields select CLI mode and replace stdin entirely. Provide both `--outcome`
and `--event-id`; optional flags are `--source`, `--session-id`, and `--target`.
Do not combine a partial CLI event with stdin expecting a merge.

The normalized ID is a versioned SHA-256 digest of outcome, occurrence ID, and
optional metadata. Object key order does not affect identity; changing those
fields does. Identical retries reach the sender with the same ID. The sender's
bounded local dedupe is not a durable, end-to-end exactly-once guarantee. The
adapter bypasses duration/debounce filtering for explicit events, but not event
ID dedupe. Exit 0 means the sender accepted processing (or notification setup was
absent), not that a device displayed an alert. Failed delivery may be queued by
the sender; this adapter does not create a background retry service.

## Privacy and authority

Notification title and body are fixed generic text for the outcome. Unrecognized
fields, including prompts, tool input, assistant output, titles, messages,
transcript paths, and commands, are ignored and never forwarded. This protects
against accidentally placing a full conversation on a lock screen.

Only generic title/body go to the existing webhook. The digest is used in local
sender state; optional source/session/target metadata appears in dry-run output
but not the notification. Do not put secrets into metadata: dry-run output may
be logged, and hashing is not encryption. Nothing reads transcripts, discovers
credentials from agents, executes event-supplied commands, or approves a tool's
permission request. Invoke with a fixed executable/path and proper argument
quoting in your tool's configuration.

## Codex, Claude Code, and dot

Use `--source codex-hook`, `--source codex-notify`, or `--source claude-hook`
to select a documented parser. Other source names keep the generic contract.
Integration modes accept JSON stdin; `codex-notify` also accepts the single JSON
argument appended by Codex. They ignore unsupported events with exit 0 and no
notification. Live hook modes always exit 0 on input/argument/delivery errors:
`codex-hook` emits neutral `{}` and `claude-hook` emits no decision. This keeps
observers from blocking or approving agent work. Dry-run reports errors with exit
2 and prints normalized JSON only on success. Legacy notify validation errors also exit 2; sender errors return nonzero.

Codex Stop uses session + turn ID when available; legacy notify uses thread +
turn ID. Both emit **Codex turn finished**, never task-success wording. Stop with
`stop_hook_active: true` is skipped. PermissionRequest maps to attention-needed;
Claude Stop and StopFailure map to turn-finished and failed respectively. Other
Claude notifications are deliberately unsupported in this bounded adapter.

When no documented stable occurrence ID is available (including Claude hooks and
permission requests), the adapter generates a UUID once per invocation. It passes
that identity to the sender, which preserves it for queued retries. No wrapper is
required. **Duplicate producer invocations can create duplicate alerts.** Supply
`--event-id` when your producer already has a stable per-occurrence identifier to
dedupe those invocations too. Never put one static ID in a recurring hook. Dry-run
IDs also change between invocations when using this fallback.

The sender subprocess has a 30-second timeout, including time waiting for its
lock. On timeout it is stopped and delivery is unknown: it may have sent an alert
or may not have persisted a retry. Hooks still return neutrally. The adapter does
not spawn a daemon or retry that uncertain operation. Session/target metadata is
never a command; no private text is hashed to manufacture an identity.

### Opt-in configuration examples

Review your installed tool's documentation and trust requirements first. Paths
below are placeholders to replace with absolute paths; no configuration is
written automatically. Do not enable both Codex completion routes at once.

Codex legacy notify, in its TOML config:

```toml
notify = ["python3", "/absolute/path/tmuxonwatch/server/event_adapter.py", "--source", "codex-notify"]
```

Codex command hook, in the hooks JSON configuration supported by your version
(review/trust it through `/hooks` where required):

```json
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"python3 /absolute/path/tmuxonwatch/server/event_adapter.py --source codex-hook","async":true,"timeout":40}]}]}}
```

Claude Code `settings.json` opt-in hooks, with no custom wrapper required:

```json
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "python3 /absolute/path/tmuxonwatch/server/event_adapter.py --source claude-hook", "timeout": 40, "async": true}]}],
    "PermissionRequest": [{"hooks": [{"type": "command", "command": "python3 /absolute/path/tmuxonwatch/server/event_adapter.py --source claude-hook", "timeout": 40, "async": true}]}],
    "StopFailure": [{"hooks": [{"type": "command", "command": "python3 /absolute/path/tmuxonwatch/server/event_adapter.py --source claude-hook", "timeout": 40, "async": true}]}]
  }
}
```

Merge only the entries you want into existing settings rather than replacing
other hooks. Quote executable/file paths if they contain spaces. Your installed
Claude release must support each chosen event; omit unsupported events. Do not
also enable the installer's legacy Claude Stop hook for the same signal. Hooks
are observers only: no approval, denial, or continuation decision is emitted.
Titles identify Codex or Claude Code using fixed provider names, never private text.
Never substitute prompt/tool-input text into shell commands. The examples use the tools' documented `async: true` command-hook option to
avoid holding up the agent while sending. This is not an added daemon. Codex
enforces its hook timeout; Claude does not enforce the runner timeout once a
hook is backgrounded, so the adapter's own 30-second sender bound matters.
Background delivery is best-effort: closing a session (including Claude `-p`
teardown) can cancel a hook before it sends. Do not infer delivery from launch.
See [Codex background hooks](https://learn.chatgpt.com/docs/hooks#run-hooks-in-the-background)
and [Claude background hooks](https://code.claude.com/docs/en/hooks#run-hooks-in-the-background).
Older releases may not support these options; verify your installed version.

Verified integration surfaces to use when writing such wrappers:

- [Codex notifications](https://learn.chatgpt.com/docs/config-file/config-advanced#notifications)
  pass one JSON **command-line argument** for `agent-turn-complete`, including
  `thread-id` and `turn-id`. Those IDs can identify a finished turn. Ignore
  `input-messages` and `last-assistant-message`. This is completion-only, not a
  failure or permission-request feed.
- [Codex lifecycle hooks](https://learn.chatgpt.com/docs/hooks) use JSON stdin.
  `Stop` means a turn ended, not that the user's task succeeded; `PermissionRequest`
  is a possible attention signal, never permission to approve anything. Supported
  events can vary by installed release. A successful observer hook must return
  the hook protocol's neutral response (such as `{}`), not the adapter's dry-run
  object. Choose one completion route to avoid duplicate alerts.
- [Claude Code hooks](https://code.claude.com/docs/en/hooks) include `Stop`,
  `StopFailure`, and `Notification`. A Stop may leave background work running.
  `StopFailure` is a failure signal; notification types such as `permission_prompt`
  are possible attention signals. Do not label every notification a success:
  `agent_completed` can include failed background work and `idle_prompt` need not
  mean blocked. Keep recursion guards, avoid default subagent alerts, and use one
  permission-alert route rather than both permission and notification hooks.
- The documented [Codex cloud orchestration hook route](https://learn.chatgpt.com/docs/hooks#hooks-with-cloud-orchestration)
  is enterprise-specific. This foundation does not claim native personal dot
  lifecycle integration. A future supported producer can use the same explicit
  contract without adding transcript scraping or private-state polling.

For a finished *turn*, consider an explicit `attention-needed` event when the
meaning is “ready for your input,” rather than claiming the whole task completed.
A hook's session ID alone is insufficient to distinguish multiple events; when a
provider supplies no stable occurrence ID, the generated invocation ID prevents
suppressing later turns but cannot dedupe repeated producer invocations. The
adapter never invents an ID from private text.

## Configuration check and supported setups

```sh
python3 server/notify_event.py --check
```

This reads local configuration and queue information without sending or writing.
It reports whether a token is configured, the relay host and queued-event count;
it never prints the token and marks delivery `not_tested`. Exit 2 means missing or
invalid configuration. It does not prove pairing, entitlement, relay reachability,
or device delivery. A live test is a separate opt-in notification.

The sender reads `TP_NOTIFY_TOKEN` and optional `TP_NOTIFY_WEBHOOK_URL` from its
process environment first, then `~/.config/tmuxonwatch/env`. Sender CLI overrides
have highest priority. Use your existing notification setup and a secure secret
injection method; do not put real tokens in hook commands, chat, or source control.
Custom relay URLs must use HTTPS without embedded credentials, query, or fragment.
Environment injection works for CI and wrappers without copying an agent's
credentials. The adapter itself never searches agent configuration for secrets.

- **macOS:** installer-supported host; helper tests run here.
- **Linux / WSL:** Python helper code is POSIX-oriented (the sender uses `fcntl`).
  Manual integration is possible in principle, but Linux/WSL were not tested in
  this pass and the launchd installer is macOS-only.
- **Native Windows:** not supported by this sender/installer; do not claim native
  Windows parity. WSL is a separate POSIX environment, not a native Windows port.
- **Outside tmux:** explicit hook notifications can use the optional push setup
  even when the producer is not inside tmux. This does not provide tmux-free live
  terminal viewing. Live panes still require a tmux host plus the iPhone/Apple
  Watch app connection; push requires its existing pairing/notification setup.
- **Personal dot:** no documented native lifecycle integration is claimed.

## Offline tests

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s server/tests -p test_event_adapter.py -v
```

Tests cover malformed/oversized input, unknown events, privacy filtering, Unicode,
stable identity, dry-run isolation, and fixed-argument sender invocation. They
mock delivery and do not send notifications or alter agent configuration.

## Delivery behavior and upgrades

The sender persists a new event before making a network request. Retries run
when another event arrives or when an existing shell hook invokes `--flush-only`;
there is no timer, daemon, or guarantee of delivery while the computer sleeps.
Each invocation processes at most two queued events and uses network timeouts.
A closed agent session or a timeout while waiting for a busy sender can still
interrupt processing. Check the device before manually retrying an uncertain
result.

Queue, lock and dedupe state are scoped to an opaque digest of the configured
HTTPS relay URL and notification token. Changing credentials or endpoints cannot
forward a previous account's queued content to the new destination. No raw token
is written into these filenames. Rotating a token starts a separate queue; the
old pending events remain isolated and are not silently migrated.

Earlier versions used one unscoped `notify-queue.jsonl`. This candidate leaves
that file untouched and does **not** send its contents automatically: the old
file does not prove which relay/account originally owned each event. The local
`--check` command reports `legacy_queue_present` so it can be reviewed deliberately.
Do not copy an old queue into a new account's directory.

For the official relay's count-based receipts, `delivered: 0` is not accepted
as success even with HTTP 202; the event remains pending. A positive count means
APNs accepted at least one alert, not that a device displayed it. Partial
multi-device acceptance is not replayed to all devices because that would create
duplicates on successful devices. Per-device retry and server-side idempotency
remain future work. Legacy/custom relays returning only HTTP success are retained
for compatibility, with no stronger delivery claim.

The optional zsh installer hook now sends outcome/duration only by default, not
the command, its arguments, or session names. Setting `TP_NOTIFY_INCLUDE_COMMAND=1`
in the invoking shell explicitly enables that older detail behavior; command
arguments can contain passwords or API keys and will be sent to the configured
relay and lock screen. Existing installed hooks are not rewritten by these source
changes. Review and reinstall them deliberately if you want the new defaults.
