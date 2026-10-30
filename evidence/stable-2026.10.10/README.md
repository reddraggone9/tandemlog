# Stable 2026.10.10/build108

[Stable 2026.10.10](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.10), release 429395840, was published 2026-10-30T19:10:10Z from exact source `12b9f03b55915813345e8940c361ae58366ac02c`. It promotes the accepted 2026.10.10-rc.1/build107 (Lee, 2026-10-30 13:21 CDT): agent CLI/MCP, Food row selection and Move some.

- **Change from RC:** version metadata and documentation only; the same-base RC row was replaced in AppStream metadata. Notes are byte-identical to the reviewed RC notes (`0920a9ba`).
- **Performance:** qualified reference `50a8ca56` / identity `12a2167c` reused. No new qualification, budget change or owner override.
- **Hosted runs:** automatic CI 41106541492 and signed candidate 41106539516 both passed on attempt 1, with no reruns.
- **Candidate:** [candidate-verification.json](candidate-verification.json) records exact inventory, source, checksums, owner signer and Linux/Windows install smoke.
- **Upgrades:** [native-acceptance-summary.json](native-acceptance-summary.json) records Android stable 106→108 (minimum 11), Android RC 107→108 (minimum 12) and GTK Flatpak 106→108 (minimum 11). Each kept its canonical byte prefix and manifest, added exactly one `product.edit`, and retained open tasks through a cold reopen. GTK also showed the retained completed task in its history view. Android labs also retained their SAF grants and confirmed bulk Cancel exits selection without a write (accepted in ADR0037). Android Running low and integrity passed; GTK Running low and integrity passed before normal close (exit 0).
- **Publication:** three installers and the original portable ZIP were digest-verified in a private draft before finalizing, with no rebuild.
- **Public check:** [public-verification.json](public-verification.json) confirms anonymously the immutable Latest release, tag/source, notes, all 4 asset bytes, and all 45 prior releases and tag refs unchanged. The public APK signer matches the owner pin.

## Recorded deviations

- The GTK test installed the Flatpak from an early artifact of candidate 41106539516 while that run was still in progress. Its SHA-256 `2193aea2…` was then proven identical to the final candidate asset, so the evidence was retained.
- The Android 106→108 driver stopped on a stale second Done tap after integrity had passed. Settings had already closed and nothing had been written; the remaining steps were resumed in the same lab, and the 107→108 lab ran with the corrected driver.

## Limits

Synthetic Android API 30 x86_64 emulators and native Linux GTK only. No physical device, Windows GUI acceptance, owner device or live data. Raw receipts stay private and are bound by SHA-256 in the summary.
