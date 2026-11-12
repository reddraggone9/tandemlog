# Storage and sync

[ADR0031](decisions/0031-coordinated-unified-cutover.md) and the [current schema](schema.md) specify the current-only boundary, released in stable 2026.10.7 (build 101) and adopted by the live cutover on 2026-10-27. Earlier released formats remain in [historical documentation](archive/storage-and-sync-before-coordinated-cutover.md) and external frozen readers.

UnifiedHistory is the sole append allocator and common admission owner. TaskStore and FoodStore retain domain APIs over the same admitted revision. The provider transports immutable bootstrap metadata and per-installation append histories with delayed/reordered/repeated delivery; it decides neither authorship nor merge meaning. Sync only the selected canonical folder, never the private app profile.

One atomic action/Save contains its typed effects in one physical record. Bulk capture/placement, edits, deletion/Undo, recurrence and checklist writes use this boundary. Native Undo targets one saved text action; earlier saves are separate actions. Bounded Food imports carry canonical provenance. Historical conversion retains old committed boundaries.

The private profile owns one exclusive SQLite connection and serialized queue. Complete candidate heads and both projections commit before publication. Exact admitted effect bytes acknowledge saves independently of physical line numbers. Unfinished bytes/native handles remain in memory only; startup admits canonical history without replaying unfinished private intent. Partial tails wait or receive owner-only safe suffix cleanup before new writes. Complete corruption, conflict copies and unknown complete semantics fail closed. A provider's in-progress staging copy of a valid app history (Syncthing's `.syncthing.<writer>.applog.tmp` / `~syncthing~<writer>.applog.tmp`) is not yet delivered history and is skipped until it is renamed into place; every other unexpected `.applog` name still fails closed.

Current admission follows [ADR0007](decisions/0007-canonical-history-integrity.md): providers with demonstrated bounded seek and usable change hints reuse unchanged admitted files and read only growth from the last complete newline. Missing hints, replacement, shrinkage or uncertainty use bounded full reads. Unchanged hints cannot reveal same-size old-prefix damage; Settings Verify Logs and full reconstruction deliberately read and verify all bytes. Explicit chain commitments bind protected physical heads; legacy byte digests are fully checked before promotion. Own actions validate a coherent snapshot plus their delta and confirm exact appended bytes before committing both projections. Startup reads the [local history store](history-store.md) (Lee 11-05): per writer, a sealed offset plus the exact last record, then only bytes after the seal; a strict full read and rebuild happens only when that check fails or there is no store. A separate clean Task projection witness, guarded by row triggers, avoids redundant semantic rebuilding. Tooling records actual read counts and timing boundaries. A shared poll performs common admission for both adapters; unchanged semantic slices retain identity.

## External coordinated cutover

The one-time converter stays outside the repository. Its input is an accepted frozen canonical copy after all apps stop and sync settles, with immutable originals and an explicit historical-to-current writer mapping. Compare every historical prefix through frozen/current and native replay, preserving text lineage, references, Undo, recurrence, tombstones and ordering. Final rows alone do not prove equivalence.

Retain continuing installation IDs and folder selections plus simple preferences. Other private state may reset, including drafts and unfinished saves; full profile export is not required. Sync-node count does not determine historical authors. Missing mappings stop conversion.

Only a separate live-cutover approval can adopt converted history (Lee approved and the household cutover ran on 2026-10-27). Old applications must remain stopped afterward. Reverting after new-format writes requires reconciliation rather than copying old files over new work. No development test opens, resets or converts a production profile/workspace.


The decoded-history blob and its whole-batch verification are replaced by the [history store](history-store.md).
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
