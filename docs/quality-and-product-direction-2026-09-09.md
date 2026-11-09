# tmuxonwatch — quality pass and product direction

## Outcome

The implementation now has a stronger efficiency/reliability foundation, a more useful iPhone companion, and cleaner watch presentation. This is a reviewed development candidate, not a deployed release or a claim that every possible bug has been eliminated.

Work is on branch `codex/efficiency-and-design`. The baseline is `f7e2d49`, which preserved existing app/localization changes on top of `ba11b89`. The original checkout was not edited. The running server, marketing site, purchase identifier, and App Store listing were not changed.

Use tmuxonwatch for new customer-facing naming. Historical internal identifiers were intentionally left alone.

## What was fixed

### Reliability and input safety

- Fixed a simulator-reproduced crash when terminal rows shrank while SwiftUI evaluated retained lazy rows. Both screens now render against an immutable array snapshot for each view transaction.
- Capture text is requested from the concrete pane whose metadata was resolved, avoiding text/label mismatches when tmux focus changes.
- Content identity includes pane/window/session/host metadata; identical text in another pane no longer suppresses the switch.
- Keystrokes and window-switch POSTs are not automatically replayed on another network path after an ambiguous failure. Read-only requests retain fallback support.
- Literal dash-prefixed text cannot become a tmux option. Targets reject trailing newlines; timed-out/cancelled subprocesses are killed and reaped.
- The iPhone input sheet retains the selected pane and server. Changing the server invalidates that composer. Watch input requires a concrete pane, not an implicit fallback to whichever pane happens to be active.
- The new composer sends text and Return separately. Multiline input is rejected with an explanation because embedded line breaks can execute commands immediately. Saved shortcuts fill the composer; selecting them never executes them.
- Stale session inventories and captures are discarded if the configured server or target changes during a request.
- Watch refresh and input handlers are connected independently of the iPhone view appearing. Background refresh can initialize the shared service on a cold launch.
- Watch background connectivity delivery uses an event-driven completion handler with cancellation, rather than a polling wait loop. Hidden rendering is deferred until the watch is visible.
- Delayed cached watch content no longer implies a live server connection. A phone acknowledgement alone does not mean the capture succeeded. Missing captures also trigger backoff.
- Queued switches expire, failed live switches are not replayed automatically, and repeated refresh hints are bounded.
- Entitlements restore before product-loading retries; duplicate purchase/restore taps are guarded; unverified purchases leave the loading state; transaction updates re-check revocation.
- Keychain updates no longer delete a working token before replacement succeeds. Failed onboarding tests do not erase the saved setup. Credential-save errors are surfaced, and connection tests no longer accept arbitrary non-401 failures as success.
- QR scanning starts/stops the camera on a serial queue, resizes the preview correctly, and suppresses duplicate results.
- Command completion detection handles trailing prompt whitespace and pane changes more carefully. The local alert toggle is respected. Live haptic events are not replayed from cached application context.
- Notification retry files are atomic/private, concurrent shell hooks are serialized, duplicate failed events are suppressed, and retry backlog work is bounded. An empty queue does not produce a file write on every prompt.
- Corrected the xterm 256-color cube. Multiple attached tmux clients and window names containing `|` are parsed correctly.

### Efficiency without reducing information

- The updated server supports conditional capture responses. On unchanged output it still checks current tmux state, but returns HTTP 304 with no response body and skips ANSI parsing.
- The updated iPhone client reuses decoded capture data for 304 responses. Older servers remain supported.
- Compact responses omit the redundant raw ANSI copy; parsed text and attributes remain. Older clients can still receive the original raw field.
- Concurrent identical capture requests share only the in-flight work. There is no new time-based server cache that intentionally delays changed output.
- Normal active refresh settings remain intact. Idle backoff cannot accidentally accelerate a user-selected slow interval. Low Power Mode, offline backoff, timer tolerance, cancellation, and in-flight coalescing are retained or corrected.
- Watch heartbeats no longer repeatedly reset the phone's quiet/error backoff.
- Unchanged output avoids attributed-string rebuilding and cache writes. Settings re-render from memory; cache saves are ordered on a utility queue.
- Font construction and character counting are reused during rendering. Existing bounded terminal limits were not reduced to manufacture a speed improvement.
- Removed an invisible video player, duplicate/custom clock work, and redundant auto-scroll passes. The native watch clock remains visible. Reduced Motion is respected and held-key timers stop when the screen becomes inactive.
- New search, sharing, and composition features run when opened; they do not add another always-running service.

