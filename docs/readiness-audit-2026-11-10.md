# Readiness audit — 2026-11-10

Scope: isolated branch `audit/readiness-r20`, based on `8db4258146102d87b507341528cf3b99868063c8`. No production deployment, store submission, real purchase, or changes to LINEUP.

## Fixed

1. Connecting a real host cleared the demo flag before the connection callback checked it. The callback consequently failed to cancel demo animation, allowing synthetic frames to overwrite live output. Cancel unconditionally and guard every asynchronous demo frame against leaving demo mode.
2. Animated demo display and the reading/copy snapshot could disagree because the latter was throttled with Watch delivery. Update the phone's payload and display together; throttle only Watch transmission.
3. Pro sheet: black text improves contrast on the lime purchase button; remove the repeated description in the input sheet. Purchase behavior is unchanged.
4. README: background refresh is opportunistic, not guaranteed continuous polling. Correct the documented polling range/default.

## Automated evidence

| Check | Result |
|---|---|
| Python host suite, isolated declared dependencies | 67 passed |
| Swift package suite | 36 passed |
| Hosted iOS lifecycle/reading regression tests | 2 passed |
| Local StoreKit purchase/restore/refund, pending approval, cancellation/empty restore | 3 passed |
| Baseline reproduction of both demo regressions | Both tests failed on baseline; 12 assertion failures |
| Debug iPhone and embedded Watch build | Passed through test build |
| Release iPhone and embedded Watch build | Passed, including locally ad-hoc signed simulator build |
| Project plist, localization JSON, installer shell syntax, diff whitespace | Passed |

Local StoreKit uses SKTestSession, the existing catalog and synthetic transactions. Approval/refund entitlement delivery is asynchronous; tests use bounded polling. No production payment was made. CI now includes the hosted app tests, but this new remote CI step has not run yet.

Reproduce hosted tests with `xcodebuild -project TerminalPulse/TerminalPulse.xcodeproj -scheme TerminalPulse -configuration Debug -destination 'platform=iOS Simulator,id=<available iPhone UDID>' -only-testing:TmuxAppTests CODE_SIGNING_ALLOWED=NO DEBUG_INFORMATION_FORMAT=dwarf-with-dsym test`. Interactive Keychain validation requires a signed simulator build; an unsigned build's Keychain failure is not evidence of a production defect.

## Observed simulator and host integration

Release configuration; iOS 26.2 iPhone 17 Pro Max simulator paired with watchOS 26.2 Series 11 46mm. Ordinary onboarding and demo flow, no Pro override. Host bound only to 127.0.0.1:18787, dedicated tmux socket `tmuxonwatch-r20`, synthetic token. Remote push/notifications disabled.

- Save token, connect, verify authentication/session/first output; demo stops and real output remains.
- Real tmux session output on phone and Watch; Read & Find returns expected matches.
- Reading sheet and search text concealed in phone app-switcher preview; returning restores the live view. Keyboard remains visible, without terminal/search content in its suggestions in this observation.
- Watch Reading holds a snapshot; Latest plus explicit Refresh displays new output. No automatic delivery latency measurement is claimed.
- Watch Always On hides terminal content and waking restores it. This is screen shielding, not screenshot prevention or biometric locking.
- Host timeout produces Reconnecting and retry UI; restarting the same host restores Live without credential re-entry.
- Largest Dynamic Type main controls remain visible and stack. Bottom-of-sheet reachability was not verified because automation scrolling did not move the form.
- HTTP integration: invalid token 401; correct capture; pane-bound literal input and explicit Enter; ETag 304; ambiguous input 422; unsupported key 400; unsafe target rejected without execution; nonzero window base index supported.

Captures contain actual local test results (67 Python and 36 Swift), not invented completion output. Review composites add illustrative bezels; they are not photorealistic hardware proofs. Raw captures remain internal sources.

## Remaining release gates

- Establish distributed App Store binary/source parity. Matching version/build labels alone do not prove parity; current fixes are not shipped.
- Run new CI on the intended remote branch and review the isolated patch before integrating.
- Physical iPhone developer-image compatibility remains blocked with the current host/Xcode combination; earlier device check reported CoreDevice 12040 / PersonalizedBundleMissingVariantError. No physical footage is claimed.
- Physical background delivery, battery/Low Power, Watch connectivity and mixed companion versions, real sandbox purchase/Watch entitlement, wrist-down/lock and VoiceOver still require validation.
- Complete largest-type sheet navigation, Japanese and smallest supported Watch checks.
- Exercise real provider hooks/optional push separately; reconcile relay/APNs disclosures with listing/privacy policy/manifest.
- Account Holder agreements and release credentials remain separate submission gates. No agreement accepted by this audit.

## Promo truth constraints

Use one real session across Mac, phone and Watch. Say “For workflows that run in tmux,” not universal agent integration. The configured host runs the session; phone fetches output and forwards it to its paired Watch. Optional push has a separate relay/APNs path. Avoid “everything stays on device,” zero-latency, perpetual background delivery, or blanket end-to-end encryption claims.

The cinematic social film can use original device compositions. The App Store preview should be separately capture-led and checked against current Apple requirements; the standing bezel preference must be reconciled explicitly before export. This audit is not a release-readiness certification.
