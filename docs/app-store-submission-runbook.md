# App Store Submission Runbook (tmuxonwatch)

This runbook is tailored to the current project configuration in this repository.

## Current Project Snapshot

- App name: `tmuxonwatch` (App Store Connect record already created)
- iOS bundle ID: `com.augustbenedikt.TerminalPulse`
- watchOS companion bundle ID: `com.augustbenedikt.TerminalPulse.watchkitapp`
- Current marketing version: `1.0.4`
- Current build number: `3`
- IAP product ID (non-consumable): `com.tmuxonwatch.pro`
- App icon asset present: `1024x1024`, no alpha

## Why The App Icon Is Missing In App Store Connect

For App Store display metadata, Apple uses icon data from an uploaded, processed build. If no processed build is selected for the version, App Store Connect often shows the placeholder icon.

Action:

1. Upload a signed App Store build from Xcode.
2. Wait for processing.
3. Select that build in the version’s `Build` section.

Reference: https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon

## Pre-Submission Checklist

1. In App Store Connect, confirm Agreements/Tax/Banking are complete (`Business` section).
2. In Xcode, increment `CFBundleVersion` (build number) before each upload.
3. Archive with Release signing for `Any iOS Device`.
4. Upload via Organizer to App Store Connect.
5. Wait for build processing and resolve any `Missing Compliance`.
6. Complete required metadata for the app version:
   - App description, keywords, support URL, marketing URL (optional)
   - Privacy policy URL (required)
   - Screenshots for required device classes
   - App Review Information (contact + notes)
7. In App Privacy, ensure data collection answers are accurate and complete.
8. In the app version, attach IAP `com.tmuxonwatch.pro` in `In-App Purchases and Subscriptions`.
9. Click `Add for Review`, then `Submit for Review`.

References:

- Submit app: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app
- Submit first IAP: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase
- App privacy metadata: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy

## Export Compliance Notes

The app currently has `ITSAppUsesNonExemptEncryption = false` in `Info.plist`, which is correct when no export docs are required for your use case.

If App Store Connect asks compliance questions, answer them at build/version level. If documentation is required, upload it in App Information.

References:

- Overview: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- Encryption docs: https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation

## Submission Sequence (First Release)

1. Upload build.
2. Wait until build is `Processed`.
3. Select build for version `1.0`.
4. Attach `com.tmuxonwatch.pro` in that same version submission.
5. Add App Review notes (see `docs/app-review-notes-template.md`).
6. Submit review.

Important: first-time IAP must be submitted with a new app version.

Reference: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase

## Common Review Risks For This App

1. Reviewer can’t access core functionality because no server setup instructions.
Mitigation: provide clear review notes + mention demo mode.

2. IAP not attached to submission.
Mitigation: verify it appears in `In-App Purchases and Subscriptions` on version page before submitting.

3. Privacy answers too narrow.
Mitigation: answer based on app + any integrated third-party SDK behavior.

4. Missing icon/screenshot confusion.
Mitigation: ensure processed build is selected; screenshots uploaded for all required sizes.

## Promo Codes Clarification

Your screenshot is consistent with Apple’s rule that app promo codes require a distributable app version, and IAP promo codes require approved IAP. Also, Apple indicates IAP promo codes are being replaced by offer codes starting March 2026.

Reference: https://developer.apple.com/help/app-store-connect/offer-promo-codes/request-and-manage-promo-codes
