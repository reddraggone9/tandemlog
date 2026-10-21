# Storage and sync

[ADR0031](decisions/0031-coordinated-unified-cutover.md) and the [current schema](schema.md) specify the implemented current-only boundary. Validation is ongoing. Earlier released formats remain in [historical documentation](archive/storage-and-sync-before-coordinated-cutover.md) and external frozen readers.

UnifiedHistory is the sole append allocator and common admission owner. TaskStore and FoodStore retain domain APIs over the same admitted revision. The provider transports immutable bootstrap metadata and per-installation append histories with delayed/reordered/repeated delivery; it decides neither authorship nor merge meaning. Sync only the selected canonical folder, never the private app profile.

One atomic action/Save contains its typed effects in one physical record. Bulk capture/placement, edits, deletion/Undo, recurrence and checklist writes use this boundary. Native Undo targets one saved text action; earlier saves are separate actions. Bounded Food imports carry canonical provenance. Historical conversion retains old committed boundaries.

The private profile owns one exclusive SQLite connection and serialized queue. Complete candidate heads and both projections commit before publication. Exact admitted effect bytes acknowledge saves independently of physical line numbers. Unfinished bytes/native handles remain in memory only; startup admits canonical history without replaying unfinished private intent. Partial tails wait or receive owner-only safe suffix cleanup before new writes. Complete corruption, conflict copies and unknown complete semantics fail closed.

Current admission uses bounded payload scans and truthful read counters; it does not claim the retired incremental backend's zero-read warm path. Startup tooling retains workload, read counts and measured latency. A shared poll performs common admission for both adapters; unchanged semantic slices retain identity.

## External coordinated cutover

The one-time converter stays outside the repository. Its input is an accepted frozen canonical copy after all apps stop and sync settles, with immutable originals and an explicit historical-to-current writer mapping. Compare every historical prefix through frozen/current and native replay, preserving text lineage, references, Undo, recurrence, tombstones and ordering. Final rows alone do not prove equivalence.

Retain continuing installation IDs and folder selections plus simple preferences. Other private state may reset, including drafts and unfinished saves; full profile export is not required. Sync-node count does not determine historical authors. Missing mappings stop conversion.

Only a separate live-cutover approval can adopt converted history. Old applications must remain stopped afterward. Reverting after new-format writes requires reconciliation rather than copying old files over new work. No development test opens, resets or converts a production profile/workspace.
