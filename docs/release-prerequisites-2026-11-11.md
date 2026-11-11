# Release prerequisite verification — 2026-11-11

## Distribution and devices

- Public US App Store: 1.0.8, released April 28. Candidate source is still 1.0.8 (14); these numbers are validation-only and must not be uploaded again.
- Safari initially displayed cached metadata for uploaded 1.0.8 (14), team YRXM89L3ZW, then redirected to login on fresh navigation. That cached page does **not** verify the latest uploaded build or current agreements. Apple passkey sign-in requires the owner's Touch ID.
- CoreDevice currently marks both known iPhones, iPad, and Watch Series 6 unavailable. No physical installation, real sandbox transaction, Watch entitlement propagation, background/Low Power/battery, or physical VoiceOver check was performed.
- The Keychain has valid Apple Development and Apple Distribution signing identities. Existing iPhone and Watch development profiles expire February 2027; App Store profiles expire April 2, 2027.
- Automatic local archive signing succeeds with cached profiles. Local `app-store-connect` export with `destination=export`, `signingStyle=automatic`, and `manageAppVersionAndBuildNumber=false` succeeds without provisioning updates or upload. Manually forcing the Xcode-managed profiles failed, so automatic signing is the supported verified path here.
- Exported signatures verify with `codesign --verify --deep --strict`. The phone is signed by Apple Distribution for team YRXM89L3ZW, `get-task-allow=false`, and `aps-environment=production`.

## Privacy evidence and correction

Vercel production deployment `dpl_9ySMP9NXibJbT3ENkGn45pLvAnhM` for www.tmuxonwatch.com reports source `beneaug/tmuxonwatch.com@790049c2fa922aca757915730ccbfe2ee9c3b505`. The deployed source matches the isolated audited checkout. No production code or configuration was changed.

| Data | Verified implementation | Disclosure treatment |
|---|---|---|
| Server address and authentication token | Address in phone preferences; auth token in Keychain | Correct EN/JA policy; do not claim both use Keychain |
| APNs device token | Relay Redis mapping under a SHA-256 notify-token digest; rolling 120-day configured expiry | Declare Device ID, app functionality, no tracking; same category already appears on public listing |
| Request IP address | Redis abuse-limit key; registration/unregistration 10-minute configured window; webhook 1 minute | Explain IP-based abuse prevention; review its category/purpose with the complete provider practices before publishing ASC answers |
| Notify-token hash | Mapping and rate limits; rate-limit windows up to 1 hour | Explain hashed mapping and rate limits |
| Webhook title/message | Forwarded to APNs; no payload-history database in the inspected relay code | Policy already discloses notification content; do not claim no cloud processing or end-to-end encryption |
| Watch terminal cache | Local cached display content | Keep local-cache disclosure; screen concealment is not storage encryption |

The app manifest now includes `NSPrivacyCollectedDataTypeDeviceID` for `NSPrivacyCollectedDataTypePurposeAppFunctionality`, not linked/tracking, based on this source audit rather than merely copying the listing. This does not certify every hosting/provider log or custom user-selected relay. Provider retention/settings and full label review remain before publication. Opt-in alone does not exempt ongoing collection from disclosure.

Prepared website wording also says disabling push **attempts** unregister; a failed request does not guarantee immediate server deletion. Configured Redis expiration is not an audit of every live key. No device-token database contents, notification payloads, or production secrets were read, and no alert was sent.

References:
- https://apps.apple.com/us/app/tmuxonwatch/id6759545173
- https://developer.apple.com/app-store/app-privacy-details/
- https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests
- https://vercel.com/docs/rest-api/deployments/get-a-deployment-by-id-or-url

## Next release sequence

1. Complete the final-head CI result and diagnose any hosted StoreKit failure; local tests are not a substitute for a green remote run.
2. Complete Apple sign-in; verify latest uploaded build, live version, selected team, agreements and approved non-consumable `tmuxonwatchpro`. Select a new version/build only after this check.
3. Connect/unlock/trust a physical iPhone and paired Watch, with supported developer access. Install the candidate without overwriting unrelated app data; exercise fresh and upgrade configurations, reconnect, background/Low Power, privacy in app switcher/Always On, large text/VoiceOver, Reading/Latest, input context changes, and mixed companion versions.
4. Verify purchase/cancel/pending/restore/refund on real StoreKit sandbox and both-device entitlement propagation; no real-money purchase is needed.
5. Review and publish the policy correction separately, reconcile provider practices and ASC disclosures, then create current-build listing captures and review EN/JA copy.
6. Rebuild/export the final numbered binary, verify its embedded Watch/signatures/privacy manifest, and only upload/submit after release authorization. No upload or submission occurred during this pass.

## CI runtime diagnosis

Run 43060246608 completed the server/core tests and all four Debug/Release builds. On Xcode 26.6 with iOS 26.4.1, both hosted lifecycle tests passed, then SKTestSession configuration calls logged `SKInternalErrorDomain Code=3`; purchase tests hit their two-minute execution allowances and the step hit its twelve-minute cap. The uploaded xcresult is incomplete (no Info.plist after interruption), so the retained job log is the usable evidence.

This matches the upstream command-line StoreKit regression reported in https://github.com/flutter/flutter/issues/184678 and Apple's StoreKit Test forum (FB22237318). Local Xcode/iOS 26.2 passes all five hosted tests. CI therefore keeps modern-SDK Debug/Release builds on the current runner and moves the entire hosted suite to macOS 15 with Xcode 26.2 and an explicitly required iOS 26.2 simulator. Missing runtime fails rather than silently substituting another. All assertions, timeouts and diagnostic retention remain. This is a test-environment qualification, not a claim that production purchases are verified on current devices.

Pinned runner inventory: https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md
