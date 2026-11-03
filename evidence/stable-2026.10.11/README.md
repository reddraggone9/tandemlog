# Stable 2026.10.11/build110

[Stable 2026.10.11](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.11), release 432283432, was published 2026-11-03T04:38:18Z from exact source `d52a81d47ff1b0400526eb9ce5bc03d1b795527e`. It promotes the accepted 2026.10.11-rc.1/build109 (Lee, 2026-11-02 22:00 CST): Activity log, Food recovery notices, Move some with large text, repeating-task selection, pinned Food controls and full-width sticky headings.

- **Change from RC:** version metadata and documentation only (pubspec 2026.10.11+110, the same-base RC row replaced by the stable row in AppStream metadata, stable notes, README feature line). Notes are byte-identical to the published RC notes (`3548689f`).
- **Performance:** qualified reference q6 `eaab6c53` / identity `59c446d5` (`single-sample-confirm-v1`) reused. No new qualification, budget change or override.
- **Hosted runs:** signed candidate 41575738097 passed on attempt 1, including its full check matrix. Automatic push CI 41575733635 failed only its diagnostic Linux disposal step (see deviations); no rerun.
- **Candidate:** [candidate-verification.json](candidate-verification.json) records exact inventory, source, checksums, owner signer and Linux/Windows install smoke.
- **Upgrades:** [native-acceptance-summary.json](native-acceptance-summary.json) records the exact APK and Flatpak installed in place over the retained synthetic RC 109 labs used for RC acceptance. Android kept its first-install time, writer/user/folder binding and persisted folder grant; GTK showed Version 2026.10.11 in Settings. Both opened retained tasks, passed the integrity check, appended one task completion with every earlier log byte kept, and kept it through a cold reopen. GTK closed normally (exit 0) both times.
- **Publication:** three installers and the original portable ZIP were digest-verified in a private draft before finalizing, with no rebuild.
- **Public check:** [public-verification.json](public-verification.json) confirms anonymously the immutable Latest release, tag/source, notes, all 4 asset bytes, and all 47 prior releases and tag refs unchanged. The public APK signer matches the owner pin.

## Recorded deviation

Push CI 41575733635 `checks / linux` failed in `verify_linux_disposal.py` (diagnostic only): after a normal window close, the app aborted at quit (`FlutterEngineRemoveView` returned `kInvalidArguments`, then `g_mutex_clear` on a locked mutex, exit -6). This is the known intermittent Linux quit-time abort first seen in CI 40426371191, on product code identical to the RC; the candidate's own Linux job on the same source passed. Under the gate rule, unchanged source was not rerun. Capturing core stacks for it is queued for the next release.

## Limits

Synthetic Android API 30 x86_64 emulator and native Linux GTK only. No physical device or Windows GUI acceptance in this record; owner-device updates are tracked outside the repository. Raw receipts stay private and are bound by SHA-256 in the summary.
