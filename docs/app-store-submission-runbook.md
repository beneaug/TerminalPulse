# tmuxonwatch release runbook

This is an existing published app, not a first submission. Use the latest [prerequisite verification](release-prerequisites-2026-11-11.md) and [readiness audit](value-readiness-2026-11-11.md); historical March build numbers are obsolete.

- App Store ID: `6759545173`
- Team: `YRXM89L3ZW`
- iPhone: `com.augustbenedikt.TerminalPulse`
- Watch: `com.augustbenedikt.TerminalPulse.watchkitapp`
- Non-consumable: `tmuxonwatchpro`
- Current source: `1.0.8 (14)`; do not reuse for a new upload.

## Before creating a release

Verify App Store Connect's live version and highest uploaded build, account/team, agreements, product state, and signing. Pass CI and the physical-device/sandbox checklist. Resolve privacy disclosures and review current-build screenshots, localization, and review instructions. A working archive or public listing alone does not satisfy these gates.

## Archive and export

Use Release, generic iOS destination and automatic signing. Existing Xcode-managed profiles support automatic signing; forcing them into manual signing fails. Archive the iPhone scheme, which embeds the Watch app. For a local distribution check, export with method `app-store-connect`, destination `export`, automatic signing, and automatic version management disabled. Keep build numbers explicit and reviewed. A local export is not an upload.

Verify the exported phone and Watch signatures, matching team and bundle IDs, embedded privacy manifest, `get-task-allow=false`, and phone `aps-environment=production`. Run the intended final binary through the applicable tests.

## Authorized submission only

After release authorization, upload the final numbered binary, wait for processing, resolve actual compliance questions, select that build, verify the Pro product and current metadata/captures/review notes, then submit. The existing Fastlane lanes upload listing text/screenshots only; they do not upload a binary or submit it for review. Do not invoke them during a read-only account check.

The source declares `ITSAppUsesNonExemptEncryption=false`; verify the actual binary/use case against Apple's current export-compliance requirements instead of treating that value as legal approval.

References:
- https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app
- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
