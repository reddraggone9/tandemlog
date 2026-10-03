# Task protocol v2

Implementation: `lib/domain/event.dart`, `lib/storage/task_store.dart`. This prerelease format explicitly rejects v1 canonical manifests and events. It does not rewrite or delete old canonical data. Use a new dedicated v2 folder; stable compatibility promises begin at 0.1.0.

## Data space and files

A selected canonical folder contains `tandemlog-space.json` (`v: 2`, UUID `id`) and `<writer UUID>.jsonl`. Initialize once and transport the manifest to joining devices. SQLite is the sole rebuildable cache; never sync the private profile or writer identity.

Each event has exactly `v`, `space`, `writer`, positive contiguous `seq`, `clock` (exact decimal nanosecond string), `entity`, `type`, `data`. Counters fit the exactly representable JSON integer range. Total replay order is `(numeric clock, writer, seq)`. Every writer clock strictly increases numerically. The clock approximates concurrent human recency using wall time while preserving observed causality; it does not establish true recency between clocks that disagree. Unknown active fields/types/versions fail explicitly. Complete records are bounded to 1 MiB.

| Event | Payload |
| --- | --- |
| `user.created` | name |
| `task.created` | title, description, assignee; optional schedule, tags |
| `task.edited` | changed title/description/schedule/assignee; optional observed tagChanges |
| `task.deleted` | empty payload; task tombstone, with its contribution retractable through session Undo |
| `task.tagsChanged` | add tag strings, remove observed add tokens |
| `task.moved` | before task ID, or null for end |
| `task.completed` | optional completedAt ISO date/time; optional complete successor snapshot |
| `task.completionUndone` | completion event ID |
| `task.operationUndone` | earlier reversible operation event ID |
| `task.recurringCompletionUndone` | earlier recurring completion event ID; conditional untouched-successor suppression |

Identifiers must be canonical lowercase RFC UUIDs accepted by the same validator used for UUIDv5 successor derivation; malformed shapes/variants fail before append. Creation is unique. Missing remote dependencies remain recorded and are revalidated when they arrive. Local commands require an existing task/user and valid known references before append. Users are attribution choices, not authentication.

## Wall-time-aware nanosecond clock

The user confirmed the [original design](archive/storage-and-sync.md): on a command after reconciliation, `clock = max(now_ns, max_seen_clock + 1)`. This supersedes the temporary pure-Lamport and HLC proposals. `now_ns` is computed exactly as `BigInt.from(DateTime.now().microsecondsSinceEpoch) * 1000`: microsecond wall-clock resolution represented in nanosecond units, with borrowed nanoseconds when necessary.

Canonical JSON encodes the clock as a decimal string without sign, exponent, whitespace or leading zeros (except `"0"`). Domain arithmetic/comparison uses BigInt. Values are bounded to nonnegative signed-64-bit range, up to `9223372036854775807`. SQLite stores the validated value as a native exact 64-bit integer; conversion happens only after range validation. View sort keys use 19-digit zero padding. No JSON numeric conversion is involved. Unknown draft numeric/tuple encodings fail explicitly rather than being reinterpreted.

An older offline edit with a high sequence count cannot dominate a later wall-time edit merely because it performed more unrelated operations. Equal or backward wall time borrows one nanosecond beyond the highest observed clock. The canonical timestamp and replay comparison never change with arrival time or cache rebuild. Occurrence dates and completion civil days remain separate domain data.

If the maximum event clock is more than five minutes ahead of this device, `clockWarning` supplies a nonblocking diagnostic. **Clock skew never blocks opening, ingestion or writes.** Future-dated canonical records are imported unchanged; subsequent writes advance beyond them. The warning is recomputed on refresh and after writes and disappears once the wall clock is sufficiently close again. The UI presents it separately from actionable errors and leaves ordinary task controls enabled.

A wrong forward clock can therefore influence later conflict ordering, including other devices that observe it. This availability-first tradeoff is explicitly accepted; recovery tooling is deferred. No timestamp clamping, silent record omission, background repair or history rewrite is implemented. Malformed values, unsupported formats and signed-64-bit exhaustion still fail explicitly; these are format/range errors, not skew admission gates.

The unpublished v2 scalar-number and HLC tuple drafts are not accepted by the final decimal-string wire contract. The current SQLite cache is format 11; its replay/in-place upgrade rules are described below. Unknown future layouts remain explicit errors. Current closed-schema validation still rejects source-map rehearsal events, invalid UUIDs and opaque reserved schedule tags in canonical history; a cache rebuild never makes incompatible logs acceptable. Published v1 folders remain untouched and unsupported by this prerelease.

## Fields, dates and tags

