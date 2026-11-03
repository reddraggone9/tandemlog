# Stable 2026.11.0/build113

[Stable 2026.11.0](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.11.0), release 432735389, was published 2026-11-03T13:29:56Z from exact source `b363a13fadca08b72eb020ee0abc0a29a84563d8`. It promotes the accepted 2026.11.0-rc.1/build112 (Lee, 2026-11-03 06:51 CST): the Activity log redesign, monthly Repeat rules, the next occurrence's date on completion, bulk-editor Review selection, the neutral startup screen, and fixes for Move some suggestions, Inbox rows and planned agent commits colliding in the text cache.

- **Change from RC:** version metadata and documentation only (pubspec 2026.11.0+113, the same-base RC row replaced by the stable row in AppStream metadata, stable notes, README Activity line). Notes are byte-identical to the reviewed RC notes (`d907847f`), including their Before/After images.
- **Performance:** qualified reference q12 `9d82e5c2` / identity `a579f229` (`single-sample-confirm-v1`) reused. No new qualification, budget change or override.
- **Hosted runs:** signed candidate 41639486016 and automatic push CI 41639469591 both passed on attempt 1, full matrix, no reruns.
- **Candidate:** [candidate-verification.json](candidate-verification.json) records exact inventory, source, checksums, owner signer and Linux/Windows install smoke.
- **Upgrades:** [native-acceptance-summary.json](native-acceptance-summary.json) records the exact APK and Flatpak installed in place over the retained synthetic RC 112 labs used for RC acceptance. Android kept its first-install time, writer/user/folder binding and persisted folder grant; both showed Version 2026.11.0 in Settings, opened retained data, passed the integrity check, showed the Activity log with day headings, appended a task completion with every earlier log byte kept, and kept it through a cold reopen. GTK closed normally (exit 0) both times.
- **Publication:** three installers and the original portable ZIP were digest-verified in a private draft before finalizing, with no rebuild.
- **Public check:** [public-verification.json](public-verification.json) confirms anonymously the immutable Latest release, tag/source, notes and their 3 images, all 4 asset bytes, and all 49 prior releases and tag refs unchanged. The public APK signer matches the owner pin.

## Recorded deviations

- The GTK pre-install snapshot was first taken without permission to read the lab and captured nothing. The RC acceptance run's final snapshot stands in as the pre-install state; the post-install snapshot is byte-identical to it, with no launch in between.
- The GTK lab had no open task left from RC acceptance, so one synthetic task was added before the completion check.

## Limits

Synthetic Android API 30 x86_64 emulator and native Linux GTK only. No physical device or Windows GUI acceptance in this record; owner-device updates are tracked outside the repository. Raw receipts stay private and are bound by SHA-256 in the summary.
