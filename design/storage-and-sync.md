# Storage and sync contract

Approved foundation: canonical per-device JSON logs and one SQLite cache. [Protocol v2](schema.md) describes the implemented subset and [recovery](recovery.md) its limits. This document explains the larger contract.

## Canonical data and local cache

Retain per-writer append-only JSONL as the initial format for any compatible folder-sync transport. Only the owning install writes its stream. Writer identity belongs to the installation's private settings; sequence and event identity are interpreted within each workspace. An installation-wide lease protects preferences and writing, with a defensive per-cache store lease. Keep identities outside synced data and do not clone them through backup/restore. [ADR 0006](decisions/0006-installation-identity-and-instance-lock.md) specifies legacy migration and settings reset. Duplicate IDs with different payloads are corruption, not ignorable duplicates. Use lowercase filename-safe IDs to avoid case-sensitive naming assumptions.

Separate event identity `(writer ID, durable sequence)` from logical order and occurrence time. Use the original wall-clock/causal scalar specified in the schema: max(current UTC nanoseconds, observed maximum + 1), serialized as an exact decimal string, with writer/sequence tie-breaking. The earlier pure Lamport implementation converged but lost the original approximate-recency intent for offline edits; [ADR 0003](decisions/0003-task-parity-and-prerelease-boundary.md) records the correction and nonblocking future-clock warning. Clock order preserves causality but cannot establish true human recency between unsynchronized devices. Persist/recover sequence and clock before another write; rescan owned history and available imported records on cache rebuild. Bound counters and reject malformed values. No global sync barrier is needed to work offline.

Append and ingest/project into **one private SQLite transaction** containing event rows, affected projections and per-stream checkpoints, then require the exact prepared `(event ID, raw bytes)` receipts before acknowledging a command. Append success alone is insufficient: a provider replacement can preserve older committed history while dropping the new suffix before ingestion. Missing receipts produce a visible failure; editors retain drafts and batches report only confirmed progress. Durability beyond process interruption still depends on platform/provider guarantees; see [stable readiness findings](stable-readiness-review-2026-10-02.md). If the process dies between append and cache commit, re-ingest; command/event IDs make retries idempotent. If the cache is gone, rebuild from logs. An in-memory view is fine; an independently persisted JSON snapshot is unnecessary initially. Provider-specific durability must be demonstrated, not inferred from POSIX APIs.

## Ingestion and corruption

Reopen replaced files and reconcile on resume, notifications, foreground polling and contextual error retry; watchers are hints. Lee approved persisted byte checkpoints: ordinary startup/resume/commands do not reread historical bytes when current size is available and the adapter can seek. Unchanged logs read zero bytes; growth admits only the new complete suffix. Cache 11 retains the old prefix digest and exact admitted-range hashes for an explicit `TaskStore.verifyHistory()` audit. It does not add canonical chain fields or change protocol v2. Unknown-size or unseekable providers conservatively full-read and verify. [The reconciliation decision and measurements](android-reconciliation-review.md) specify this tradeoff.

Missing known streams, truncation, manifest replacement, conflict copies and invalid new records still fail immediately. A same-length historical rewrite, or a rewritten prefix followed by valid growth, can remain unseen until an explicit full audit. This is accepted cached-versus-fresh divergence risk, not proof of immutable current files. A fresh/cache-rebuilt installation reads the current logs but loses a discarded cache's previous integrity baseline. Never treat missing history as entity deletion, rewrite timestamps, or silently reset a known integrity warning.

Read only complete newline-terminated records. Temporarily ignore an incomplete trailing record on a remote stream and retry. Repair an owned incomplete tail only under exclusive access after confirming interrupted append and preserving recovery evidence. A complete invalid record, conflicting event ID or unsupported required version gets diagnostics and write blocking for the affected scope; never truncate it as a “broken tail.” Bound input sizes and validate workspace IDs, filenames and payloads.

