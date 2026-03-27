# App Review Notes Template (Copy/Paste)

Use this in App Store Connect -> Version -> App Review Information -> Notes.

## Reviewer Notes

tmuxonwatch is a companion viewer for tmux output from a self-hosted server running on the user’s own Mac.

How to test without external setup:

1. Launch app
2. On onboarding step 1, tap `Try Demo`
3. The app displays sample terminal content and watch UI behavior without requiring a server.

How to test full live mode (optional):

1. On Mac: run `bash <(curl -sSL https://tmuxonwatch.com/install)`
2. Scan QR code in iPhone app onboarding
3. Confirm terminal output appears in iPhone and Apple Watch companion app

Remote Push (optional):

1. Open Settings -> `Remote Push (Webhook)`
2. Turn on `Enable Remote Push`
3. Allow notification permission when prompted
4. Tap `Send Test Push`

In-App Purchase details:

- Product ID: `tmuxonwatchpro`
- Type: Non-consumable (one-time unlock)
- Unlocks watch input actions (send keys / session switching from watch)
- Free features remain available without purchase (viewing terminal output, notifications, themes, polling settings)

The iPhone app has standalone functionality as a live terminal viewer/configuration app; Apple Watch is a companion display/input surface.
Remote Push is optional and disabled by default on new installs.
Core terminal viewing works without enabling notifications.

No account/login is required.
No third-party ad SDKs or tracking SDKs are used.

## Contact (fill before submission)

- First name:
- Last name:
- Phone:
- Email:

## Demo Account

Not applicable (no user account system).
