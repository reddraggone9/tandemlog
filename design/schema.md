# Task protocol v3

Implementation: `lib/domain/event.dart`, `lib/domain/event_chain.dart`, `lib/storage/task_store.dart`. The first stable 2026.10.0 format explicitly rejects prerelease-only v1/v2 canonical manifests and events, preserving them without rewriting or deleting data. Existing v3 folders remain supported unchanged; backward readability and meaning are durable from this stable boundary. The [chain decision](decisions/0007-canonical-history-integrity.md) specifies exact encoding and integrity limits.

## Data space and files

A selected canonical folder contains `tandemlog-space.json` (`v: 3`, UUID `id`) and `<writer UUID>.jsonl`. Initialize once and transport the manifest to joining devices. SQLite is the sole rebuildable cache; never sync the private profile or writer identity.

Each event has exactly `v`, `space`, `writer`, positive contiguous `seq`, `clock` (exact decimal nanosecond string), `entity`, `type`, `data`, `previousHash`, `hash`, in that canonical order. Nested payload maps sort their keys; the record hash covers the canonical UTF-8 event including its predecessor, with domain separation. The first predecessor binds the workspace and writer; later predecessors equal the previous record's hash. Exact serialization and golden hashes are specified in [ADR 0007](decisions/0007-canonical-history-integrity.md#wire-contract). Counters fit the exactly representable JSON integer range. Total replay order is `(numeric clock, writer, seq)`; chain order is per-writer sequence. Every writer clock strictly increases numerically. The clock approximates concurrent human recency using wall time while preserving observed causality; it does not establish true recency between clocks that disagree. Unknown active fields/types/versions fail explicitly. Complete records are bounded to 1 MiB.

| Event | Payload |
| --- | --- |
| `user.created` | name |
| `task.created` | title, description, assignee; optional schedule, tags |
| `task.edited` | changed title/description/schedule/assignee; optional observed tagChanges |
| `task.deleted` | empty payload; task tombstone, with its contribution retractable through session Undo |
| `task.moved` | before task ID, or null for end |
| `task.completed` | optional completedAt ISO date/time; optional complete successor snapshot |
| `task.completionUndone` | completion event ID |
| `task.operationUndone` | earlier reversible operation event ID; recurring completion with a successor excluded |
| `task.recurringCompletionUndone` | earlier recurring completion event ID; conditional untouched-successor suppression |

Identifiers must be canonical lowercase RFC UUIDs accepted by the same validator used for UUIDv5 successor derivation; malformed shapes/variants fail before append. Creation is unique. Missing remote dependencies remain recorded and are revalidated when they arrive. Local commands require an existing task/user and valid known references before append. Users are attribution choices, not authentication.

## Wall-time-aware nanosecond clock

The user confirmed the [original design](archive/storage-and-sync.md): on a command after reconciliation, `clock = max(now_ns, max_seen_clock + 1)`. This supersedes the temporary pure-Lamport and HLC proposals. `now_ns` is computed exactly as `BigInt.from(DateTime.now().microsecondsSinceEpoch) * 1000`: microsecond wall-clock resolution represented in nanosecond units, with borrowed nanoseconds when necessary.

Canonical JSON encodes the clock as a decimal string without sign, exponent, whitespace or leading zeros (except `"0"`). Domain arithmetic/comparison uses BigInt. Values are bounded to nonnegative signed-64-bit range, up to `9223372036854775807`. SQLite stores the validated value as a native exact 64-bit integer; conversion happens only after range validation. View sort keys use 19-digit zero padding. No JSON numeric conversion is involved. Unknown draft numeric/tuple encodings fail explicitly rather than being reinterpreted.

An older offline edit with a high sequence count cannot dominate a later wall-time edit merely because it performed more unrelated operations. Equal or backward wall time borrows one nanosecond beyond the highest observed clock. The canonical timestamp and replay comparison never change with arrival time or cache rebuild. Occurrence dates and completion civil days remain separate domain data.

If the maximum event clock is more than five minutes ahead of this device, `clockWarning` supplies a nonblocking diagnostic. **Clock skew never blocks opening, ingestion or writes.** Future-dated canonical records are imported unchanged; subsequent writes advance beyond them. The warning is recomputed on refresh and after writes and disappears once the wall clock is sufficiently close again. The UI presents it separately from actionable errors and leaves ordinary task controls enabled.

