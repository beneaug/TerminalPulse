# Privacy, deliberate input, and release gates

This is a local development candidate, not a published release. It continues
`codex/efficiency-and-design` from `2af6746`. Do not describe the changes below as
shipped or use historical screenshots as evidence of the current interface.

## Product changes

- Two free privacy preferences default on, including when a preference has never
  been saved: protect screen previews and hide local notification details.
- iPhone protection covers scene windows when inactive, including presented
  sheets, while retaining the mounted interface and drafts. Apple Watch removes
  terminal text, session names and input from the view/accessibility tree while
  inactive or in Always On. The iPhone preference syncs to the Watch.
- New private local completion alerts use fixed text and neutral identifiers.
  Detailed local alerts require an explicit opt-out. This does not redact prior
  delivered alerts or remote push notifications. Remote content is controlled at
  its source; the new event adapter uses fixed, content-free messages.
- Watch Reading freezes output and its session title, preserving the reading
  position while new captures arrive. Latest explicitly returns to live output.
  Input and switching are suppressed while reading.
- Watch input pins the pane and opaque connection context that the person saw.
  Composition preserves drafts on failure or privacy dismissal. Held keys stop
  when their target changes. Only acknowledged sends clear a draft.
- iPhone composition also pins the displayed capture's context. Changing the
  connection while old output remains cannot retarget a draft to another host.
- Context is issued only for a successful, validated capture. Server address and
  authentication stay on the phone; the Watch receives a random identifier.
  Missing/stale contexts fail closed. Settings and cached/demo captures cannot
  grant input authority. Requests use a client bound to the validated credentials
  so a later settings change cannot reroute an awaiting request.
- Offline Watch switching now asks the person to reconnect and retry rather than
  reporting a queued success. Legacy queued switches are not executed. Legacy
  read-only window probing remains supported using bound clients and freshness
  checks. Mixed old/new phone and Watch versions can view output but must update
  both apps before sending context-protected input.

These controls are not screenshot prevention, a biometric lock, encrypted local
storage, or a guarantee that the operating system can never show old content.
Lifecycle behavior still needs the runtime checks below. Free viewing/reading
and one-time Pro input entitlements are unchanged.

## Offline validation

The final source must pass these again after any further code changes:

- 67 Python tests using the existing Python 3.13 server environment. The system
  Python is 3.9 and is not supported by the server's Python 3.10+ syntax.
- 36 Swift package tests: networking/readiness, relay receipts, privacy defaults,
  private alert content, Watch concealment/frozen snapshots, and opaque input
  context rotation/rejection, and atomic capture/context display replacement.
  These compile core code, not SwiftUI app targets.
- Swift syntax parsing for changed app files, localization JSON decoding,
  Xcode project plist validation, installer shell syntax, and `git diff --check`.
- Independent static review of stale-target input, held-repeat input, cached and
  settings-only context handling, offline switching and legacy capture probes.

A moved Swift module cache initially failed with an absolute-path PCH error;
a fresh scratch directory passed. An initial system-Python invocation failed dependency type
evaluation; rerunning in the existing supported Python environment passed.

## Current release blockers

1. **Full Apple builds and real screenshots are not run.** Local build resources
   are currently constrained. Run CI and use a suitable Apple development
   environment for simulator and device validation before release.
2. **Current UI and lifecycle proof.** Build both Debug and Release iPhone/Watch
   targets. Capture the same viewport, safe demo data and state at the baseline
   and final candidate. Exercise inactive/app switcher, presented sheets, locked
   phone, Watch wrist-down/Always On, accessibility trees, interrupted composer,
   long held keys, Reading/Latest scroll position, server/token changes, restart,
   disconnected/reconnected devices and old/new companion versions.
3. **Existing candidate gates.** Physical paired-device battery and latency,
   background delivery, Low Power Mode, StoreKit purchase/cancel/pending/restore/
   offline/revocation, VoiceOver and larger type, Japanese, smallest watch layout,
   QR permission denial/regrant, and old/new server compatibility. Real provider
   hooks and push delivery need an explicitly opted-in integration test.
4. **Distribution and account state.** Verify the highest uploaded build and
   current App Store Connect state before choosing a new build number. Candidate
   source is 1.0.8 (14); public US App Store is 1.0.8. Use a newer marketing version
   for the release, with a verified available build number. Archive/export,
   production APNs entitlement, processing/compliance, IAP association and review
   state remain unverified. Existing Fastlane lanes update metadata only; they
   do not upload a binary or submit for review.
5. **Privacy and listing reconciliation.** Public App Privacy declares Device ID
   for app functionality, not linked to identity. The app manifest has no tracking
   and an empty collected-data list. Audit the optional relay's device-token and
   payload handling, then reconcile the manifest, policy and listing accurately.
   Verify legal/support URLs, update stale March submission instructions and
   release notes, and use final-build screenshots in the required device classes.

No archive, upload, submission, deployment, push, hook installation, or live
notification has been performed in this pass. Shipping authorization does not
replace these validation gates or any required agreement/credential approval.

## Accurate promotional statements

Source-supported narrow wording: **No account required. Connect to your own tmux
host. Optional push alerts use a cloud relay and Apple Push Notifications.**

Do not say “no relay,” “no data ever leaves your device,” “end-to-end encrypted,”
or that new privacy features are released. No analytics/ad SDK was found in the
inspected sources, but that does not prove all hosted infrastructure keeps no
logs. Public listing: https://apps.apple.com/us/app/tmuxonwatch/id6759545173.

For current marketing captures, use native-resolution iPhone and Watch images
and genuine 20–30 second recordings with safe demo content. A clean 9:41/status
bar can be used when supported. Keep Pro input disclosure, use intact accurate
device artwork, and retain a separate clearly labelled historical-draft set
until current footage passes review.