## What users gain now

| Area | Free experience | Pro experience |
| --- | --- | --- |
| Monitoring | Live terminal, session/window selection, existing themes and refresh controls | Existing monitoring remains available; no battery or readability paywall |
| iPhone reading | Read & Find opens a stable, searchable snapshot with line numbers, selection, copy and sharing; the live stream continues separately | Same |
| Input | Clear explanation of the upgrade; safe composer preview in demo mode | Input from iPhone as well as Apple Watch, explicit special keys, and up to eight locally saved input shortcuts |
| Purchase | Live price is supplied by StoreKit; restore remains available | Existing product/one-time unlock preserved; no new subscription or replacement purchase introduced |

The visual language is a quiet instrument: dark neutral surfaces, one consistent accent for product actions, monospaced terminal content, and native navigation/forms where they help. Status, terminal text, and input controls now occupy distinct areas instead of overlapping. Color inside the terminal retains its meaning.

On iPhone, accessibility-sized text reflows status and action controls into readable vertical arrangements. Terminal text scales from the user's chosen font size using system font metrics. The standard text-size layout is unchanged in density.

New interface strings have Japanese translations in the existing catalogs. These should receive a fluent-human copy review before release; this is not a claim of completed localization QA on every screen.

## Verification and limits

- 33 server unit tests pass.
- 15 Swift tests pass, including the actual API client under an in-memory URL transport. Coverage includes 304 reuse, Unicode preservation, target-specific validators, legacy responses, non-replayed mutations, and read-only fallback.
- Both iPhone and watch targets build in Debug and Release for the iOS/watchOS 26.2 simulators. The remaining build messages are the normal skipped App Intents metadata extraction warning.
- The animated iPhone demo was exercised through repeated content growth/clear/shrink cycles. Search returned the expected four `Compiling` rows. Input preview and shortcut save were checked without sending any command to a real terminal.
- The 42 mm watch presentation was visually checked in active and simulated Always On states. The latter hides the input toolbar and stops decorative motion.
- The final iPhone main screen was checked in Japanese and at Accessibility Extra Large text size. The initial large-text check exposed awkward word wrapping; the corrected layout was rebuilt and visually rechecked. The simulator's original text size was restored afterward.
- CI now installs server dependencies, runs the server suite, and runs the shared Swift/network tests before the Apple builds. The workflow itself has not been executed remotely in this pass.

### Synthetic efficiency measurement

An 80-line ANSI/Unicode fixture, 200 requests per path, no real tmux process or network radio:

| Measurement | Legacy full response path | Compact changed response | Conditional unchanged response |
| --- | ---: | ---: | ---: |
| Response body | 18,139 bytes | 9,671 bytes | 0 bytes |
| ANSI parses across 200 unchanged requests | 200 | Not measured | 0 |
| Median handler time in this run | 0.279 ms | Not measured | 0.078 ms |

This compares paths in the new handler, not complete old-versus-new app performance. HTTP headers, tmux capture work, transport costs, and WatchConnectivity are excluded. The results prove avoided serialization/parsing/body bytes for this fixture, not a percentage battery saving.

Reproduce using the [capture benchmark](../server/tests/benchmark_capture.py).

Historical visual QA covered the iPhone main screen, Watch active and Always On, iPhone composer, Japanese, and larger text. Repeat against the final candidate before release.

### Required release gates — not yet completed

