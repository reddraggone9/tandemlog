# Task protocol v1

Implementation: `lib/domain/event.dart`, `lib/storage/task_store.dart`. No old `data-model.md` schema is reused.

## Data space and files

A dedicated selected folder contains `tandemlog-space.json` (`v: 1`, random UUID `id`) and `<writer UUID>.jsonl`. Initializing separate unsynced folders creates different spaces; initialize one, transport its manifest, then join it on other devices. Identity mismatches are errors. Do not sync private profile folders.

Each newline-terminated event has `v`, `space`, `writer`, positive `seq`, positive logical `clock`, `entity`, `type`, `data`. Counters are bounded to the exactly representable JSON integer range. Per-writer sequence is contiguous and clock strictly increases. Global replay order is `(clock, writer)`; event identity is `(writer, seq)`. Logical order does not pretend to establish actual concurrent human recency.

| Event | Payload |
| --- | --- |
| `user.created` | name |
| `task.created` | title, description, assignee user ID |
| `task.edited` | changed title and/or description only |
| `task.completed` | empty object |
| `task.completionUndone` | completion event ID |

Users are attribution/assignment choices, not authenticated principals. Task creation enters Inbox; its first actual edit leaves Inbox. Completion removes the task from the active view. Undo retracts only the named completion, so another independent completion still stands. Multiple undo events are harmless. No task deletion, reassignment, recurrence, dates or reminder schema yet.

Text fields use deterministic per-field last-writer-wins. Creation is unique per entity. Missing entity dependencies remain stored until creation arrives. Projection never writes more events. User/task mixing and duplicate creation are errors.

## Durability and compatibility

Append with durable flush before materialization. SQLite transactions contain imported events, touched projections and stream checkpoints together. Restart after append/cache failure reimports once. Byte-prefix hashes detect changes to imported history when file metadata changes; Android revalidates every scan because provider metadata may be unreliable. Unchanged desktop files avoid parsing and projection replay. Do not edit logs while preserving metadata intentionally; supported transports must expose file changes.

Incomplete remote tails are retried. Incomplete owned tails, invalid complete records, unknown types/versions/fields, missing known logs, identity/counter violations and conflict copies are visible errors; writes validate history first and do not silently discard data. An unsupported cache version is blocked; rebuilding means closing the app, preserving canonical files and private writer identity, removing only cache SQLite/WAL/SHM, then reopening. Do not use cache deletion to conceal missing canonical history.

Protocol changes require a new version/decoder and historical fixtures; projection changes require compatibility review. No automatic destructive repair is included. See [recovery](recovery.md).

Commands and ingestion serialize through one store queue. Local commands validate their prospective projection and dependencies before canonical append. The manifest is checked on every refresh, including before writes. Undo references must resolve to an earlier logical-clock completion of the same task; unresolved remote references remain stored and are validated when their target arrives. Invalid references block ingestion transactionally.

Capture retries retain each pending task's entity ID within the running UI, remove acknowledged lines progressively, and check imported state before retrying an uncertain append. This is not a durable draft queue across process termination. Undo UI actions retain their originating store and are discarded when changing folders.

Store shutdown rejects new work and drains accepted operations before closing SQLite or releasing the writer lock. This preserves the single-writer boundary during folder changes or teardown. References that would become invalid when the next local event arrives are checked before append as well as during remote ingestion.
