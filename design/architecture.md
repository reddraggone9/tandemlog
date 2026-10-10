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

RC4 extracts single/bulk editor draft ownership into `presentation/task_editor.dart`; host navigation owns editor-session identity and dirty-close routing. Shared `presentation/tag_input.dart` owns focus and anchored suggestion geometry; its host owns selected values and query drafts. `presentation/tag_filter_picker.dart` is the thin Filter policy wrapper. `domain/bulk_task_edit.dart` describes explicit functional patches and per-task results, while `TaskStore` serializes validation/durable writes. UI passes target/context guards, never writes SQL/logs. Per-task partial durability is explicit; do not hide it behind an apparent multi-task transaction. Main still combines workspace/filter/selection/drag orchestration; extract a focused controller when concrete duplication or another workflow warrants it, rather than a generic framework during this candidate.

The authorized, unreleased text integration adds `application/task_text_session.dart`
for captured private drafts and `application/text_save_command.dart` for exact
canonical receipt/commit orchestration. `storage/text_cache.dart` validates and
materializes native field checkpoints in the same disposable SQLite cache.
Bounded process-local immutable-record/proof memos belong to storage/text
resolution, never editor/Undo ownership; every reused checkpoint must match the
independently verified native state.
The current shared-history redesign replaces per-prefix inherited packet arrays
with immutable original-operation references. Resolver admission shares original
claims and incremental unowned native documents; its bounded pool carries sparse
historical checkpoints. Memo entries carry visible summaries and references.
Original authority is retained once separately from disposable cache budgets.
New reference proofs and compact SQLite reference rows now avoid inherited BLOBs
and operation-ID arrays per occurrence; exact editor/receipt state is reconstructed
on demand. Adapter1 proof/checkpoint meanings remain supported. Full observed-prefix
scans and warm command costs remain scaling work; this is not a constant-latency
claim. Independent review and platform acceptance are pending. See the
[implementation evidence](../evidence/production-text/shared-history/README.md).
`text/native_text_engine.dart` owns typed FFI handles and bounded exact packets;
the single Rust implementation owns character identity and selective Undo only.
Domain context/actor claims and required event validation stay in Dart. See
[ADR 0010](decisions/0010-collaborative-text-adoption.md) for the legacy baseline,
offline new-task exception and remaining release gates.

The approved [Food inventory module](decisions/0014-food-inventory.md) uses its own canonical Food streams and pure physical-container projection, with recovery authority on the same app-owned SQLite connection and queue. Tasks retain their released v3 history. Future games and nutrition remain separate domain modules with explicit integration commands. A food entry that deducts stock is one logical operation, with linked idempotency and reversal rules, rather than two UI callbacks. Shared foundations should stay small: workspace/user identity, event envelope, quantities where needed, and adapter contracts. No plugin engine, universal entity/field store, generalized CRDT framework or microservices now.

The isolated checklist component keeps membership/order, item kind and durable
descendant protection in `domain/checklist.dart`. `storage/checklist_store.dart`
shares the existing TaskStore command/ingestion transaction as a focused part;
it owns parent/anchor admission and native copy-proof validation. Item title/notes
reuse item-scoped native contexts and receipts without new Rust or dependencies.
Native-enabled cache16 aggregates items under task projections, while the ordinary
task list excludes item rows. Immutable-prefix baseline selection and live
selection use the same pure descendant-protection rule. Editor captures and local
item writes check the containing task's availability; remote late work retains
normal deterministic restoration. The task list owns collapsed checklist disclosure and inline child panels;
children are outside parent selection/focus and task drag/drop geometry.
Reusable item widgets delegate durable commands to the host, using parent-,
workspace- and snapshot-scoped drag admission. Local sparse expansion entries
use the existing cache metadata and do not enter canonical history.
The host owns item capture/receipt lifetime independently from the parent draft.
`ChecklistCompletionCommand` reconciles a complete immutable item snapshot before
consent and again before preparation, renewing consent after incoming changes.
Exact Windows/Android acceptance remains pending; see
[ADR0011](decisions/0011-one-level-checklists.md).

Checklist validation currently revisits existing completion prefixes during
reconciliation/commands. Impact: larger checklists add work to the separately
documented historical prefix CPU debt. Owner: Tandemlog implementation with Lee;
exit: measured checklist native workflows meet the agreed device budget or a
bounded indexed verifier is independently reviewed. Revisit before stable
checklist promotion; do not claim linear replay or open-ended optimization here.

## Trust and privacy

A selected user is not a security principal. A Syncthing peer that can alter the shared directory can fabricate another user's content; encrypted transport does not add application authorization or encrypt files at rest. Initially assume explicitly trusted household devices. Keep secrets, tokens and SQLite caches private. Before adding personal food/weight data, decide sharing boundaries; hiding a screen is not privacy. Workspace separation is simpler than field-level permissions on a shared log.

Model-derived content is untrusted input. A later ingestion adapter produces a proposal with source/provenance, uncertainty and structured fields. Deterministic parsing/validation and an explicit human acceptance step create normal commands. Never allow receipts or transcripts to issue tool calls, select arbitrary filesystem paths, invent IDs, or write logs directly. Keep imported strings inert in UI; bound attachment/event sizes. Uploads to an external model require an intentional user workflow.

## Growth and review

The combined release candidate's app-wide profile owner serializes workspace and settings work through one SQLite connection; task namespaces borrow it explicitly. Startup performs source-backed migration before opening adapters, and failed workspace switches retain prior UI/importer/Undo ownership. See [ADR0013](decisions/0013-app-wide-local-database.md) for the integrated local persistence boundary and remaining platform acceptance.

At each milestone, review dependencies, duplicated rules, error/recovery paths, UX consistency and actual performance. For every module addition, review cross-module transactions and compatibility before UI expansion. Record refactors and bounded debt; do not use “future flexibility” to justify unused infrastructure.
