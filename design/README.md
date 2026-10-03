# Design map

## Current source of truth

Lee approved Flutter/Dart + SQLite cache + canonical per-device JSON logs on 2026-09-30. File-based provider-independent serverless sync is foundational. Default household data is shared within one space. Tasks are the current implementation; future modules remain separate.

1. [Status, commands and limitations](status.md)
2. [Product and milestone](product-behavior.md)
3. [Onboarding and everyday UI rationale](decisions/0002-onboarding-and-everyday-interface.md), [approved stack decision](decisions/0001-client-and-storage.md) and [stack](tech-stack.md)
4. [Architecture](architecture.md)
5. [Storage design](storage-and-sync.md), [implemented schema](schema.md), [recovery](recovery.md)
6. [Runtime/visual QA](runtime-qa.md) and [current task-based UX audit](ux-audit-rc4.md) ([rc3 history](ux-audit-rc3.md), [rc2 history](ux-audit-rc2.md))
7. [Deferred modules](future-modules.md)
8. [Repository rules](../AGENTS.md)

The [initial review](review.md) is historical rationale; later accepted decisions supersede its recommendations. Original [product](archive/product-behavior.md), [storage](archive/storage-and-sync.md), and [stack](archive/tech-stack.md) documents are archived, not active requirements. Obsolete `data-model.md` was removed as requested; recover it from Git if needed.

Each subject has one source of truth. Keep status/evidence current; link rather than duplicate specifications. New consequential choices receive an ADR and explicit accepted/proposed status.

- [Builds and releases](releases.md): CI gates, test installation and signing limitations.

## Current milestone and supporting research

- [Task parity decisions](decisions/0003-task-parity-and-prerelease-boundary.md): authorized scope, time semantics and prerelease compatibility boundary.

- [Editing, bulk actions and installers](decisions/0004-editing-bulk-actions-and-installers.md): RC4 rationale.

- [Next task parity draft](next-task-parity-draft.md): research and source inventory underpinning the authorized parity milestone; ADR 0003 supersedes its earlier planning-only status.

- [Session Undo and toolbar fit](decisions/0005-session-undo-and-toolbar.md): RC5 rationale and conflict boundaries.

- [Stable readiness review](stable-readiness.md): required durable-data decisions before the first stable release.

- [Installation identity and locking](decisions/0006-installation-identity-and-instance-lock.md): one preferences-root lease, settings-owned writer UUID and local migration/reset.
- [Android reconciliation review](android-reconciliation-review.md): accepted checkpoint policy, SAF notification capabilities, measurements and limits.
- [Canonical record chains and integrity checks](decisions/0007-canonical-history-integrity.md): approved v3 wire contract, Settings audit, compatibility and trusted-head limits.
- [Calendar versions and promotion](decisions/0008-calver-and-release-promotion.md): approved naming, monotonic builds, resource bounds and separate stable acceptance.
