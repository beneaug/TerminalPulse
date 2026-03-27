# App Store Connect Copy Recommendations

Date: 2026-03-07

## Blocking Issues From Current Screenshots

1. The app code previously used StoreKit product ID `com.tmuxonwatch.pro`, but App Store Connect shows `tmuxonwatchpro`.
2. App Privacy is currently set to `Data Not Collected`, which is likely too narrow if Remote Push remains in the shipping build.
3. The current description and keywords lead with `VPN`, `remote`, and `tailscale`, which increases App Review risk for this app category.
4. The current IAP review note says the purchase serves little functionality on iPhone, which is weak positioning for review.

## Recommended Promotional Text

Live tmux output on Apple Watch. Set up from your Mac in minutes with a QR scan. Pro unlocks watch input and watch-side window switching.

## Recommended Description

tmuxonwatch brings live tmux output from your own Mac to iPhone and Apple Watch.

Scan the setup QR code from the Mac installer, connect to your tmux server, and keep up with builds, logs, and long-running commands with readable monospace rendering tuned for small screens.

Free features include:
- Live terminal viewing on iPhone and Apple Watch
- Demo mode with sample terminal output
- Themes, font sizing, and polling controls
- Optional notifications when commands finish

One-time Pro unlock includes:
- Send keys from Apple Watch
- Watch-side session and window switching

## Recommended Keywords

tmux,terminal,watch,watchos,unix,developer,command line,logs,build monitor,server

## Recommended App Review Notes

tmuxonwatch is a companion viewer for tmux output from a self-hosted server running on the user's own Mac.

The review can be completed entirely without external setup:

1. Launch the app.
2. On onboarding step 1, tap `Try Demo`.
3. The app will show sample terminal output and Apple Watch companion behavior without requiring a server or account.

Optional live mode:

1. On a Mac, run `bash <(curl -sSL https://tmuxonwatch.com/install)`.
2. Scan the QR code in the iPhone onboarding flow.
3. Confirm tmux output appears in iPhone and Apple Watch.

Optional Remote Push:

1. Open Settings -> `Remote Push (Webhook)`.
2. Enable `Remote Push`.
3. Allow notification permission when prompted.
4. Tap `Send Test Push`.

In-app purchase details:

- Product ID: `tmuxonwatchpro`
- Type: Non-consumable
- Unlocks Apple Watch input controls and watch-side session/window switching
- Core viewing functionality remains available without purchase

No account or sign-in is required.
Remote Push is optional and disabled by default.

## Recommended IAP Review Note

This non-consumable unlock adds Apple Watch input controls and watch-side session/window switching for the paired companion app. Core iPhone and Apple Watch terminal viewing remains available without purchase.

## Recommended Metadata Removals

Remove these from the current submission copy:

- `secure access via VPN`
- `remote`
- `tailscale`
- wording that makes the app sound like a remote desktop or SSH client
- wording that minimizes iPhone value after purchase

## Privacy Follow-Up

If Remote Push remains enabled in the shipping app, revisit App Privacy before submission. The current `Data Not Collected` answer is likely not accurate because the app can register an APNs device token with your relay when the user opts into Remote Push.
