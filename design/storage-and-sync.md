# Storage and sync

[ADR0031](decisions/0031-coordinated-unified-cutover.md) and the [current schema](schema.md) specify the implemented current-only boundary. Validation is ongoing. Earlier released formats remain in [historical documentation](archive/storage-and-sync-before-coordinated-cutover.md) and external frozen readers.

UnifiedHistory is the sole append allocator and common admission owner. TaskStore and FoodStore retain domain APIs over the same admitted revision. The provider transports immutable bootstrap metadata and per-installation append histories with delayed/reordered/repeated delivery; it decides neither authorship nor merge meaning. Sync only the selected canonical folder, never the private app profile.

One atomic action/Save contains its typed effects in one physical record. Bulk capture/placement, edits, deletion/Undo, recurrence and checklist writes use this boundary. Native Undo targets one saved text action; earlier saves are separate actions. Bounded Food imports carry canonical provenance. Historical conversion retains old committed boundaries.

The private profile owns one exclusive SQLite connection and serialized queue. Complete candidate heads and both projections commit before publication. Exact admitted effect bytes acknowledge saves independently of physical line numbers. Unfinished bytes/native handles remain in memory only; startup admits canonical history without replaying unfinished private intent. Partial tails wait or receive owner-only safe suffix cleanup before new writes. Complete corruption, conflict copies and unknown complete semantics fail closed.

Current admission follows [ADR0007](decisions/0007-canonical-history-integrity.md): providers with demonstrated bounded seek and usable change hints reuse unchanged admitted files and read only growth from the last complete newline. Missing hints, replacement, shrinkage or uncertainty use bounded full reads. Unchanged hints cannot reveal same-size old-prefix damage; Settings Verify Logs and full reconstruction deliberately read and verify all bytes. Explicit chain commitments bind protected physical heads; legacy byte digests are fully checked before promotion. Own actions validate a coherent snapshot plus their delta and confirm exact appended bytes before committing both projections. Startup still reads actual canonical bytes and verifies physical/protected/migration evidence. A one-shot layout2 decode receipt can reuse exact-raw immutable Task/Food objects; a separate clean Task projection witness avoids redundant semantic rebuilding. Cache parsing/checksums and complete typed-table proof checks remain proportional to saved cache size. Tooling records actual read counts and timing boundaries. A shared poll performs common admission for both adapters; unchanged semantic slices retain identity.

## External coordinated cutover

The one-time converter stays outside the repository. Its input is an accepted frozen canonical copy after all apps stop and sync settles, with immutable originals and an explicit historical-to-current writer mapping. Compare every historical prefix through frozen/current and native replay, preserving text lineage, references, Undo, recurrence, tombstones and ordering. Final rows alone do not prove equivalence.

Retain continuing installation IDs and folder selections plus simple preferences. Other private state may reset, including drafts and unfinished saves; full profile export is not required. Sync-node count does not determine historical authors. Missing mappings stop conversion.

Only a separate live-cutover approval can adopt converted history. Old applications must remain stopped afterward. Reverting after new-format writes requires reconciliation rather than copying old files over new work. No development test opens, resets or converts a production profile/workspace.


Clean-cache startup preserves the same generation2 byte digest, scope binding,
kind/position checks and opaque receipts. Fresh decoded JSON trees are frozen in
place before unmodifiable views escape, avoiding redundant collection copies.
Pure whole-batch verification runs in a short-lived Dart isolate with only three
immutable strings; profile transactions, canonical reads/admission and native
text ownership stay on the owning queue. The one-shot proof is consumed durably
before awaiting the worker. Unavailable or failed optional verification falls
back to strict canonical reconstruction. This improves UI responsiveness rather
than promising that verification or disk durability takes less than100ms.
A full owned canonical candidate may reuse its already-computed Task root after
an exact cached ID/raw bijection; a cached prefix retains its own root check
before any arriving delta is admitted.

Supported first text, metadata and copied-checkbox actions can reuse exact
pre/post earliest-target and parent-seed proofs, as described in the
[latency repair](task-latency-repair.md). Changed or uncertain seeds retain full
readiness. The remaining full-readiness pass indexes the earliest copy birth by
compareEvents once, including retracted and competing claims, instead of
repeating transitive copy-closure lookups. Successor selection, native checks
and every readiness dependency remain enforced.

Copy-seed lookup uses the existing owning validator's exact per-item claim
relation, not a transitive text-selection closure. The snapshot key, owning
validator, readiness and byte-exact inserted-candidate checks are shared with
selected text reads. Empty claims return an empty result; an untrusted scope
falls back to the original SQL oracle. All competing/retracted claims and
candidate claims are retained in compareEvents order. No new cache or size
budget is introduced.

See [ADR0035](decisions/0035-exact-completion-instants.md) for required revision3 completion instants, offline cutover approximation, viewer-local Completed/search chronology, and unchanged recurrence/Undo.

### Offline replay observation

`TaskStore.validateSemanticHistory` can optionally expose all materialized rows
through `onAllRows` for external normalization/replay comparison. Ordinary visible
rows deliberately exclude tombstones, suppressed successors and checklist items;
those filters must not hide state from the offline equivalence oracle. The
observer does not change runtime admission, projection, authority or persistence.
Frozen historical readers remain byte-exact; any external observation-only
adapter must prove its limited instrumentation delta separately.
