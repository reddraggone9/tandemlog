# Design map

## Current source of truth

Lee approved Flutter/Dart + SQLite cache + canonical per-device JSON logs on 2026-09-30. File-based provider-independent serverless sync is foundational. Default household data is shared within one space. Tasks are the current implementation; future modules remain separate.

1. [Status, commands and limitations](status.md)
2. [Product and milestone](product-behavior.md)
3. [Onboarding and everyday UI rationale](decisions/0002-onboarding-and-everyday-interface.md), [approved stack decision](decisions/0001-client-and-storage.md) and [stack](tech-stack.md)
4. [Architecture](architecture.md)
5. [Storage design](storage-and-sync.md), [implemented schema](schema.md), [recovery](recovery.md)
6. [Runtime/visual QA](runtime-qa.md) and [rc2 task-based UX audit](ux-audit-rc2.md)
7. [Deferred modules](future-modules.md)
8. [Repository rules](../AGENTS.md)

The [initial review](review.md) is historical rationale; later accepted decisions supersede its recommendations. Original [product](archive/product-behavior.md), [storage](archive/storage-and-sync.md), and [stack](archive/tech-stack.md) documents are archived, not active requirements. Obsolete `data-model.md` was removed as requested; recover it from Git if needed.

Each subject has one source of truth. Keep status/evidence current; link rather than duplicate specifications. New consequential choices receive an ADR and explicit accepted/proposed status.

- [Builds and releases](releases.md): CI gates, test installation and signing limitations.