RC4 adds `task.deleted` and assignee edits within protocol v2; every participating app must be updated before using them because older readers reject unknown active types/fields. An active tombstone hides its task regardless of later edit/completion delivery; the canonical record and independent successor remain. Assignee uses an independent last-writer-wins register and local commands require an existing user. Bulk patches merge only explicit fields into each task's full validated schedule, use observed tag deltas and prevalidate the whole selection. Per-task appends are independently durable: report partial progress and reconcile uncertain acknowledgement failures before retry. No cache-layout change or history rewrite is needed.

Title and description use independent last-writer-wins registers. Schedule is one atomic register: `startDate`, `scheduledDate`, `dueDate`, `startTime`, `scheduledTime`, `dueTime`, `timeZone`, `recurrence`, and optional integer `dueMinDays`/`dueMaxDays`. Bounds are integer calendar-day offsets from 0 through 365000 (a finite supported horizon) with minimum no greater than maximum; they affect only derived sort/group dates and are inherited by recurring successors. Dates are strict civil YYYY-MM-DD values; time is HH:mm and requires its corresponding date. Start cannot be later than due; a date-only due date includes the whole civil day. Null zone means floating local time; named zones must exist in the pinned timezone database. No absent date is invented. Recurrence date arithmetic is separate from resolving a wall time into an instant.

Tags use observed-remove membership. Each addition has a token `<event-id>:<index>`; edits remove only tokens observed when the form opened, preserving unseen concurrent same-name additions. Tags retain exact case/spelling and display deterministically sorted. Reserved lowercase schedule-tag spellings are rejected in app history; use functional schedule fields instead. The private importer maps these semantic tags before creating events. A single edit event commits text, schedule and tag changes together. Resolved removal references must identify an earlier addition for the same task and valid index; delayed references are checked on arrival, including prospective local appends.

## Manual order and recurrence

Creation order initializes one shared task sequence. Relative moves replay in total event order, remove the moved task and insert it before the anchor (or at the end). Missing remote anchors defer their effect; known non-task anchors fail. Local moves require a known task anchor. Cyclic/concurrent move intentions therefore produce a deterministic order without fractional-rank exhaustion or replacing the entire sequence.

Completing a repeating task appends **one** completion event containing the full next-occurrence snapshot (title, description, assignee, tags, schedule). The successor ID is UUIDv5(parent occurrence ID, `successor`). Replay materializes it without writing canonical events. Concurrent completions select the earliest total-order seed for that one successor; later edits/completions of the successor remain independent. Creation, selected-seed completion and move actions replay interleaved in total event order. At the selected completion, the successor is inserted immediately before its predecessor’s current position. Later moves of either occurrence remain independent; later duplicate completions do not reposition the existing successor.

Derived initial tag tokens are UUIDv5(successor ID, `tag:<exact tag>`), followed by `:1:0`. They are stable across competing seed snapshots, so late seed selection cannot resurrect observed removed tags. Validation resolves them against completion snapshots and checks causal clock order.

Reopening history retracts only observed completion IDs. **It always retains the successor, including its work; it does not cancel the next occurrence.** Recompletion reuses that same successor identity. Historical `task.operationUndone` records also preserve the successor. RC8 true Undo of a recurring completion instead uses the new conditional record below; checkbox Reopen is unchanged. Imported completed recurrence rows are historical completions without generated successor snapshots or guessed series links.

Completion accepts an explicitly captured instant and computes its civil day from the freshly reconciled task zone inside the serialized command. Tests/imports may supply an explicit day instead. Replay never reads the clock. The recurrence engine handles the observed 37 rule forms; configured scheduled-date removal and calendar/completion anchors are documented in the parity decision.

## External migration

The data-only importer emits ordinary user/task events. There is no import.document event, task import reference, source template, original-text snapshot or formatting sidecar in the app protocol. Superseded private rehearsal histories containing those removed fields fail explicit closed-schema validation; no live conversion is needed because none was authorized or performed. Source hashes, private diffs and import reports remain external audit outputs. Private one-off migration tooling lives outside this repository and is not shipped or supported as an application feature. Generic domain validation, ordering and persistence remain app responsibilities.

## Durability and recovery

Commands and ingestion share one queue. Durable canonical append is the commit point. Events, affected materialized views and stream checkpoints commit in one SQLite transaction. A failed cache update or process interruption after append is recoverable by ingestion; no second authoritative successor record is needed. Untouched desktop logs are stamp-cached and skip parsing/projection. Android scans revalidate because provider metadata can be unreliable. Derived seed lookup is indexed; only affected entities are projected on ingestion. Shared sequence positions are cached transactionally after order-affecting ingestion; the order-projection marker permits a one-time cache-only rebuild when ordering semantics change, without touching canonical history; ordinary row reads and untouched startup do not replay move history.

