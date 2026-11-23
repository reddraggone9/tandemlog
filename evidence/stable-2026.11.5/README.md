# Stable 2026.11.5 / build127

Promotion of Lee-accepted [RC126](../prerelease-2026.11.5-rc.1/README.md), source f5de444d. Lee accepted 2026-11-23 13:34 CST: “LGTM. Let's publish that stable upgrade.”

Version-only promotion: pubspec version/build and the same-base metainfo RC entry replaced by one stable entry. This stable follows stable125 and covers one RC, so the stable notes body is byte-identical to RC126's independently reviewed notes (no media); no second review is required by the notes rule. No application source, dependencies, budgets or qualification identity changed. The RC126 reference (52e14803) and native cold-start receipts are reused after verification (`reference_receipt.py verify` and `native_cold_start.py verify` PASS on the promotion tree).

Signed candidate [45250859311](https://github.com/reddraggone9/tandemlog/actions/runs/45250859311) passed all 12 jobs on ef94d788 (reference-performance with the reused RC126 receipts); `verify-candidate.py` PASS (`candidate-verification.json`): APK be38b49b…, signer pin, 2026.11.5/127, non-debuggable.

Scripted acceptance of the exact candidate APK and Flatpak (`native-acceptance.json`), both PASS: RC126→127 on the retained labs as RC126 acceptance left them, then 125→127 after restoring the exact public stable125 bytes and RC126's recorded stable125 data. Checked install identity (UID, firstInstallTime), retained folder grant, canonical files unchanged by install and prefix-only after use, SQLite integrity, usable Android launch plus two cold reopens, two GTK cold reopens with normal exit 0. Synthetic data only. Windows GUI remains Lee's own coverage.
