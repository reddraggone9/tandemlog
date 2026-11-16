# Stable 2026.11.4 / build125

Promotion of Lee-accepted [RC124](../prerelease-2026.11.4-rc.1/README.md), source 3a9e7d8f. Lee accepted 2026-11-16 06:56 CST: “Looks good! Please publish stable.”

Version-only promotion: pubspec version/build and the same-base metainfo RC entry replaced by one stable entry. This stable follows stable123 and covers one RC, so the stable notes body is byte-identical to RC124's independently reviewed notes (no media); no second review is required by the notes rule. No application source, dependencies, budgets or qualification identity changed. The RC124 reference and native cold-start receipts are reused after verification.

Signed candidate [43871336458](https://github.com/reddraggone9/tandemlog/actions/runs/43871336458) passed all 12 jobs on d8832f17 (reference-performance with the reused RC124 receipts); `verify-candidate.py` PASS (`candidate-verification.json`): APK 0e3b000e…, signer pin, 2026.11.4/125, non-debuggable.

Scripted acceptance of the exact candidate APK and Flatpak (`native-acceptance.json`), both PASS: RC124→125 on the retained RC124 labs, then 123→125 after restoring the exact public stable123 bytes and RC124's recorded stable123 data. Checked install identity (UID, firstInstallTime), retained folder grant, canonical files unchanged by install and prefix-only after use, SQLite integrity, usable Android launch plus two cold reopens, two GTK cold reopens with normal exit 0. Synthetic data only. Windows GUI remains Lee's own coverage.

Anonymous public verification pending. Owner-device rollout is separate.
