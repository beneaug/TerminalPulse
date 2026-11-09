# tmuxonwatch: interoperability and trustworthy setup

## Scope and product boundary

This development pass continues the September candidate on
`codex/efficiency-and-design`. It is not a deployment, App Store release, or
change to anyone's installed hooks. Keep the core promise: step away from a
terminal, learn when attention is useful, and respond deliberately.

Tool-neutral events are free interoperability infrastructure. Existing free
viewing and one-time Pro input benefits are unchanged. No account system,
subscription, transcript reader, agent controller, background poller, or native
personal-dot integration was introduced.

## Implemented

- An explicit versioned JSON/CLI event adapter for completion, failure and
  attention-needed events, plus documented Codex and Claude Code payload modes.
- Generic, fixed alert text excludes prompt, transcript, tool-input and response
  content. Provider hooks say a turn ended, not that a task succeeded.
- Passive asynchronous hook examples, input size/type limits, stable provider IDs
  where available and per-invocation IDs otherwise. No hook approves or blocks
  an agent action. User configuration remains opt-in.
- Notification receipts distinguish explicit zero acceptance from HTTP success.
  Accepted events are queued before network work, and queue/dedupe state is
  isolated per relay/account. Invalid custom URLs never fall back to another
  recipient. Legacy unscoped queues are preserved but not automatically sent.
- Environment-provided relay configuration and a read-only `--check` command for
  scripts, CI and custom setups, without copying secrets into examples.
- Privacy-preserving optional shell alerts and an installer source-detection fix:
  a checkout's folder name no longer determines whether it downloads over its
  own server files.
- iPhone setup tests a real capture after authentication/session discovery, with
  actionable incomplete-readiness messages rather than a false fully-connected
  promise. Valid server setup remains saveable without a running session.
- Push-test results separate APNs acceptance, missing recipients and unknown
  legacy receipts. An ambiguous POST is never automatically repeated.
- Japanese text and cancellation/stale-request handling for changed setup fields.

## Compatibility, not universality

The automated server installer remains macOS-only. The Python adapter/sender uses
POSIX facilities and Python 3.10+; Linux/WSL paths are documented but were not run
on those operating systems in this pass. Native Windows hosting and arbitrary
non-tmux terminal capture are not supported. Agent notification events can be
emitted independently of tmux, while live terminal viewing/control still requires
a reachable tmux host and the iPhone/watch companion path.

Current Codex/Claude hook events depend on the installed product version. Use the
legacy Codex completion notification path where lifecycle hooks are unavailable,
and do not enable both completion routes. Personal dot integration is not claimed;
the documented dot hook surface is enterprise managed cloud orchestration.

See [integration contracts and examples](integrations.md) for official sources,
configuration, privacy and delivery limitations.

## Validation and remaining gates

Final checks: 67 Python tests and 36 Swift package tests passed. The installer
passes `bash -n`; changed iOS sources pass Swift syntax parsing; localization
JSON and `git diff --check` pass.

[CI run 42673616824, attempt 2](https://github.com/beneaug/TerminalPulse/actions/runs/42673616824)
verified implementation commit `e9226509f435d7158df5fd332b1dfec3ffad1c3f` with
67 Python tests on Linux, 36 Swift core tests on macOS, and full unsigned
iOS Simulator and watchOS Simulator builds. The first attempt encountered a
GitHub internal server error before jobs started; the retry passed without
implementation changes. The [draft PR](https://github.com/beneaug/TerminalPulse/pull/1)
records exact current-commit results. The current workflow covers both unsigned
Debug and Release iPhone and Watch simulator builds.

Offline Python/Swift checks cover event normalization, malformed/oversized input,
privacy, neutral hook responses, recipient-isolated queues, interruption recovery,
relay receipts, session/capture readiness and cancellation. No test sends a real
notification or installs an agent hook.

Unsigned simulator compilation passes, but interactive UI and lifecycle validation
remain incomplete. Genuine matching before/after screenshots of the setup/status
text changes are still required, not substituted with mockups or historical
screenshots. Run the final candidate on the same simulator viewport. CI includes
Release simulator compilation; verify the final PR checks. Physical-device builds,
archive/export and signing remain unverified.

Then complete the September candidate's physical paired-device battery,
background delivery, StoreKit, accessibility/localization and old/new server
compatibility release gates. Real hook installation/delivery also needs an
explicit opt-in test against the user's chosen tools; this pass validates their
parsers offline, not their installed configuration.