Prefix hashes detect rewrites of committed history when file metadata changes. Incomplete remote tails retry; owned incomplete tails, invalid full records, unsupported formats, missing known logs, conflict copies and changed space identity stop writes without discarding history. Keep canonical files and writer identity when rebuilding only SQLite/WAL/SHM. Never rebuild to conceal missing history. See [recovery](recovery.md).

Store shutdown rejects new commands, drains accepted operations, then closes SQLite and releases the writer lock. Capture retries retain task IDs within the running UI; this is not a durable draft queue across process termination. Undo actions retain their originating store and are discarded when switching folders or restarting.

RC5 adds `task.operationUndone` with exactly `operation: <writer UUID>:<seq>`. It targets an earlier same-entity `task.edited`, `task.moved`, `task.deleted`, `task.completed` or `task.completionUndone`; Undo itself is not retractable. Replay omits only the target contribution. Later scalar/schedule registers, independent tag tokens, completion/deletion and relative moves remain. Recurrence successor seeds remain materialized even if their completion is retracted. Missing remote targets wait for arrival, then entity/type/strict earlier-clock checks run transactionally. Update all peers before using this additive closed-schema type. [Rationale and session limits](decisions/0005-session-undo-and-toolbar.md).


## RC8 conditional recurring-completion Undo

`task.recurringCompletionUndone` has exactly `completion: <writer UUID>:<seq>` and names a strictly earlier, same-task `task.completed` containing a successor snapshot. It retracts that completion contribution and conditionally suppresses its untouched successor. It is not itself an Undo target. Known invalid targets fail before append or transactionally on ingestion; missing remote targets remain pending and are revalidated when they arrive. Plain completions and other reversible operations still use `task.operationUndone`. No old event is reinterpreted or rewritten.

An untouched successor uses the earliest total-order seed not named by this new cleanup type. If all seeds are cleanup-retracted, the identity remains internally materialized with `successorSuppressed: true` but is absent from task rows. This is a cache projection flag, never a canonical deletion event. Recompletion reuses the deterministic successor identity with the new surviving snapshot and inserts it at that selected completion's parent position.

Conservatively, any direct canonical history on the successor or any incoming relative-move anchor preserves its earliest historical seed, even when that work was subsequently undone or deleted. Such activity includes edits, tags, moves, completion and descendants. A second completion seed not cleanup-retracted independently supports the successor. Late arrival of protected activity or another supporting seed restores the successor deterministically; ordinary tombstones and independent newer work remain effective. Cleanup delivery, selected-seed changes and late anchor/activity delivery reproject the affected successor and its ordering in the same cache transaction.

Mixed Undo batches append unchanged per-record envelopes together. Exact confirmed receipts determine undone/remaining operations and retained/removed successor counts; a partial prefix does not claim tail success. One recurring cleanup record couples its completion reversal with its derived suppression, avoiding a separately durable unconditional successor deletion.

Update **every peer before using RC8 recurring-completion Undo**: RC7 and older readers reject this additive closed-schema type. The workspace/envelope remains v2; cache 9 rebuilds caches 1–8 with a private backup and retained workspace/writer/committed-prefix guards. Older apps reject cache 9 rather than reading its projections. The historical-format fixture `test/fixtures/recurring_operation_undone_v2.jsonl` verifies legacy retention; `test/recurring_completion_undo_test.dart` covers cleanup, protection, recompletion, delayed references, convergence and partial retries.


## Unreleased cache 11 and installation identity

Canonical workspace/event protocol remains v2. The accepted Inbox classification is derived from existing functional task fields and surviving edits/tags, not a new event or stored `neverEdited` flag. Supported caches 1–9 rebuild with a private backup and existing identity/committed-history guards; caches newer than 11 remain untouched with an explicit compatible-app error. Cache 10 upgrades to 11 in one SQLite schema transaction without historical rereads.

`streams` retains complete byte `offset`, prior-prefix `hash` and its `hash_offset`, adapter observation `stamp`, and cached `range_capable`. `stream_ranges(name,start_offset,end_offset,hash)` records exact SHA256 digests of subsequently admitted complete byte ranges. Explicit full verification requires contiguous coverage through `offset` and compares the current bytes. SHA digest concatenation is not used as resumable hash state. Checkpoints, newly admitted literal event lines and affected projections commit together; receipts compare exact admitted raw bytes rather than reserialized JSON. Ordinary cache reopen and size/seek-capable reconciliation skip historical bytes. See [accepted admission policy](android-reconciliation-review.md).

Production stores receive the installation writer from settings under the profile-wide lease; per-workspace sequence/clock and stream identity semantics remain unchanged. See [ADR 0006](decisions/0006-installation-identity-and-instance-lock.md). Low-level standalone store clients may still omit that optional argument and retain their existing local writer file.
