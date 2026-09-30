# Task protocol v2

Implementation: `lib/domain/event.dart`, `lib/storage/task_store.dart`. This prerelease format explicitly rejects v1 manifests, events and caches. It does not rewrite or delete old canonical data. Use a new dedicated v2 folder; stable compatibility promises begin at 0.1.0.

## Data space and files

A selected canonical folder contains `tandemlog-space.json` (`v: 2`, UUID `id`) and `<writer UUID>.jsonl`. Initialize once and transport the manifest to joining devices. SQLite is the sole rebuildable cache; never sync the private profile or writer identity.

Each event has exactly `v`, `space`, `writer`, positive contiguous `seq`, hybrid `clock` (`wallMs`, `logical`), `entity`, `type`, `data`. Counters fit the exactly representable JSON integer range. Total replay order is `(clock.wallMs, clock.logical, writer, seq)`. Every writer clock strictly increases lexicographically. HLC approximates concurrent human recency using wall time while preserving observed causality; it does not establish true recency between clocks that disagree. Unknown active fields/types/versions fail explicitly. Complete records are bounded to 1 MiB.

| Event | Payload |
| --- | --- |
| `user.created` | name |
| `task.created` | title, description, assignee; optional schedule, tags, import |
| `task.edited` | changed title/description/schedule; optional observed tagChanges |
| `task.tagsChanged` | add tag strings, remove observed add tokens |
| `task.moved` | before task ID, or null for end |
| `task.completed` | optional completedAt ISO date/time; optional complete successor snapshot |
| `task.completionUndone` | completion event ID |
| `import.document` | immutable validated Markdown source map, described below |

Creation is unique. Missing remote dependencies remain recorded and are revalidated when they arrive. Local commands require an existing task/user and valid known references before append. Users are attribution choices, not authentication.

## Hybrid clock and skew admission

This restores the original design's wall-time-aware ordering intent using explicit HLC components rather than its nanosecond scalar. On a command after reconciliation, `wallMs = max(nowMs, maxSeen.wallMs)`; logical is zero if wall time advances, otherwise `maxSeen.logical + 1`. Large same-millisecond imports consume logical increments, not future milliseconds. Both components are bounded nonnegative JSON-safe integers. Exhaustion fails explicitly. Injected clocks make ordering/skew tests deterministic.

An unseen older offline edit with a large logical counter cannot defeat a later physical timestamp merely because of more unrelated writes. Writes after observing an event still sort after it even through a small clock rollback. The stored timestamp and replay comparator never change with ingestion time, current time or cache rebuild. Occurrence dates and completion civil days remain separate domain data.

Admission allows event physical time up to five minutes ahead of this device. A farther-future batch is not checkpointed or materialized; canonical bytes and the previous cache are preserved, and commands fail with a clock-recovery error. The gate also checks the already accepted maximum before local writes, stopping propagation after a larger local clock rollback. An already open screen can retain its previous rows; startup currently shows the recovery error rather than opening the cached view, while retaining that cache on disk. Retry can admit the same unchanged bytes when the discrepancy falls within tolerance. No timestamp clamping, ignored records or canonical rewrite is allowed.

This deliberately trades write availability for containing bad forward-clock propagation. A device cannot detect its own incorrect forward clock without another reference. Correcting that device's clock does not alter an already written far-future record: such history may require an explicit reviewed recovery into a fresh space rather than waiting. No automatic repair is implemented. A wrong receiving clock can also trigger the gate. HLC improves typical conflict ordering; concurrent edits within the clock uncertainty window remain deterministically resolved, not provably ordered by human intent.

The unpublished v2 scalar draft is not accepted as hybrid: scalar `clock` fields fail explicitly, and SQLite cache format 3 rejects older cache layouts. Published v1 canonical folders remain untouched and unsupported by this prerelease.

## Fields, dates and tags

