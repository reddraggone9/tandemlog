# Collaborative task text

Status: implementation authorized on 2026-10-04; unreleased on
`experiment/text-activation-policy`. Initial native Linux editing checks pass;
an extended Undo lifecycle regression currently blocks adoption. Full platform
and release gates remain pending.

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
remains process-local, clears on workspace change/restart, and restricts each
prepared native Undo to its named acknowledged operation. A shared field/session
owner retains Yrs's local identity and redone links across successive Saves and
Undo receipts. Independent per-operation documents lost those links when later
Undo restored an earlier insertion, producing duplicated text on a second Undo.
The temporary preparation manager contains only the requested stack item; Yrs
cannot skip an ineffective item and consume an earlier command. Closing an editor
releases its live source owners. Retained Undo entries reference separate session
owners, released when their last history reference is evicted.
Actual-library regressions cover remote edits, exact receipt retries, cache loss
and an ineffective most-recent edit without retracting an earlier command.

The extended lifecycle found another limitation in the current snapshot wrapper:
recreating a session reruns Yrs Undo. Yrs 0.28.0 visits a HashSet of items to
restore, assigning new local character IDs in that iteration order. Recreating
the same acknowledged Undo can consequently fail the exact native-state check.
No check is weakened and no canonical packet is regenerated to hide this.
The [isolated patch proposal](../../evidence/production-text/undo/README.md)
sorts that traversal by immutable `(client, clock)` IDs and passes the observed
regression plus the frozen native corpus. It is not adopted: maintaining a
patch to a core dependency versus redesigning snapshot ownership needs Lee's
decision. This evidence establishes the tested path, not general determinism of
all Yrs features.

A confirmed Save whose local Undo registration has not finished must not be
silently absent from older Undo preparation. Matching affected fields now block
preparation without appending compensation or changing saved task history.
Exact registration retry remains possible with its retained open capture;
restart clears session Undo if that capture has already closed.

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

The current source also cross-builds for arm64-v8a, x86_64 and armeabi-v7a with
NDK 28.2/API 24; required exports and 16 KiB ELF segment alignment pass. A local
debug APK also passes three-ABI payload/ZIP alignment and full-notices checks.
It is packaging evidence from the earlier branch snapshot, not the final signed
candidate or an Android execution result.

Before any preview: resolve successor text, pass the complete existing native
workflow matrix and the now-mandatory real-library hosted CI, verify native
Windows packaged lifecycle, and accept the exact signed APK on Android.
Release-mode startup samples are recorded in the production checkpoint with
their exact source and methodological limits; final UI/release review remains
pending. Stable promotion requires
separate behavior acceptance. [Prototype evidence](../text-merge-prototype.md)
remains historical; passing it alone is not production acceptance.

### Pending recurring-text choice: concrete impact

Two offline devices start with parent title `AB`. A edits to `AXB` and completes;
B edits to `ABY` and completes. A can already edit the deterministic successor
before B's completion arrives. The current historical earliest-completion
snapshot selection can then change the successor's seed, invalidating native
character identities. The temporary preappend guard prevents that unsafe case.

Recommended, not accepted: the new native completion contract contributes exactly
its observed parent text state; the child combines states observed by either
completion and keeps its own later edits. Subsequent parent edits do not flow
into the child automatically. Child field context must be immutable parent
lineage plus deterministic successor identity, with verified inheritance grants
for parent actors. Missing canonical proof stays pending. Nontext selection,
recurrence timing and conservative protection of successor work after Undo keep
the existing behavior. One immutable selected snapshot is an alternative, but
requires a shared selection gate or explicitly excluding offline contributions.
Old scalar completion payloads and accepted v3 fixtures retain their meaning.

This choice is Lee's product decision, not implicit approval of the recommended
contract. Native Windows/Android packaging and workflow work can proceed without
it. Startup checkpoint and exact limitations are recorded in the linked evidence.

### Decision brief — 2026-10-05, not accepted

There are two separate decisions. Neither is authorization to adopt the patch,
alter recurring completion, or publish the collaborative-text branch. Build45
publication is a separate parent/local task. The checklist prototype remains
paused; resumption needs a fresh quota check.

**1. Recommend the narrowly pinned restoration-order patch.** It affects our
exact Yrs **0.28.0** dependency, upstream source
`23b7f5693bbf9e7d26340c521ee8647f79bdfba2`. This investigation establishes that
version/path, not the affected range of other versions. The
[minimal diff](../../evidence/production-text/undo/proposed-deterministic-undo.patch)
collects the existing restoration set, sorts by immutable `(client, clock)`, and
visits that order. The original set remains available for recursive membership
checks. This is needed by **our current reconstruction design**; it is not a
general requirement for syncing Yrs updates or proof of an upstream correctness
bug. Byte-identical ownership replay is our application assumption, not an
established upstream guarantee.

The wrapper records exact Save and Undo packets in canonical events already.
However, its process-local `ReplayStep::UndoOperation` records an instruction to
run Undo again. `Replica::recreate()` executes that instruction to reconstruct
the private native ownership graph. The unordered restoration loop can assign
fresh identities differently; our exact-state check then rejects the candidate.
The observed failure is `session Undo replay differs from live state`, including
a compensation that was already durably acknowledged. The check remains strict.

