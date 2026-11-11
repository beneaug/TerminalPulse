# App value and readiness — 2026-11-11

This pass continues `2cd2ede` on `audit/value-readiness-r49`. It preserves the existing facelift, promo assets, free tier, and one-time Pro product. No merge, deployment, store upload, purchase, or submission is included. Draft metadata files describe this candidate, not the currently distributed app.

## Improvements implemented

- Setup now scrolls inside a stable header/footer, adapts explanatory text and controls to Dynamic Type, respects Reduce Motion, and wraps the install command instead of shrinking/truncating it. The copy control has a 44-point minimum target and a copied accessibility value. Supporting text has stronger contrast.
- The step header no longer hides the language menu from accessibility. Japanese setup and the new guidance are localized.
- Server guidance uses a Mac hostname, explicitly explains that 127.0.0.1 means the phone, and retains manual/QR setup. Successful connection button text stays black on lime.
- API requests normalize pasted trailing slashes while preserving reverse-proxy path prefixes. Unsupported schemes, absent hosts, embedded credentials, query strings and fragments fail before attaching/sending a token. Configuration errors do not echo potentially secret URL text.
- Network diagnostics redact hostnames and localized error details; HTTP status codes remain visible.
- Pending StoreKit purchases display an approval-waiting explanation. They do not grant input; verified entitlement approval updates the state. Purchase retry remains available so a declined Ask to Buy cannot permanently strand the button. Local StoreKit tests cover this transition.
- English/Japanese store description and release-note drafts explain the actual free/paid split and privacy/background limitations. Removed an unmeasured battery claim from README.

## Value retained

| Free | One-time Pro |
|---|---|
| iPhone/Watch live viewing; iPhone Read & Find/search/copy/share; Watch frozen Reading/Latest; themes/font sizing/refresh controls; default-on preview protection/private local alerts; demo; opt-in event adapters | iPhone/Watch deliberate input; Watch dictation/control keys/window switching; saved commands on iPhone |

Tool-neutral means workflows running in tmux, plus the documented opt-in notification contracts. It does not mean arbitrary native Windows hosting, universal agent control, or personal dot integration. No speculative new feature or subscription was added to this stabilization pass.

## Current evidence

- 67 server tests passed.
- 39 Swift core tests passed, including three new URL regression tests. Those three failed against the baseline with 16 assertion failures before the implementation fix. Final core suite passed after diagnostic redaction.
- Five hosted iOS tests passed: two demo/lifecycle/reading regressions and three local StoreKit purchase/restore/refund, pending approval, cancellation/empty-restore tests. These are synthetic SKTestSession transactions, not real App Store sandbox purchases.
- Debug iPhone/embedded Watch test build passed. Locally ad-hoc-signed Release simulator build passed. Final-source unsigned generic iOS archive, including Watch, passed. This is not a signed distribution archive or export.
- Fresh isolated iPhone SE 3 simulator, iOS 26.2: verified ordinary English/Japanese onboarding, language menu accessibility, normal and largest text, and keyboard focus/dismissal. Baseline keyboard pushed content into the status bar; revised header remains stable and focused credentials are brought into view. At largest text the connection action is visible after keyboard dismissal. Native automation wheel/drag scrolling was inconsistent; no blanket touch/VoiceOver certification is claimed.
- A new isolated 40mm Watch SE 3 / watchOS 26.2 simulator paired successfully. Initial launch showed Waiting for data; after relaunch it displayed the actual phone demo payload. Read/Latest interaction could not be completed because Simulator window-menu actions began returning CUA error -10005 despite refreshed state. This is not sufficient evidence for physical delivery latency or all compact-Watch flows.
- Privacy and support URLs both resolve to HTTP 200 after redirects. Public US App Store still lists 1.0.8. No accessible physical phone/Watch was available in CoreDevice at this check. The exact App Store binary/source relation and highest uploaded build are not verified.

## Release gates, in order

1. Review and run CI for this final candidate. Previous draft PR #1 was open, unmerged, with head `8db4258`; its existing CI succeeded. That older success is not evidence for this patch.
2. Complete compact Watch Reading/Latest and input flows, physical paired-device reconnect/background/Low Power/battery checks, VoiceOver, mixed companion versions, and real sandbox purchase/restore/entitlement propagation. iPhone setup keyboard checks do not substitute for the complete accessibility matrix.
3. Reconcile privacy disclosures. Live policy says both server URL and auth token are in Keychain; source stores the URL in UserDefaults and only the auth token in Keychain. The correct replacement is: “Server address is stored in app preferences on iPhone; the server authentication token is stored in the iOS Keychain. Terminal output and display preferences may be cached on the paired Watch.” Confirm relay retention against deployed relay source before making stronger claims. Public App Privacy declares Device ID; the app privacy manifest has an empty collected-data list. Review the relay's actual collection, retention, processors, and Apple's disclosure definitions before editing either declaration. Do not blindly copy one into the other.
4. Verify App Store Connect app/team, highest build/version, agreement state and signing. Choose a new release version/build only after that check; source remains 1.0.8 (14). Export/sign and test the intended binary, associate IAP, then obtain final release authorization.
5. Replace listing captures with verified current-build material. Review prepared English/Japanese metadata and policy wording before upload. Real provider-hook/remote-push delivery remains a separately opted-in integration test; no real alert was sent.

## Follow-up scope decisions

Settings currently persists connection fields as they are edited. Existing bound input contexts prevent stale drafts from silently targeting a newly edited host; this pass does not replace that contract. A future atomic “test then apply” editor should stage URL/token/optional push configuration together and cover cancellation, secure-save failure, and interrupted tests before changing persistence semantics.

Review artifacts live in the sibling `audit-r49` folder; they contain synthetic setup/demo content. Existing r48 films remain untouched.