Title and description use independent last-writer-wins registers. Schedule is one atomic register: `startDate`, `scheduledDate`, `dueDate`, `startTime`, `scheduledTime`, `dueTime`, `timeZone`, `recurrence`. Dates are strict civil YYYY-MM-DD values; time is HH:mm and requires its corresponding date. Start cannot be later than due; a date-only due date includes the whole civil day. Null zone means floating local time; named zones must exist in the pinned timezone database. No absent date is invented. Recurrence date arithmetic is separate from resolving a wall time into an instant.

Tags use observed-remove membership. Each addition has a token `<event-id>:<index>`; edits remove only tokens observed when the form opened, preserving unseen concurrent same-name additions. Tags retain exact case/spelling and display deterministically sorted. A single edit event commits text, schedule and tag changes together. Resolved removal references must identify an earlier addition for the same task and valid index; delayed references are checked on arrival, including prospective local appends.

## Manual order and recurrence

Creation order initializes one shared task sequence. Relative moves replay in total event order, remove the moved task and insert it before the anchor (or at the end). Missing remote anchors defer their effect; known non-task anchors fail. Local moves require a known task anchor. Cyclic/concurrent move intentions therefore produce a deterministic order without fractional-rank exhaustion or replacing the entire sequence.

Completing a repeating task appends **one** completion event containing the full next-occurrence snapshot (title, description, assignee, tags, schedule). The successor ID is UUIDv5(parent occurrence ID, `successor`). Replay materializes it without writing canonical events. Concurrent completions select the earliest total-order seed for that one successor; later edits/completions of the successor remain independent. Initial successor placement is immediately before its completed predecessor, before replaying explicit moves.

Derived initial tag tokens are UUIDv5(successor ID, `tag:<exact tag>`), followed by `:1:0`. They are stable across competing seed snapshots, so late seed selection cannot resurrect observed removed tags. Validation resolves them against completion snapshots and checks causal clock order.

Reopening history retracts only observed completion IDs. **It always retains the successor, including its work; it does not cancel the next occurrence.** Recompletion reuses that same successor identity. This also applies to transient Undo; the UI must disclose this behavior. Imported completed recurrence rows are historical completions without generated successor snapshots or guessed series links.

Completion accepts an explicitly captured instant and computes its civil day from the freshly reconciled task zone inside the serialized command. Tests/imports may supply an explicit day instead. Replay never reads the clock. The recurrence engine handles the observed 37 rule forms; configured scheduled-date removal and calendar/completion anchors are documented in the parity decision.

## Migration provenance

`import.document` stores `documentId` (matching entity), `formatVersion: 1`, `encoding: utf-8`, BOM flag, and ordered source-line maps. Literal spans preserve formatting/non-task lines; task slots link semantic title, completion, tags, dates and recurrence to task IDs. This is a closed, validated nested schema, not executable instructions or a raw-file-only round-trip shortcut. Imported task creation references `{documentId, line}`; known document/line references must match. The external tool checks semantic equality independently before reporting byte-exact reconstruction. Later app edits may invalidate exact original-source reconstruction; they must be reported rather than hidden by returning archived literals.

## Durability and recovery

Commands and ingestion share one queue. Durable canonical append is the commit point. Events, affected materialized views and stream checkpoints commit in one SQLite transaction. A failed cache update or process interruption after append is recoverable by ingestion; no second authoritative successor record is needed. Untouched desktop logs are stamp-cached and skip parsing/projection. Android scans revalidate because provider metadata can be unreliable. Derived seed lookup is indexed; only affected entities are projected on ingestion. Shared sequence positions are cached transactionally after order-affecting ingestion; ordinary row reads and untouched startup do not replay move history.

Prefix hashes detect rewrites of committed history when file metadata changes. Incomplete remote tails retry; owned incomplete tails, invalid full records, unsupported formats, missing known logs, conflict copies and changed space identity stop writes without discarding history. Keep canonical files and writer identity when rebuilding only SQLite/WAL/SHM. Never rebuild to conceal missing history. See [recovery](recovery.md).

Store shutdown rejects new commands, drains accepted operations, then closes SQLite and releases the writer lock. Capture retries retain task IDs within the running UI; this is not a durable draft queue across process termination. Undo actions retain their originating store and are discarded when switching folders.