1. On the same physical paired iPhone/watch, compare this candidate with the preserved baseline for two hours each: actively changing output, idle output, periodic wrist raises, and phone/network disconnection. Keep brightness, battery health, radios, watch model and Return to Clock settings comparable; repeat runs to distinguish noise from regression.
2. Measure device energy impact, CPU/wakeups, network bytes, memory growth, missed/duplicate input, and median/p95 wrist-raise-to-fresh-output latency. Reject any repeatable battery or interaction regression. Use the same terminal fixture and output cadence for both builds.
3. Test background delivery and expiration with apps launched from their Home Screens, not attached to the debugger. Exercise phone lock, app suspension, out-of-range recovery, Always On, and Low Power Mode. Apple specifically calls for physical devices for WatchConnectivity testing. [Apple's connectivity sample](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
4. Exercise StoreKit sandbox purchase, cancellation, pending approval, restore, offline relaunch and refund/revocation on the paired devices. No real purchase was made during this pass.
5. Check VoiceOver reading order, accessibility Dynamic Type sizes, contrast in every existing theme, Japanese text expansion, the smallest supported watch, and iPad layout. QR camera permission denial/regrant also needs physical-device testing.
6. Update server and client together to obtain the conditional-response benefit. Test new-client/old-server and old-client/new-server combinations before restarting the live service. No live server restart or app distribution has occurred yet.

## Product direction: confidence at a glance

The strongest product promise is not “a tiny terminal that never sleeps.” It is “step away from your computer without losing the thread.” The important loop is: check what matters, understand whether attention is needed, and respond deliberately.

A watch app cannot promise an indefinitely foreground, fully animated custom watch face. Apple limits frontmost/background behavior and reduces Always On update frequency; users control Return to Clock behavior. Design around immediate check-ins and useful saved state. Do not use fake workout/audio/video sessions to evade those limits. [Apple's Always On guidance](https://developer.apple.com/documentation/watchos-apps/designing-your-app-for-the-always-on-state) Background execution is explicitly budgeted and may be throttled. [Apple's background-task guidance](https://developer.apple.com/documentation/watchkit/using-background-tasks)

### Next release: make the core experience excellent

- Give setup a small connection checklist: Mac reachable, token accepted, tmux session available, watch ready. Separate actionable setup failures from temporary standby. Make the first successful real capture feel unambiguous.
- Replace the single generic demo with three short, on-demand stories: build finished, an assistant waiting for a reply, and deployment output. Show useful outcomes rather than screen density.
- Add a free privacy option for wrist-down/app-switcher output. Keep basic legibility, accessibility, safe input, and efficiency free.
- Give the watch an explicit “follow latest / reading older output” mode so live updates cannot pull someone away from the line they are inspecting. Keep the return-to-live action obvious and test its interaction with the Digital Crown.

### Following release: meaningful Pro leverage

- Local named server profiles and favorite targets, with only the currently viewed source actively polled. This adds convenience without multiplying idle radio activity.
- Named, per-project input shortcuts with a clear preview and confirmation for consequential actions. Preserve literal text/Return separation and avoid silent automatic execution.
- A small local activity inbox: recent completions, which session they belong to, and a direct route back to that pane. Prefer explicit shell-hook events to guessing task state from arbitrary text. Retain only a bounded history and let the user clear it.
- One useful free complication/Smart Stack entry that reopens the last workspace; consider more configurable target-specific glances for Pro. Display honest “last checked” state, not a synthetic second-by-second live badge. Widgets have system update budgets; they are not a workaround for continuous polling. [Apple's connectivity/widget example](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)

These are proposals, not implemented features or changes to existing customers' entitlements. Keep the current one-time purchase intact unless pricing is separately reconsidered.

### What would earn editorial-level polish

A coherent app wins through the quality of its smallest states: waiting, reconnecting, reading, completing, and sending. Prioritize those states, accessibility, localized copy, graceful offline behavior, fast first success, and genuinely restrained motion before adding more surfaces.

Avoid background AI summaries, constant animations, polling every configured server, or a permanently connected stream merely to sound “real time.” Any proposed event-driven/control-mode transport should first beat the current approach in measured device energy and latency while preserving output and reconnect correctness.

Apple editorial selection cannot be guaranteed. The aim is a distinctive, trustworthy product whose beauty comes from making one technical workflow feel effortless.
