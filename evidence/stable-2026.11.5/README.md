# Stable 2026.11.5 / build127

Promotion of Lee-accepted [RC126](../prerelease-2026.11.5-rc.1/README.md), source f5de444d. Lee accepted 2026-11-23 13:34 CST: “LGTM. Let's publish that stable upgrade.”

Version-only promotion: pubspec version/build and the same-base metainfo RC entry replaced by one stable entry. This stable follows stable125 and covers one RC, so the stable notes body is byte-identical to RC126's independently reviewed notes (no media); no second review is required by the notes rule. No application source, dependencies, budgets or qualification identity changed. The RC126 reference (52e14803) and native cold-start receipts are reused after verification (`reference_receipt.py verify` and `native_cold_start.py verify` PASS on the promotion tree).
