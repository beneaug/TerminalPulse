# tmuxonwatch App Store Screenshot Specs (v1)

This spec matches your current Figma direction: vivid solid background, watch + iPhone composition, bold condensed copy.

## Canvas Targets

- iPhone 6.7: `1290 x 2796` (`iphone-67-template.*`)
- iPhone 6.9: `1320 x 2868` (`iphone-69-template.*`)

## Visual Tokens

- Background: `#F2CE3B`
- Primary text: `#101114`
- Secondary text: `rgba(16,17,20,0.80)`
- Device shell dark: `#0F0F12`
- Screen dark: `#0B1220`
- Accent line: `#22C55E`

## Type

- Headline: `Helvetica Neue Bold`, tracking `-22`
- Subtext: `Helvetica Neue Regular`, tracking `-16`
- Headlines are intentionally tight; if clipping appears on export, relax to `-18`.

## Layout Coordinates

### 6.7 in (`1290x2796`)

- Safe frame: `x=64 y=64 w=1162 h=2668`
- Copy zone: `x=88 y=106 w=720 h=390`
- Main iPhone outer: `x=506 y=502 w=708 h=2160`
- Main iPhone screen placeholder: `x=596 y=700 w=528 h=1688`
- Watch outer: `x=92 y=1120 w=360 h=440`
- Watch screen placeholder: `x=124 y=1160 w=296 h=328`

### 6.9 in (`1320x2868`)

- Safe frame: `x=66 y=66 w=1188 h=2736`
- Copy zone: `x=92 y=112 w=736 h=402`
- Main iPhone outer: `x=532 y=514 w=722 h=2220`
- Main iPhone screen placeholder: `x=624 y=718 w=538 h=1736`
- Watch outer: `x=100 y=1146 w=372 h=454`
- Watch screen placeholder: `x=132 y=1188 w=308 h=338`

## Launch Copy Pack (Suggested)

Use one slide per line item.

1. Headline line 1: `LIVE TMUX.`
2. Headline line 2: `ON WRIST.`
3. Subtext line 1: `Track your active pane.`
4. Subtext line 2: `See output in seconds.`
5. Visual note: Hero split layout (watch + iPhone terminal).

1. Headline: `CHECK STATUS FAST.`
2. Subtext: `See what changed without pulling out your laptop.`
3. Visual note: Watch-focused screenshot crop.

1. Headline: `FOLLOW LONG RUNS.`
2. Subtext: `Keep up with builds, logs, and long-running tasks.`
3. Visual note: Terminal output with clear progress lines.

1. Headline: `POWER MODE: CONTROL.`
2. Subtext: `One-time unlock for watch input and tmux window switching.`
3. Visual note: Show controls row and swipe affordance.

1. Headline: `PRIVATE BY DEFAULT.`
2. Subtext: `Uses your own host setup and tmux session context.`
3. Visual note: Settings/connection view.

## Store Compliance Notes

- Avoid claiming this is a full standalone SSH client.
- Avoid leading with remote/VPN claims in App Store screenshots.
- Keep “watch input + window switching” language tied to the one-time unlock.
- Use real in-app UI in screenshots; avoid concept-only mockups for final upload.

## Export Checklist

- Export PNG at `1x` from the template dimensions.
- Keep all copy inside safe frame.
- Maintain one strong message per screenshot.
- Verify no sensitive hostnames or secrets appear in terminal screenshots.
