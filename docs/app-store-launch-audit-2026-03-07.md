# App Store Launch Audit

Date: 2026-03-07

## Verified Locally

- Release build succeeded for `TerminalPulse` with `generic/platform=iOS`.
- Archive succeeded for `TerminalPulse` at `/tmp/TerminalPulse-20260307114528.xcarchive`.
- Python server tests passed: `12` tests, `OK`.
- Current app version in Xcode: `1.0.7` (`CURRENT_PROJECT_VERSION = 7`).
- Bundle IDs:
  - iOS: `com.augustbenedikt.TerminalPulse`
  - watchOS companion: `com.augustbenedikt.TerminalPulse.watchkitapp`
- App icons exist at `1024x1024` for both iOS and watchOS asset catalogs.
- Generated plist settings include:
  - Camera usage description for QR setup
  - Local network usage description
  - `ITSAppUsesNonExemptEncryption = NO`
  - Background modes: `fetch`, `remote-notification`
- Privacy manifest exists and currently declares `UserDefaults` accessed API reason `CA92.1`.

## Code Status

- No compile blocker found in the current project state.
- Demo mode exists and should remain the primary App Review path.
- StoreKit product ID in the app is `tmuxonwatchpro`.
- The app does not include ad SDKs or tracking SDKs in the inspected codebase.

## Launch Risks To Manage

### 1. Remote-client review risk

Apple's current App Review Guideline `4.2.7` is still the biggest policy risk for this app category. Keep submission copy focused on:

- the user's own Mac
- tmux output viewing
- local/demo review flow
- optional features that are not required for review

Do not lead App Store screenshots, subtitle text, or review notes with:

- Tailscale or VPN marketing
- "remote access" slogans
- "SSH client" framing
- third-party agent brands

Reason: Apple still flags thin-client and remote-control interpretations aggressively.

Reference:

- https://developer.apple.com/app-store/review/guidelines/

### 2. App Privacy answers need careful review

Re-check App Privacy in App Store Connect against optional Remote Push behavior. When Remote Push is enabled, the system may process:

- APNs device token
- notify token
- webhook title/message payload
- relay registration metadata

That flow passes through Apple APNs and your hosting/storage providers. Make sure the App Privacy answers match the shipped behavior, including optional features.

Reference:

- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy

### 3. Screenshot set must match current Apple requirements

Before submission, verify the uploaded screenshot set matches the current required device classes in App Store Connect for this binary. At minimum, confirm the exact iPhone and Apple Watch classes Apple asks for on the version page.

Reference:

- https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications

### 4. Production signing still needs final export verification

The local archive succeeded, but it used a development identity and development provisioning profile during local signing. Before upload, do one final Organizer distribution/export path and confirm:

- App Store distribution signing is selected
- push entitlement resolves correctly for production upload
- the processed build appears in App Store Connect with no entitlement/compliance surprises

## Submission Checklist

1. Archive from Xcode for `Any iOS Device`.
2. Upload to App Store Connect and wait for `Processed`.
3. Attach the processed build to the app version.
4. Attach IAP `tmuxonwatchpro` to the same version submission.
5. Use App Review notes that start with `Try Demo` and do not require external setup.
6. Verify App Privacy answers against optional Remote Push relay behavior.
7. Verify screenshots do not contain risky wording, third-party brands, or secrets.
8. Confirm Support URL, Privacy Policy URL, and Terms URL are live and accurate.

## Recommended Review Positioning

Use language like:

- "Companion viewer for tmux output from a self-hosted server on the user's own Mac."
- "Demo mode is available immediately and does not require account or server setup."
- "Remote Push is optional and disabled by default."
- "Apple Watch is a companion display/input surface; core value is available on iPhone."

Avoid language like:

- "remote access from anywhere"
- "SSH on your wrist"
- "control your Mac from anywhere"
- third-party tool names in product screenshots

## What I Changed In This Pass

- Removed risky public marketing phrases from the website and launch-artifact sources.
- Reworded screenshot generator copy away from `SSH`, `AI agents`, and "from anywhere" positioning.
- Added this audit so App Store Connect review can be checked against current project state.
