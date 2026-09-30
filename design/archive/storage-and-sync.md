> Historical design from commit `1be49b4`; not an implementation specification.
> See [current design index](../README.md). Latest user direction and approved decisions take precedence.

# Storage & Sync

## Storage: Append-Only Event Log

The database is a log of immutable events, not a table of mutable state. Current state is _derived_ by replaying events in order.

**Per-node JSONL logs** are the unit of storage: one append-only file per node, one event per line.

Each install generates a stable `node_id` automatically: 128 random bits encoded as base64url without padding. This `node_id` is opaque and is used in the owning node's log filename. Reinstallation will simply orphan the old `node_id` and generate a new one.

Example:

```
logs/q7L9xT2eWmN4Kc8pV1aZ0Q.jsonl
logs/bM6rH1sNf2YpJ8dLw4UcXA.jsonl
...
```

Each node only appends to its own log file. No two nodes should ever write to the same canonical file. Within a log file, each event is identified by its `clock`; globally, an event is identified by `(node_id, clock)`, where `node_id` is implied by the filename.

If a log ends with a truncated or otherwise invalid final JSON line, readers should treat the file as ending at the last valid line. If the reader owns that log file, it should truncate the broken tail away.

Each event is a JSON object:

```json
{
  "clock": 1741376580000000000,
  "type": "task_field_changed",
  "payload": { "task_id": "abc123", "field": "due_date", "value": "2026-03-08" }
}
```

This payload is illustrative, not prescriptive. The storage layer requires immutable events with deterministic replay ordering, but it does not require every logical change to be encoded as a single-field update. Event shapes for coupled fields and invariant enforcement belong to the data model and replay/materialization design.

`clock` is a signed 64-bit integer storing UTC nanoseconds since the Unix epoch. On a local write, the node compares the current timestamp to the highest clock it has seen (from itself or any synced node). If `now_ns > max_seen_clock`, it uses `now_ns`; otherwise it uses `max_seen_clock + 1`. This preserves a local total order for writes while staying close to wall time in the common case. `(clock, node_id)` is the global deterministic replay order.

Each install persists `max_seen_clock` in the local snapshot so it can preserve this invariant across restarts without rescanning all logs before writing a new event. If local wall time is materially behind `max_seen_clock`, the app should warn but still allow initialization and local writes.

Note: if any JS/TS layer touches `clock`, use `BigInt` or a canonical string encoding rather than `Number`.

## Sync: Syncthing

Syncthing handles file transport between devices. It works peer-to-peer, requires no central server, and syncs directly between phones over a hotspot when there's no internet. Because each node owns its own append-only log file, Syncthing is transporting per-node logs rather than arbitrating concurrent writes to a shared one.

Node discovery is filename-based: the app scans the synced log directory for valid `logs/<node_id>.jsonl` files and starts tracking any previously unknown `node_id` automatically. While running, it watches the log directory and known log files for changes and reruns the incremental ingestion flow when new files appear or existing files grow.

A central server is intentionally avoided so that any two devices that can see each other can still exchange data, even if some other machine is offline.

## Convergence: Deterministic Replay Order

On startup:

1. Load the local JSON snapshot (contains per-node log read offsets); if no snapshot exists yet, start from an empty local cache and perform a full rebuild from the synced logs before allowing local writes
2. Load the local SQLite DB (per-entity event history + indexes)

After startup initialization, run the following incremental ingestion flow once immediately, and again whenever synced logs change while the app is running:

1. For each known node log, seek to the stored local byte offset and read forward; if a saved offset is invalid (for example, because the file was truncated or manually repaired), fall back to a full rescan of that node's log
2. Parse any newly appended events
3. Insert the new events into SQLite, indexed by entity, with `node_id` inferred from the log filename; enforce uniqueness on `(node_id, clock)` so rescans and reprocessing are idempotent
4. Determine which entities were touched by the new events
5. Rebuild only those entities from their per-entity event history in SQLite, ordered by `(clock, node_id)`
6. Write the rebuilt entities back into the in-memory snapshot, update `max_seen_clock` and the read offsets

After the startup incremental run, asynchronously persist the updated snapshot to disk if it changed.

This replay order also defines conflict resolution. When the data model represents two offline edits as competing writes to the same logical value, convergence falls out of replay order, effectively yielding last-writer-wins by `(clock, node_id)`; exact convergence semantics are left up to the data model. Deletion is terminal during replay: once an entity's history includes a delete event, it is omitted from the materialized snapshot and later events for that entity are ignored. Logical restoration of a deleted entity (such as a user triggering an 'undo') is achieved by appending a new creation event with identical data, rather than modifying the historical delete event.

**Why not raw wall-clock timestamps alone?**
Raw timestamps can go backwards, collide, or arrive out of order after a partition. The clock preserves a local total order by borrowing future nanoseconds when needed, while still staying close to wall time in the common case.

## Startup Performance: Local Snapshot + SQLite

Replaying the full event history on every startup would become slow as the log grows. The local materialization layer avoids that.

The local JSON snapshot stores the current materialized global state, `max_seen_clock`, and per-node log byte offsets:

```json
{
  "max_seen_clock": 1741376600000000003,
  "log_offsets": { "q7L9xT2eWmN4Kc8pV1aZ0Q": 1234567, "bM6rH1sNf2YpJ8dLw4UcXA": 987654 },
  "tasks": { ... },
  "time_logs": { ... }
}
```

A local SQLite DB stores per-entity event history and indexes derived from the canonical synced per-node JSONL logs. Together, the snapshot and DB let the incremental sync process touch only affected entities rather than replaying the whole world. Snapshot writes should be atomic (for example, write temp file then rename). The app should also rewrite the snapshot on clean shutdown so a normal exit preserves the latest local cache.

**Neither the snapshot nor SQLite is synced.** They are local caches, not source of truth. Every install can rebuild them from the canonical event logs if needed.

## Log Retention

The canonical per-node JSONL logs are retained indefinitely. No log compaction or history squashing is part of this design. Storage is treated as cheap enough that the synced append-only logs remain the source of truth in full, while the local snapshot and SQLite DB handle performance.
