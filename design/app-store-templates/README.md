# App Store Screenshot Templates

Launch-ready template pack for tmuxonwatch with your preferred style:

- Vivid solid background
- Helvetica Neue headline/subtext
- Tight tracking (`-22` headline, `-16` subtext)
- Split hero composition (watch + iPhone)

## Files

- `iphone-67-template.svg` (`1290x2796`)
- `iphone-67-template.png` (`1290x2796`)
- `iphone-69-template.svg` (`1320x2868`)
- `iphone-69-template.png` (`1320x2868`)
- `LAUNCH-SPECS.md` (copy + layout + export guidance)

## Usage

1. Import the SVG in Figma.
2. Replace the phone and watch placeholder regions with real screenshots.
3. Keep copy in the top guide box.
4. Export PNG at `1x`.

## Exporting Real Assets From Figma CLI/API

If MCP tool-call quota is exhausted, use REST export (stable + scriptable):

1. Create a Figma personal access token.
2. Run:
   `FIGMA_ACCESS_TOKEN=... ./export_figma_assets.sh --file JlmgstLYrGngH4JDybrP6Z --out /Volumes/SSD/tmuxonwatch/figma-assets --node watch-bezel=5:153 --node iphone-bezel=5:187`
3. Check `/Volumes/SSD/tmuxonwatch/figma-assets` for PNGs.

## Notes

- Templates are already at App Store portrait screenshot dimensions.
- SVG keeps the strict typography tokens (`-22`, `-16`) for Figma editing precision.
- PNG preview exports use slightly relaxed tracking so text stays legible in raster form.
- Keep paid feature language explicit: one-time unlock for watch input and tmux window switching.
- Do not market the app as a standalone SSH client.
