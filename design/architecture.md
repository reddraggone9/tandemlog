# Architecture

Status: accepted direction; see [ADR 0001](decisions/0001-client-and-storage.md) and [implemented schema](schema.md).

## Boundaries

Use a modular monolith. Start with ordinary Dart modules; extract packages only when dependency boundaries or build targets benefit.

| Area | Owns | Must not own |
| --- | --- | --- |
| Tasks domain | Commands, invariants, task/user state, deterministic projection | UI framework, SQLite, filesystem, model calls |
| Application | Use cases, current user/workspace, durability workflow, command IDs | OS-specific APIs or duplicated domain rules |
| Persistence/sync adapter | Canonical records, validation, ingestion, private cache, recovery | UI behavior or transport-defined conflict rules |
| Platform adapters | Desktop paths, Android URI trees/grants, lifecycle, later notifications/capture | Task or quantity semantics |
| UI | Rendering, input, navigation, accessible feedback | Direct SQL/log writes |

Inject time, IDs, storage and platform services at boundaries. Commands produce validated domain events; incoming events use the same versioned deterministic projection semantics, not current UI validation or current wall time. Keep diagnostics available even if a workspace cannot safely open for writing.

RC4 extracts single/bulk editor draft ownership into `presentation/task_editor.dart`; host navigation owns editor-session identity and dirty-close routing. `domain/bulk_task_edit.dart` describes explicit functional patches and per-task results, while `TaskStore` serializes validation/durable writes. UI passes target/context guards, never writes SQL/logs. Per-task partial durability is explicit; do not hide it behind an apparent multi-task transaction. Main still combines workspace/filter/drag orchestration; extract a focused controller when concrete duplication or another workflow warrants it, rather than a generic framework during this candidate.

Future games, nutrition and inventory are separate domain modules with explicit integration commands. A food entry that deducts stock is one logical operation, with linked idempotency and reversal rules, rather than two UI callbacks. Shared foundations should stay small: workspace/user identity, event envelope, quantities where needed, and adapter contracts. No plugin engine, universal entity/field store, generalized CRDT framework or microservices now.

## Trust and privacy

A selected user is not a security principal. A Syncthing peer that can alter the shared directory can fabricate another user's content; encrypted transport does not add application authorization or encrypt files at rest. Initially assume explicitly trusted household devices. Keep secrets, tokens and SQLite caches private. Before adding personal food/weight data, decide sharing boundaries; hiding a screen is not privacy. Workspace separation is simpler than field-level permissions on a shared log.

Model-derived content is untrusted input. A later ingestion adapter produces a proposal with source/provenance, uncertainty and structured fields. Deterministic parsing/validation and an explicit human acceptance step create normal commands. Never allow receipts or transcripts to issue tool calls, select arbitrary filesystem paths, invent IDs, or write logs directly. Keep imported strings inert in UI; bound attachment/event sizes. Uploads to an external model require an intentional user workflow.

## Growth and review

At each milestone, review dependencies, duplicated rules, error/recovery paths, UX consistency and actual performance. For every module addition, review cross-module transactions and compatibility before UI expansion. Record refactors and bounded debt; do not use “future flexibility” to justify unused infrastructure.