The isolated patch passes 454 unit/widget, 50 actual application/FFI ownership,
98 unchanged frozen native and 4 Rust cases. The
[receipt and independent review](../../evidence/production-text/undo/README.md)
pin official source, patch and binary hashes. This establishes the tested
repeated-owner path; it is not a general proof of deterministic Yrs replay.
The patched library has not undergone actual GTK/Windows/Android application
acceptance. Current repository builds still use the unpatched dependency.

Maintenance means retaining one exact, reviewed local patch and its MIT notice,
reviewing/rebasing it for each proposed Yrs update, and keeping the frozen
identity/lifecycle regressions mandatory on all targets. Do not stay on an old
dependency indefinitely to avoid that review. Prefer an upstream-supported fix
or an ownership API that lets us remove the patch. No upstream message or PR has
been sent. The change adds no dependency, IO, permissions or unsafe block; it
does add a temporary `Vec` and an `O(k log k)` sort of restoration items. Existing
admission limits remain, but patched platform performance/RAM is not yet measured.
This is a reliability repair, not a security-vulnerability fix or a wider security
audit of Yrs.

**Exact packets versus private ownership.** Durable materialization and cache
rebuild apply the recorded packets as remote updates. They do not regenerate
compensations. Ordinary unsaved-draft Cancel disposes its private document;
editor reopening restores a verified checkpoint; process restart clears session
Undo. None needs replay of a prior local Undo. Ordinary scalar completion Reopen
also does not generate native compensation.

The fragile reconstruction occurs in session-owner mutations after local Undo:
`Engine::command` snapshots affected owners, `Replica::snapshot` also reconstructs
prepared candidates, preparation reconstructs the owner, and commit reconstructs
the prepared candidate. Remote arrival and cancellation of a prepared Undo pass
through that machinery too. Moving the actual prepared document only at commit
would fix one of those sites, not all of them.

Saving more operation bytes alone cannot replace this machinery. Yrs's
[private `Item.redone` links and item encoding](https://github.com/y-crdt/y-crdt/blob/23b7f5693bbf9e7d26340c521ee8647f79bdfba2/yrs/src/block.rs)
show that the links are not in v1 update/checkpoint bytes. Undo stack entries
are separately cloneable, but restoring those entries plus the content packets
does not restore the links needed by subsequent selective Undo. Exact content
restore is established; exact private ownership restore from only those bytes
is not. No canonical bytes need to be rewritten to fix this local problem.

**Best ownership alternative:** retain actual native ownership documents, validate
before mutation, and transfer the exact prepared document on receipt instead of
re-executing Undo. Ideally upstream would expose an identity-preserving deep
clone of the document and ownership graph. With the pinned public API, a complete
clone-free design must still prove cancellation, replenishing a speculative
owner, queued remote arrivals, two-field Save, and budget rejection without
consuming Undo or changing acknowledged state. Redo is not an exact rollback;
a finite pool of mirrors is not an unlimited cancellation solution. This larger
alternative is currently unproven, independently reviewed as such. I recommend
the bounded patch rather than treating that alternative as a ready replacement.

**2. Recommend one successor merging the text observed by completing devices.**
For a character-level example, both devices start with parent title `AB`:

- Offline A inserts `X`, sees `AXB`, and completes the occurrence.
- Offline B appends `Y`, sees `ABY`, and completes the same occurrence.
- A has already prefixed the single next occurrence with `Next: `.
- After sync the recommended next title is `Next: AXBY`: merge the observed
  native operations, not concatenate two whole title strings. Both devices
  converge to the same one successor. Notes follow the same rule.

Editing the old occurrence *after* completing it would not keep editing its
child. Only text observed in a completion's declared canonical frontier enters
that child's initial lineage, plus the child's own subsequent edits. Concurrent
replacement of the same words can still yield awkward merged prose; this rule
preserves character edits, not inferred human intent.

Recommended Undo consequence for this new contract: completing an occurrence
does not own the parent's independent text edits. An inherited text contribution
is not silently unmerged when that completion is later undone. Existing
completion retraction governs whether the child is needed: all creation
proposals undone can hide an untouched child; independent child work or an anchor
keeps it. Another surviving completion keeps the one child. Reopening historical
completion retains the child. This is a proposed native-text rule; old scalar
snapshot selection and accepted v3 fixtures keep their original meaning.

The alternative is **one explicitly selected completion snapshot**. That avoids
merging competing descriptions, but safe offline child editing needs an agreed
initialization before edits refer to its character identities. First arrival
cannot select it globally, and the earliest ordered completion is not final
while an offline completion can still arrive. A shared selection step therefore
delays next-occurrence editing on offline devices, or deliberately excludes their
competing inherited text. One child per completing device would create duplicate
occurrences and is not recommended.

The failure of late scalar seed selection to provide an immutable native basis
is established by current source/guards. The union's proposed behavior is **not
implemented or tested**. It needs immutable parent/child context, canonical
frontier proof and inherited-actor grants; the completing writer cannot claim
authorship of a peer's characters. Missing proof stays pending. Before adopting
it, test reordered/duplicate completions, early child edits, parent edits after
completion, late Undo/protection, inherited deletion and missing dependencies.
Nontext schedule/tag/assignee ordering remains under the existing contract.
