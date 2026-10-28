# Current unified action schema

Implementation under validation. [ADR0031](decisions/0031-coordinated-unified-cutover.md) supersedes earlier live wire readers. The [previous schema](archive/schema-before-coordinated-cutover.md) remains historical documentation for frozen readers and the external converter.

## Manifest and action

A current canonical folder contains tandemlog-space.json and one <installation UUID>.applog per writer. Protocol5's immutable manifest has exactly v,id,epoch,sourceDigest,owners,referenceAuthors. Each owner seals a converted prefix with count, head and digest; historical functional reference namespaces map to current authors. Labels never determine identity. A new installation appends its own standalone joined action.

A committed record is one canonical UTF-8 JSON object followed by LF. Its exact keys are v,space,epoch,writer,seq,clock,previousHash,observed,effects,provenance,hash. Nested objects sort keys. Physical sequence is positive contiguous per writer. Clock is an exact decimal nanosecond string, increasing per writer and beyond observed clocks even after rollback. SHA-256 domains are tandemlog:app-action:v5 followed by LF, and tandemlog:app-genesis:v5 followed by LF with space/epoch/writer binding.

Each effect is {kind,raw}. Live Task/Food effects in one atomic action share author and have consecutive logical IDs, increasing clocks and chained predecessors. Logical effect sequences are separate from physical line numbers. Installation metadata is standalone. Historical and live effects cannot mix. Historical converted prefixes contain one verified normalized effect per old committed record, sealed by the manifest.

The observed frontier binds writer positions/hashes, including the action's predecessor. Missing dependencies hold the whole action and dependent actions. Wrong hashes, unknown complete effect kinds/revisions, malformed records, changed acknowledged prefixes and sync conflicts stop common admission. Both module projections stage in one SQLite transaction before publication.

Optional provenance is exactly kind,namespace,planHash,sourceSha256: `food.import` for an add-only Food import action, or `food.purchase-import` for a receipt import containing only container adds/links, product edits and purchase records ([Food products](food-products.md#5-method-prices-and-receipt-import)). It makes repeated accepted imports identifiable without a private ledger. Limits16MiB/action,32MiB/file,256MiB/workspace and10000effects apply before append; incremental effect-byte accounting bounds preparation. The current1000-item import fits one action.

## Operation registry

domain/current_operation.dart defines the closed current codec: format tandemlog.operation, version1, module, space, author, identity, clock, subject, operation family/revision, value, predecessor, referenceHash and contentHash. Content hashing covers the normalized body. Converted prefixes may retain verified historical reference anchors; live operations derive their anchor from their own exact content hash. The common action seals attribution and all normalized data.

Envelope format version, operation revision and new event families are distinct. Newly supported timezones use required revision2 for create/update; every new task.complete uses required revision3 with only a canonical UTC microsecond completedInstant (all four completion modes), cumulative with revision2 timezone meaning. Historical r1/r2 retain their date semantics and are not emitted by live commands; startup, draft choice, Cancel and no-op Save do not update compatibility metadata. A complete unknown family/revision fails both modules before continuing writes. There is no separate mutable reader floor or timezone toggle.

Food products (on `vex/food-products`, unreleased) add the required families product.edit, product.merge, purchase.record, purchase.edit and container.link (revision1), and container.add revision2 with an explicit product/purchase link; plain Adds still write container.add revision1. container.undo revision1 retracts every Food family; Undo of a product-level operation carries no container creation basis. A pre-products app stops at the first such record with "Update the app; history was preserved". Values, bounds and merge rules: [Food products](food-products.md#4-method-sync-log-protocol).

Old wire decoders are absent from the app. Current semantic reducers retain task/native text/recurrence/Undo/Food meaning. A domain action is not a legacy wire decoder.

## Commit, tails and local profile

A complete valid LF-terminated action is canonical authority. Unfinished bytes/native prepared handles are process memory only for same-session reconciliation. Restart never replays private intent. A fully appended action can survive without visible acknowledgement.

An unterminated suffix, including complete JSON without LF, is uncommitted. A nonowner ignores it without modification. Before its next action, the owner may compare/truncate only that suffix through an explicit safe capability and confirm the retained prefix before reserving new bytes. Read-only validation never truncates. Complete invalid records remain corruption. Desktop uses regular-file compare/truncate/flush/postcheck. Android uses nontruncating rw and same-descriptor compare/fstat/ftruncate/fsync. A provider lacking this capability refuses a new write after restart; it never replaces a committed prefix.

Private schema6 has protected_settings, profile_metadata, protected_app_workspaces and protected_app_heads plus rebuildable Task projections/native checkpoints. No durable unfinished-save outbox, conversion journal or capability table remains. Recognized old local profiles retain installation ID/folder/person/appearance/last section under the exclusive owner and reset other private state. Invalid identity, malformed settings, damaged current authority and future versions fail without reset. This policy authorizes no real-profile mutation.

See [ADR0035](decisions/0035-exact-completion-instants.md) for required revision3 completion instants, offline cutover approximation, viewer-local Completed/search chronology, and unchanged recurrence/Undo.