A wrong forward clock can therefore influence later conflict ordering, including other devices that observe it. This availability-first tradeoff is explicitly accepted; recovery tooling is deferred. No timestamp clamping, silent record omission, background repair or history rewrite is implemented. Malformed values, unsupported formats and signed-64-bit exhaustion still fail explicitly; these are format/range errors, not skew admission gates.

The unpublished scalar-number and HLC tuple drafts are not accepted by the final decimal-string wire contract. The current SQLite cache is format 13; its replay/in-place upgrade rules are described below. Unknown future layouts remain explicit errors. Current closed-schema validation still rejects source-map rehearsal events, invalid UUIDs and opaque reserved schedule tags in canonical history; a cache rebuild never makes incompatible logs acceptable. Published v1/v2 folders remain untouched and unsupported by this prerelease. Earlier RC history below explains operation meanings; v3 changes their envelope integrity rather than reinterpreting those meanings.

## Fields, dates and tags

RC4 adds `task.deleted` and assignee edits within protocol v2; every participating app must be updated before using them because older readers reject unknown active types/fields. An active tombstone hides its task regardless of later edit/completion delivery; the canonical record and independent successor remain. Assignee uses an independent last-writer-wins register and local commands require an existing user. Bulk patches merge only explicit fields into each task's full validated schedule, use observed tag deltas and prevalidate the whole selection. Per-task appends are independently durable: report partial progress and reconcile uncertain acknowledgement failures before retry. No cache-layout change or history rewrite is needed.

Title and description use independent last-writer-wins registers. Schedule is one atomic register: `startDate`, `scheduledDate`, `dueDate`, `startTime`, `scheduledTime`, `dueTime`, `timeZone`, `recurrence`, and optional integer `dueMinDays`/`dueMaxDays`. Bounds are integer calendar-day offsets from 0 through 365000 (a finite supported horizon) with minimum no greater than maximum; they affect only derived sort/group dates and are inherited by recurring successors. Dates are strict civil YYYY-MM-DD values; time is HH:mm and requires its corresponding date. Start cannot be later than due; a date-only due date includes the whole civil day. Null zone means floating local time; named zones must exist in the pinned timezone database. No absent date is invented. Recurrence date arithmetic is separate from resolving a wall time into an instant.

Tags use observed-remove membership. Each addition has a token `<event-id>:<index>`; edits remove only tokens observed when the form opened, preserving unseen concurrent same-name additions. Tags retain exact case/spelling and display deterministically sorted. Reserved lowercase schedule-tag spellings are rejected in app history; use functional schedule fields instead. The private importer maps these semantic tags before creating events. A single edit event commits text, schedule and tag changes together. Resolved removal references must identify an earlier addition for the same task and valid index; delayed references are checked on arrival, including prospective local appends.

## Manual order and recurrence

Creation order initializes one shared task sequence. Relative moves replay in total event order, remove the moved task and insert it before the anchor (or at the end). Missing remote anchors defer their effect; known non-task anchors fail. Local moves require a known task anchor. Cyclic/concurrent move intentions therefore produce a deterministic order without fractional-rank exhaustion or replacing the entire sequence.

Completing a repeating task appends **one** completion event containing the full next-occurrence snapshot (title, description, assignee, tags, schedule). The successor ID is UUIDv5(parent occurrence ID, `successor`). Replay materializes it without writing canonical events. Concurrent completions select the earliest total-order seed for that one successor; later edits/completions of the successor remain independent. Creation, selected-seed completion and move actions replay interleaved in total event order. At the selected completion, the successor is inserted immediately before its predecessor’s current position. Later moves of either occurrence remain independent; later duplicate completions do not reposition the existing successor.

Derived initial tag tokens are UUIDv5(successor ID, `tag:<exact tag>`), followed by `:1:0`. They are stable across competing seed snapshots, so late seed selection cannot resurrect observed removed tags. Validation resolves them against completion snapshots and checks causal clock order.

Reopening history uses `task.completionUndone` to retract only observed completion IDs. **It always retains the successor, including its work; it does not cancel the next occurrence.** Recompletion reuses that same successor identity. True Undo of a recurring completion uses `task.recurringCompletionUndone`; generic `task.operationUndone` cannot target a completion containing a successor in v3. Imported completed recurrence rows are historical completions without generated successor snapshots or guessed series links.

Completion accepts an explicitly captured instant and computes its civil day from the freshly reconciled task zone inside the serialized command. Tests/imports may supply an explicit day instead. Replay never reads the clock. The recurrence engine handles the observed 37 rule forms; configured scheduled-date removal and calendar/completion anchors are documented in the parity decision.

