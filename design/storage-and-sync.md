# Storage and sync contract

Approved foundation: canonical per-device JSON logs and one SQLite cache. [Protocol v1](schema.md) describes the implemented subset and [recovery](recovery.md) its limits. This document explains the larger contract.

## Canonical data and local cache

Retain per-writer append-only JSONL as the initial format for any compatible folder-sync transport. Only the owning install writes its stream, with one local writer lock. Scope writer identity to a workspace, keep it outside synced data, and do not clone it through backup/restore. Duplicate IDs with different payloads are corruption, not ignorable duplicates. Use lowercase filename-safe IDs to avoid case-sensitive naming assumptions.

Separate event identity `(writer ID, durable sequence)` from logical order and occurrence time. A Lamport-style counter plus writer ID is sufficient for deterministic task ordering; UTC timestamps are metadata, not truth about concurrent human intent. Persist/recover sequence and clock before another write; rescan owned history and available imported records on cache rebuild. Bound counters and reject malformed values. No global sync barrier is needed to work offline.

Canonical append succeeds durably before a command is acknowledged. Then ingest/project into **one private SQLite transaction** containing event rows, affected projections and per-stream checkpoints. If the process dies between append and cache commit, re-ingest; command/event IDs make retries idempotent. If the cache is gone, rebuild from logs. An in-memory view is fine; an independently persisted JSON snapshot is unnecessary initially. Provider-specific durability must be demonstrated, not inferred from POSIX APIs.

## Ingestion and corruption

Reopen replaced files and rescan on resume, periodic checks and explicit refresh; watchers are hints. Offset alone is insufficient: detect changed/truncated prefixes, replacement, disappearance, and conflicting copies. At first, favor conservative full validation over an elaborate incremental optimization. Replacing an old prefix or removing a stream is a workspace integrity failure requiring visible recovery; do not silently retain stale cache data and claim convergence. Never treat missing history as entity deletion.

Read only complete newline-terminated records. Temporarily ignore an incomplete trailing record on a remote stream and retry. Repair an owned incomplete tail only under exclusive access after confirming interrupted append and preserving recovery evidence. A complete invalid record, conflicting event ID or unsupported required version gets diagnostics and write blocking for the affected scope; never truncate it as a “broken tail.” Bound input sizes and validate workspace IDs, filenames and payloads.

Syncthing [replaces destinations via temporary files](https://docs.syncthing.net/users/syncing.html), can generate conflict copies, and recommends rescans alongside watchers. Single-writer ownership reduces ordinary conflicts; it does not prevent cloned identities, manual edits or restores. Detect conflict filenames and stop treating transport as healthy until reconciled.

## Convergence semantics

Same validated event set plus the same projection version must produce identical state, regardless of arrival order or batching. Missing referenced events may arrive later: retain pending dependencies and rerun; do not permanently reject based only on arrival order. Per-field last-writer-wins is acceptable for independent task text fields, with a stable logical tie-break; it is not appropriate for inventory consumption or coupled date fields.

Undo must target an operation and be repeat-safe. For M1 completion, preserve completion IDs so undoing one's own completion does not erase another user's independent completion. Deletion/restore are deferred; decide identity-preserving tombstones versus intentional copy semantics before implementing them. Do not generate new authoritative events as a side effect of replay.

## Compatibility and recovery

Version the workspace protocol/envelope and each event meaning. New meaning gets a new version/type; never reinterpret old payloads in place. Use deterministic decoders/upcasters and fixtures spanning versions. Cache migrations are disposable: rebuild when incompatible. A changed projection algorithm still needs a compatibility decision to prevent two app versions producing different outcomes.

Preserve unknown records. Fail closed for unknown required semantics; independently versioned optional modules may remain unavailable while compatible tasks work only if dependency isolation is proven. Otherwise open safe read-only diagnostics and explain upgrade needs. Do not silently skip an unknown event and report a complete view.

Retain canonical history for M1; backup separately from sync and test restore with a fresh writer identity. Health/photo data will require a retention/privacy decision before adoption: indefinite logs make true erasure harder. Keep large attachments outside JSONL, linked by stable identifiers when introduced.

## Alternatives to evaluate only if needed

Sealed immutable event batches avoid repeatedly replacing growing logs and may fit document providers better, at the cost of file counts, publishing/recovery rules and more scanning. Benchmark/prove providers before changing format. A private durable outbox exported to a shared folder can improve availability when permissions vanish, but changes which data is authoritative; it needs an ADR. A service-based outbox sync can simplify setup but changes the no-server premise. No change to the canonical log foundation is implicitly approved here.
