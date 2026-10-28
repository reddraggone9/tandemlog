# Stable 2026.10.8/build103 preparation

Candidate source is published 2026.10.8-rc.1 (main 865f945, product source 03ecab3) with only release metadata changed: `pubspec.yaml` 2026.10.8+103, the Flatpak metainfo release entry (2026.10.8-rc.1 development → 2026.10.8 stable), `design/stable-notes.md` and this record. No product, test, tooling or workflow change.

## Lee authorization / lee_accepted attestation

Lee, Discord DM 2026-10-28 01:19 CDT, after testing RC.1: “Almost. I've looked at that RC and it seems fine. Are we ready to promote it to stable?” Vex replied that it was ready and started the promotion; he did not object. This is acceptance of the behavior-changing RC.1 source for stable. lee_accepted may be true only after all candidate gates complete; it does not attest they have already passed.

## Notes

`design/stable-notes.md` is the published RC.1 notes body byte-for-byte under a stable heading. Those notes and media passed the independent editorial review before RC.1 publication and are not materially revised.

## Reference performance

Relevant-source identity v2 ignores the version-only pubspec line and plain Flatpak release list, so the existing passing qualification (request 9b29fa84, identity 4d8842a2…) covers this source without a new reference run.

## Format

Same unified workspace format as 2026.10.7: no conversion, no live data operation.