## External migration

The data-only importer emits ordinary user/task events. There is no import.document event, task import reference, source template, original-text snapshot or formatting sidecar in the app protocol. Superseded private rehearsal histories containing those removed fields fail explicit closed-schema validation; no live conversion is needed because none was authorized or performed. Source hashes, private diffs and import reports remain external audit outputs. Private one-off migration tooling lives outside this repository and is not shipped or supported as an application feature. Generic domain validation, ordering and persistence remain app responsibilities.

## Unreleased required text extension

The authorized branch adds `task.createdWithText`, `text.baselineInitialized`,
`task.textEdited` and `task.textEditUndone` within the unchanged v3 envelope.
These are required meanings: older readers fail explicitly instead of ignoring
the packets or treating them as scalar edits. Creation seeds and field context,
exact shared baseline frontiers, actor admission, receipt-gated native Save and
compensation are specified in [ADR 0010](decisions/0010-collaborative-text-adoption.md).
Original v3 scalar records, canonical hashes, clocks and historical Undo retain
their original meaning. Frozen stable histories remain unchanged.

Branch cache 14 adds verified native field checkpoints, actor claims and pending
receipt indexing to SQLite. Existing current cache 13 upgrades additively without
full-log replay; older supported cache rebuild and integrity guards still apply.
Installation-private exact text intent files survive disposable cache loss and
are retired only after matching canonical acknowledgement. They are never shared
or treated as accepted task state. Missing native engine support fails explicitly
if required native records are present. The extension is not released; native
recurring successor semantics and platform acceptance remain gates.

## Durability and recovery

Commands and ingestion share one queue. Durable canonical append is the commit point. Events, affected materialized views and stream checkpoints commit in one SQLite transaction. A failed cache update or process interruption after append is recoverable by ingestion; no second authoritative successor record is needed. Untouched desktop logs are stamp-cached and skip parsing/projection. Android scans revalidate because provider metadata can be unreliable. Derived seed lookup is indexed; only affected entities are projected on ingestion. Shared sequence positions are cached transactionally after order-affecting ingestion; the order-projection marker permits a one-time cache-only rebuild when ordering semantics change, without touching canonical history; ordinary row reads and untouched startup do not replay move history.

Fresh replay and Settings **Check data integrity** verify complete record hashes and chain continuity. The explicit check also compares retained private byte receipts. Ordinary size/seek-capable reconciliation validates only new records against its saved chain head, not the current old prefix. Unknown-size/nonseekable providers full-read. Hashes are not authentication: a fresh device cannot detect a fully recomputed chain or removed final records without a trusted head. Incomplete remote tails retry; owned incomplete tails, invalid full records, unsupported formats, missing known logs, conflict copies and changed space identity stop writes without discarding history. Keep canonical files and writer identity when rebuilding only SQLite/WAL/SHM. Never rebuild to conceal missing history. See [recovery](recovery.md).

Store shutdown rejects new commands, drains accepted operations, then closes SQLite and releases the writer lock. Capture retries retain task IDs within the running UI; this is not a durable draft queue across process termination. Undo actions retain their originating store and are discarded when switching folders or restarting.

RC5 adds `task.operationUndone` with exactly `operation: <writer UUID>:<seq>`. It targets an earlier same-entity `task.edited`, `task.moved`, `task.deleted`, `task.completed` or `task.completionUndone`; Undo itself is not retractable. Replay omits only the target contribution. Later scalar/schedule registers, independent tag tokens, completion/deletion and relative moves remain. Recurrence successor seeds remain materialized even if their completion is retracted. Missing remote targets wait for arrival, then entity/type/strict earlier-clock checks run transactionally. Update all peers before using this additive closed-schema type. [Rationale and session limits](decisions/0005-session-undo-and-toolbar.md).


## RC8 conditional recurring-completion Undo

`task.recurringCompletionUndone` has exactly `completion: <writer UUID>:<seq>` and names a strictly earlier, same-task `task.completed` containing a successor snapshot. It retracts that completion contribution and conditionally suppresses its untouched successor. It is not itself an Undo target. Known invalid targets fail before append or transactionally on ingestion; missing remote targets remain pending and are revalidated when they arrive. Plain completions and other reversible operations still use `task.operationUndone`. No old event is reinterpreted or rewritten.

