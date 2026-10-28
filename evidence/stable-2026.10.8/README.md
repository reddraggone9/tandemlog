# Stable 2026.10.8/build103 preparation

Candidate source was published 2026.10.8-rc.1 (main 865f945, product source 03ecab3) with only release metadata changed: `pubspec.yaml` 2026.10.8+103, the Flatpak metainfo release entry (2026.10.8-rc.1 development → 2026.10.8 stable), `design/stable-notes.md` and this record. No product, test, tooling or workflow change.

## Lee authorization / lee_accepted attestation

Lee, Discord DM 2026-10-28 01:19 CDT, after testing RC.1: “Almost. I've looked at that RC and it seems fine. Are we ready to promote it to stable?” Vex replied that it was ready and started the promotion; he did not object. This is acceptance of the behavior-changing RC.1 source for stable. lee_accepted may be true only after all candidate gates complete; it does not attest they have already passed.

## Notes

`design/stable-notes.md` is the published RC.1 notes body byte-for-byte under a stable heading. Those notes and media passed the independent editorial review before RC.1 publication and are not materially revised.

## Reference performance

Relevant-source identity v2 ignores the version-only pubspec line and plain Flatpak release list, so the existing passing qualification (request 9b29fa84, identity 4d8842a2…) covers this source without a new reference run.

## Format

Same unified workspace format as 2026.10.7: no conversion, no live data operation.

## Publication

Published 2026-10-28T07:34:03Z as Latest: <https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.8>, release 426371483, source 6b8bb74.

- Push CI 40643574069 and signed candidate 40643585573: every job passed, each dispatched once. Hosted reference-performance verification passed on both.
- Candidate verification: owner signer pin 0a396940…, 2026.10.8/103, nondebuggable, arm64-v8a/armeabi-v7a/x86_64, checksums and install-smoke reports.
- Native: Android API30 emulator in-place upgrade from synthetic RC.1/102 (no folder prompt, data and user retained, batch Food edit + Undo, Task add/complete, cold reopen persistence, canonical manifest unchanged); isolated GTK Flatpak upgrade from published 2026.10.7 (data retained, batch Food edit persisted across restart). Synthetic data only.
- Draft path: three gated installers plus the original portable ZIP attached and digest-verified before finalizing.
- Anonymous check: Latest, tag → 6b8bb74, notes equal `design/stable-notes.md`, 7 note images, asset bytes equal candidate bytes, public APK owner signer; all 40 prior releases unchanged.
