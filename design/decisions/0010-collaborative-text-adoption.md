# Collaborative task text

Status: implementation authorized on 2026-10-04; unreleased on
`experiment/text-activation-policy`. Integrated native Linux editing checks pass;
full platform and release gates remain pending.

## Accepted behavior

Lee approved uncovered legacy whole-field text edits losing after activation
(Sentinel_17d7070781648191be317081ef30c28e). Their original records remain intact.
He approved one chosen-device shared baseline for existing fields, with the
condition that newly created upgraded tasks work offline without that setup
(Sentinel_906078ee71408191bb93f64b1b34d823).

The original v3 clock, hash chain, UUIDs, schedule/tag registers, completion and
historical Undo meanings stay unchanged. New required event types make older
readers stop explicitly; an older reader cannot quietly reinterpret native text.
No canonical history is rewritten, deleted or timestamped at reception.

## Shared basis and captured editing

An explicit `text.baselineInitialized` record names exact per-writer sequence/hash
frontiers and a digest of their original projected legacy field seeds. Verify
the complete declared prefix before accepting a legacy text Save. Users establish
this once on one device, then transport the same record/history to the others.
Independent incompatible roots are retained and block legacy text writes; there
is no first-arrival or minimum-ID election over acknowledged native work.

Upgraded captures use `task.createdWithText`: the immutable creation identifies
its own title/notes seeds. They can be created and edited offline before a legacy
baseline exists. After activation, old-style task creations that arrive outside
the baseline seed from their immutable creation; later uncovered scalar text
edits lose. Nontext effects retain their original meanings.

Each field context binds workspace, entity, title/description, canonical basis,
basis kind, pinned codec/adapter, and exact seed SHA-256. Equality of rendered
strings does not establish equality of native state. Existing private scalar
drafts are not relabeled as captured native edits or copied over received text.
Opening a verified editor captures a native private draft; received updates
change the live owner while preserving its editing value, selection/composition
and unsaved text. Save publishes the captured operations, not a whole-string
replacement of the received live value.

## Narrow native boundary

Yrs 0.28.0 provides character identities, delayed dependencies and selective Undo.
This concrete need justifies the Rust bridge exception in ADR 0001. It does not
move domain rules or SQLite into Rust. One canonical implementation lives in
`native/text_engine`; experiment wrappers include that source rather than copy it.
The typed Dart adapter owns UUID handles. One dedicated native thread owns Yrs
documents and receives owned requests; worker panic quarantines it instead of
silently respawning empty documents. The library remains loaded for process life.

Canonical field updates retain their exact native bytes and a checked actor
claim. A nonreserved JSON-safe actor is derived from context, installation writer
and immutable allocation UUID. Detect collisions and foreign struct authors;
delete-set references are not struct authors. Cancelled leases are not reused for
different content. A checkpoint contains full native state, including delayed
dependencies, and its verified context/digest/replay frontier in SQLite.

## Receipts, cache and Undo

Native Save and compensation preparation do not acknowledge a durable change.
Append an immutable canonical record, ingest and verify its exact bytes, then
commit the corresponding native operation. Failed or uncertain appends retain
the original preparation for exact retry; they do not regenerate UUIDs, clocks,
actors or opaque bytes.

SQLite remains the sole disposable task cache. Unconfirmed local canonical
records also have installation-private durable intent files outside SQLite, so
cache loss does not strand a WriterGuard reservation with only a hash. These are
recovery intents for uncertain commands, not an alternate accepted task state or
synced snapshot. Retire an intent only after its exact canonical receipt.
Installation identity, guards and locks remain separate from cache migration.

New `task.textEditUndone` records carry native compensation and reference the
original native edit. Their nontext part retracts only that original command's
effects. Native replay still includes both original and compensation packets.
Old `task.operationUndone` cannot target a native text command. Session Undo
remains process-local, clears on workspace change/restart, and needs an owned
single-operation native basis so skipping an ineffective entry cannot undo an
earlier command. Closing an editor releases its live source owners; retained
session Undo entries own separate documents and release them on eviction.
Actual-library regressions cover remote edits, exact receipt retries, cache loss
and an ineffective most-recent edit without retracting an earlier command.

## Bounds and measured limits

Application fields retain title 500 / notes 10,000 UTF-16 units. Initial
engineering caps are 1 MiB decoded operation, 8 MiB full field state, 16 MiB
serialized session payload and 64 MiB serialized retained ownership payload.
The unchanged 1 MiB canonical JSON record bound is stricter after Base64 and
envelope overhead. An additional 100,000 retained identity/work-unit admission
cap rejects oversized structure expansion before building its per-unit index.
These limits preserve original records and drafts on failure; they do not prune
history, perform compaction or guarantee unlimited future Undo. Undo itself can
need additional identities and encounter the cap.

These are serialized/structural bounds, **not a native RAM cap**. On the tested
Linux SO, a valid 1 MiB packet previously rejected in 276–326 ms with about 224
MiB additional peak RSS. The admission preflight reduced it to 2.18–3.10 ms and
2.2–2.5 MiB above the payload-ready baseline. A 1,000-edit near-full notes
session measured 11.47 ms worst edit, 3.36 ms p95, 5.10 ms worst Save and
0.049 ms worst read. These subprocess measurements do not establish Android
peak memory, UI frame latency or end-to-end startup.

## Alternatives and remaining gates

Keeping scalar LWW avoids native/bootstrap costs but loses concurrent text edits.
Independent legacy snapshot activation cannot safely pick one acknowledged root.
Rendered-string checkpoints discard identity and pending dependencies. Automatic
old-draft rebasing cannot recover character intent from full strings.

Concurrent recurring completions still need an immutable successor text basis.
The proposed union of text observed by either completion is a pending product
decision; do not silently adopt it or change old completion snapshots. No native
recurrence release proceeds while this is unresolved. Local recurring completion
of a native-text occurrence currently fails before preparation or append. This
temporary guard does not alter historical replay or old scalar completion
semantics; it must be replaced by the agreed successor contract before release.

The production controller, captured editor and session Undo are wired. The
native Linux flow covers offline creation before setup, private draft retention
during a peer update, merged Save/selective Undo, explicit legacy setup, narrow
dark 200% text, and restart persistence. Its composition/insets are injected;
it is not Android OS-IME evidence. See the [production checkpoint](../../evidence/production-text/README.md).

Before any preview: resolve successor text, adapt and run the complete existing
native workflow matrix, make real-library CI checks mandatory, verify native
Windows packaged lifecycle, rebuild all Android ABIs/page alignment, and accept
the exact signed APK on Android. Release-mode startup/resource measurements and
independent final UI/release review remain pending. Stable promotion requires
separate behavior acceptance. [Prototype evidence](../text-merge-prototype.md)
remains historical; passing it alone is not production acceptance.
