# Legal Posture: Open Source + Paid Features

Yes, this is possible.

## What Is Possible

1. You can open-source the code repository.
2. You can still sell a one-time IAP in the official App Store build.
3. You can reserve brand/trademark rights for the `tmuxonwatch` name and logos.

## Key Tradeoff

If code is open source, others can fork it. Depending on license choice, they may also redistribute modified builds (including with paywall removed).

Open source gives transparency and community trust, but does not by itself prevent copycats.

## Recommended Practical Setup

1. License code under `Apache-2.0` (App Store-friendly, permissive).
2. Reserve trademark/brand assets in a separate policy (`TRADEMARKS.md`).
3. Keep official branding and distribution channel value in the official App Store app.
4. Continue monetizing convenience/pro features in official build via IAP.

## If You Want Stronger Fork Restrictions

If your main goal is stopping commercial forks, use a source-available commercial license instead of OSI open source. That sacrifices "open source" status.

## Selected Posture

Selected in this repository:

1. Code license: `Apache-2.0`
2. Trademark reservation: `TRADEMARKS.md`
3. README license section updated
4. Website Terms language updated to match

## Repo/Website Changes Needed For Open-Source Posture

1. Add `LICENSE` file.
2. Update README license section to match chosen license.
3. Add trademark policy file for brand usage rules.
4. Update website Terms section so it matches repo license posture.

If you later want stronger anti-fork controls, switch to a source-available commercial license. That would no longer qualify as open source.
