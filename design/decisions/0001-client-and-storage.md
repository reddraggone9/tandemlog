# 0001 — Flutter client and portable file history

Status: **accepted by Lee, 2026-09-30**. Supersedes the Rust/Dioxus recommendation in the historical review.

Use Flutter/Dart, SQLite as the sole rebuildable local cache, and canonical per-device JSON logs in a selected shared folder. Reliability, maintainability and startup/performance matter more than development speed. Do not add a Rust bridge without a concrete need.

Serverless phone-to-phone, file-based synchronization is foundational and provider-independent. BasicSync is Lee's current Android provider, not an integration dependency. A future optional server must remain additive. No transport should decide domain conflicts.

All data is shared by default within one data space. The immutable workspace ID defines the boundary; events from another space are rejected. Future private folders may sync among one person's devices; UI filtering is not privacy and cross-space references are not implemented.

Consequences: Android SAF requires a real platform adapter and validation across restart/replacement; SQLite and writer identity stay outside synced folders. Native Windows verification needs Windows. Linux/browser evidence cannot substitute. Native adapters remain small in responsibility, not necessarily in effort.

Alternatives considered: Rust/Dioxus, Flutter plus Rust FFI, service-dependent sync. Revisit only for demonstrated limitations, recording evidence and migration effects.