An untouched successor uses the earliest total-order seed not named by this new cleanup type. If all seeds are cleanup-retracted, the identity remains internally materialized with `successorSuppressed: true` but is absent from task rows. This is a cache projection flag, never a canonical deletion event. Recompletion reuses the deterministic successor identity with the new surviving snapshot and inserts it at that selected completion's parent position.

Conservatively, any direct canonical history on the successor or any incoming relative-move anchor preserves its earliest historical seed, even when that work was subsequently undone or deleted. Such activity includes edits, tags, moves, completion and descendants. A second completion seed not cleanup-retracted independently supports the successor. Late arrival of protected activity or another supporting seed restores the successor deterministically; ordinary tombstones and independent newer work remain effective. Cleanup delivery, selected-seed changes and late anchor/activity delivery reproject the affected successor and its ordering in the same cache transaction.

Mixed Undo batches append unchanged per-record envelopes together. Exact confirmed receipts determine undone/remaining operations and retained/removed successor counts; a partial prefix does not claim tail success. One recurring cleanup record couples its completion reversal with its derived suppression, avoiding a separately durable unconditional successor deletion.

The RC8 v2 transition is historical: older peers rejected its additive cleanup type. Current v3 rejects all v2 envelopes without converting them. The historical fixture `test/fixtures/recurring_operation_undone_v2.jsonl` verifies explicit unsupported-version preservation; `test/recurring_completion_undo_test.dart` covers current cleanup, protection, recompletion, delayed references, convergence and partial retries.


## Released cache 13 and installation identity

Canonical workspace/event protocol is v3. The accepted Inbox classification is derived from existing functional task fields and surviving edits/tags, not a new event or stored `neverEdited` flag. Supported old projection caches rebuild only against supported v3 canonical logs with a private backup and existing identity/committed-history guards; caches newer than 13 remain untouched with an explicit compatible-app error. A real v2 folder is rejected before private cache migration. Supported prior caches replay v3 records after preserving a private backup and integrity guards, so retired draft meanings cannot survive a cached fast path. This never converts canonical files; warmed current caches retain incremental reads.

`streams` retains complete byte `offset`, prior-prefix `hash` and its `hash_offset`, adapter observation `stamp`, cached `range_capable`, `chain_head`, `last_seq` and `last_clock`. `stream_ranges(name,start_offset,end_offset,hash)` records exact SHA256 digests of subsequently admitted complete byte ranges. Explicit full verification requires contiguous observed-byte coverage through `offset` and compares the current bytes as well as checking the complete canonical chain. SHA digest concatenation is not used as resumable hash state. Checkpoints, newly admitted literal event lines and affected projections commit together; receipts compare exact admitted raw bytes rather than reserialized JSON. Ordinary cache reopen and size/seek-capable reconciliation skip historical bytes. See [ADR 0007](decisions/0007-canonical-history-integrity.md).

Production stores receive the installation writer from settings under the profile-wide lease; per-workspace sequence/clock and stream identity semantics remain unchanged. See [ADR 0006](decisions/0006-installation-identity-and-instance-lock.md). Low-level standalone store clients may still omit that optional argument and retain their existing local writer file.

The installation also retains a private writer guard keyed by workspace UUID and writer UUID, independent of selected path and disposable SQLite. Before append it durably prepares exact candidate sequence/hash pairs; before confirming a command it durably acknowledges the observed complete prefix. A restored backup at another path cannot reuse an already acknowledged sequence under the same installation identity. A pending interrupted append reconciles its exact contiguous prefix; missing history blocks rather than skipping sequence numbers or choosing a new writer silently.

## Stable compatibility promise

Compatibility begins with first stable 2026.10.0. Retain v3 decoders, frozen historical fixtures and the exact canonical hash preimages for every format shipped as stable. The synthetic `test/fixtures/stable-v3-2026.10.0` history freezes all supported event types, identities, clocks, field/Undo/successor meaning and order; its regression exercises both stream arrival orders, cache reopen/rebuild and new-writer extension without rewriting history. The independent `event_chain_v3.jsonl` golden retains exact Unicode/hash encoding coverage. New meanings receive new versioned admission; deterministic upcasting may change only the projection. Never rewrite old canonical bytes or recompute historical hashes as a cache upgrade. Known disposable-cache upgrades retain backup/identity/guard checks; unknown future layouts and unsupported required semantics preserve files and fail explicitly. Prerelease-only v1/v2 and removed draft fields remain explicitly unsupported. [ADR 0008](decisions/0008-calver-and-release-promotion.md) separates release naming from protocol/cache versions.