Syncthing [replaces destinations via temporary files](https://docs.syncthing.net/users/syncing.html), can generate conflict copies, and recommends rescans alongside watchers. Single-writer ownership reduces ordinary conflicts; it does not prevent cloned identities, manual edits or restores. Detect conflict filenames and stop treating transport as healthy until reconciled.

## Convergence semantics

Same validated event set plus the same projection version must produce identical state, regardless of arrival order or batching. Missing referenced events may arrive later: retain pending dependencies and rerun; do not permanently reject based only on arrival order. Per-field last-writer-wins is acceptable for independent task text fields, with a stable logical tie-break; it is not appropriate for inventory consumption or coupled date fields.

Undo must target an operation and be repeat-safe. For M1 completion, preserve completion IDs so undoing one's own completion does not erase another user's independent completion. Task deletion uses an identity-preserving canonical tombstone, recoverable through named session Undo while preserving independent newer writes; broader restore/copy workflows remain deferred. Do not generate new authoritative events as a side effect of replay.

## Compatibility and recovery

Version the workspace protocol/envelope and each event meaning. New meaning gets a new version/type; never reinterpret old payloads in place. Use deterministic decoders/upcasters and fixtures spanning versions. Cache migrations are disposable: rebuild when incompatible. A changed projection algorithm still needs a compatibility decision to prevent two app versions producing different outcomes.

Preserve unknown records. Fail closed for unknown required semantics; independently versioned optional modules may remain unavailable while compatible tasks work only if dependency isolation is proven. Otherwise open safe read-only diagnostics and explain upgrade needs. Do not silently skip an unknown event and report a complete view.

Retain canonical history for M1; backup separately from sync and test restore with a fresh writer identity. Health/photo data will require a retention/privacy decision before adoption: indefinite logs make true erasure harder. Keep large attachments outside JSONL, linked by stable identifiers when introduced.

## Alternatives to evaluate only if needed

Sealed immutable event batches avoid repeatedly replacing growing logs and may fit document providers better, at the cost of file counts, publishing/recovery rules and more scanning. Benchmark/prove providers before changing format. A private durable outbox exported to a shared folder can improve availability when permissions vanish, but changes which data is authoritative; it needs an ADR. A service-based outbox sync can simplify setup but changes the no-server premise. No change to the canonical log foundation is implicitly approved here.


## Validated local batches

Capture and bulk edit/tag/move/delete/Undo/reopen commands validate their complete event set against one reconciled cache before append. Sequence numbers and approved wall-clock causal values increase for every unchanged JSONL record. The serialized store queue prevents another local writer command from entering between preparation and append. Reference checks include delayed incoming dependencies on later prepared IDs. Caller snapshot/context guards run at the batch commit boundary, rather than suggesting a separate user permission check between every line.

One transport append still flushes; then one ingestion/cache transaction materializes all complete records. A batch is not crash atomic: complete prefix records can persist, an acknowledgement can fail after the full write, or an owned tail can be incomplete. Exact `(event ID, raw bytes)` receipts acknowledge only confirmed records. Retry preserves capture identities and skips already materialized creations/retractions. A complete-prefix failure can reconcile immediately; an incomplete owned tail remains preserved and blocks writing under the existing recovery policy. Do not truncate it or claim success. Cache failure never makes SQLite authoritative. No protocol/cache projection version change is needed for grouping unchanged records into one append.

Local event preparation checks only historical references affected by that proposed event; canonical ingestion still validates the full joined reference set. This removes repeated decoding of unrelated history without weakening late-dependency admission.

See [batch performance evidence](../evidence/rc5-batch-performance.json) and the reusable synthetic `tool/measure_batches.dart`. Its storage phases/counters are separate from perceived UI latency and Android document-provider behavior.


## Conditional recurring-completion Undo

RC8 adds one explicit cleanup-retraction meaning; existing completion retraction and checkbox Reopen retain their meanings. The [schema](schema.md#rc8-conditional-recurring-completion-undo) defines untouched-successor suppression, conservative independent-work/dependency protection, late-arrival restoration, surviving-seed selection and peer upgrades. Suppression is derived from immutable canonical records, not a deletion tombstone or canonical rewrite. Cache 9 rebuilds supported older materializations while retaining the established backup and integrity guards. A mixed Undo action still uses one flushed append, per-record exact confirmation and one cache transaction; complete-prefix and interruption behavior is unchanged.
