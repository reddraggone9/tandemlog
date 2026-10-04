# Text merge adoption choices — proposal, 2026-10-04

Status: Lee approved late legacy text writes losing after activation on 2026-10-04
(Sentinel_17d7070781648191be317081ef30c28e). Bootstrap is still a proposal.
The isolated lab is authorized; production adoption and new durable meanings are not. Existing stable-v3 logs,
wall-clock causal ordering, Undo meaning, task schedules and shared folders stay
unchanged. [Prototype evidence](text-merge-prototype.md) records what was run.

| Boundary | Alternatives | Recommendation | Decision owner |
|---|---|---|---|
| Legacy scalar writes | Convert whole strings; retain manual conflicts; let uncovered writes lose after activation | **Approved:** uncovered legacy text writes lose in the visible projection; retain original records, no reconciliation UI | Lee decided; bounded Linux prototype passes, production integration pending |
| First activation | Independent snapshot seeds; common bootstrap basis; automatic rebasing | **Proposed:** one shared immutable baseline, issued once on a chosen device; derive field seeds lazily from that basis | Lee: accept one-time baseline sync before another upgraded device can Save |
| Field/seed routing | Rely on equal seed text/client IDs; bind every packet to its document and shared seed | Validate space UUID, entity UUID, field, epoch UUID, exact seed SHA256 and codec/adapter version before native decode | Engineering detail implementing an approved protocol |
| Actor allocation | Active-process counter; hash writer UUID; distinct immutable edit-batch identity with collision checking | Derive a nonreserved 53-bit actor from field/epoch/writer UUID/edit-batch UUID; persist the prepared batch and bind each actor to its origin. Detect collisions explicitly; never reuse a cancelled or retried batch for different content | Engineering detail; no new user preference |
| Checkpoint | Rendered string or ordinary diff; complete native state with a verified replay frontier | Rebuildable SQLite field checkpoint: full state including pending structs/delete sets, exact context/version/hash, source chain heads/frontier. Retain original canonical update bytes | Engineering detail; accepted cache/canonical boundaries already apply |
| Resource limits | One limit for visible text/update/history; unlimited native history; separate measured budgets | Preserve current title500/notes10000 UTF16 limits; start testing 1MiB decoded update, 8MiB field checkpoint and 64MiB active native cache with lazy loading. These are proposed test budgets, not accepted limits | Engineering tuning; **Lee** if visible limits change or history compaction/repair is proposed |

## Approved legacy policy

Once a field is activated, legacy whole-field writes outside its declared
baseline lose in the visible text projection. Preserve their original canonical
bytes, clocks, IDs and hashes. No manual reconciliation UI, converted character
operations or receipt-time rewriting is proposed. A higher scalar clock does not
make an excluded legacy value replace CRDT text. The clock remains ordinary event
metadata and is still observed according to the existing clock/warning contract.

"Outside the baseline" is defined by explicit included writer sequence/hash
frontiers, not event arrival order or wall time. An old edit can arrive before the
activation and appear temporarily under ordinary v3 rules; once the full event
set is known, it must lose identically on every replica if it was not included.
The declared historical prefix continues to use the original v3 field/retraction
projection. A late legacy Undo cannot roll back CRDT work. Non-text effects of a
legacy event keep their original meaning where safe field isolation is proven;
this permission is only about its title/notes values, not schedules, tags,
completion or canonical integrity failures.

Old readers still stop on unknown required semantics and request an upgrade.
An offline old device can write until it receives those records, but those
uncovered text values now deliberately lose. A synchronized stop/upgrade is
optional risk reduction, not mandatory. No old record or historical meaning is
rewritten, and no old history is deleted.

## First activation must share a native basis

Lee's permission for old edits to lose does **not** permit upgraded CRDT edits to
lose. Two independent activations can safely coincide only if they derive the
same field identity and native seed from the same already agreed basis. Exact
identical activations are idempotent; equal rendered strings alone do not prove
identical native state or covered history.

If A independently seeds `Buy oats` and B seeds `Buy fruit`, hashing the seeds
only produces two identities. Selecting the earliest received root diverges by
arrival order. Selecting a minimum ID converges but can hide acknowledged CRDT
updates on the other root. Importing both independent historical seeds duplicates
baseline text. The approved legacy loser policy cannot make any of these safe.
Frontiers describe what each device saw; they do not establish agreement between
those different snapshots.

### Simplest proposed bootstrap

Create **one immutable shared activation baseline on a chosen upgraded device**,
then let every upgraded device derive field seeds lazily from that same record.
The existing fields' baseline is their original v3 projection at its declared
frontiers, verified from preserved canonical history. Native state can still be
loaded lazily; independent first field edits no longer invent independent cuts.
A field identity includes space/entity/field, the shared activation reference,
codec and exact seed-state digest. New fields/recurring successors require their
own canonical creation-based initialization, retaining their distinct identities.

For the minimal implementation, **gate new title/notes editing until the common
baseline and referenced history are verified**, rather than allowing an arbitrary
scalar draft and only gating Save. Gating applies to the designated device too
while its seed is being prepared/validated. After the other upgraded device has
received the baseline, normal CRDT editing is offline-capable.

An existing unsaved draft must remain available as the user's private text with
its captured scalar base and editing value. Arrival of activation must not clear
it, copy it into the new live Y.Text, submit it automatically, or relabel it as an
edit captured against the native seed. Even receiving activation before Save
proves nothing about the base used while the draft was typed. For example, a draft
made from `Buy oats` cannot safely become a whole replacement of a live seeded
`Buy fruit and milk` without erasing other content.

A new writable CRDT editing session must explicitly capture the verified native
field/epoch/state before interpreting edits. Preserve a stranded pre-activation
draft for deliberate user handling (for example, copying its content before
opening the verified editor); never imply automatic lossless rebasing. Explicit
handling of unsaved local text is distinct from reconciliation of retained legacy
canonical edits, which Lee has declined. Do not promise survival through process
termination unless separate draft persistence is actually implemented.

This is not an all-device stop or simultaneous upgrade: the chosen device can
proceed once it has established its own valid baseline, while the old device's
excluded canonical text writes lose. A device must not acknowledge a merged-text
Save, fall back to a legacy scalar Save, or invent a replacement root while its
shared native context is missing or incompatible.

The issuer/reference must be explicitly agreed **before any CRDT Save is
acknowledged**. The current v3 manifest has only version and space UUID; it does
not already designate an activation authority. Do not invent an authority from
first arrival, the currently visible writer list or an independently editable
manifest copy. The bootstrap procedure/descriptor needs an explicit single
issuer/reference; receiving an unsupported second root must retain evidence and
fail safely, not elect it over acknowledged work. A user enabling two independent
bootstrap roots while disconnected violates this proposed single-root procedure;
handling that automatically is not proven or included in the simplest design.

This is the unavoidable tradeoff of the simple design: a newly upgraded device
cannot make its **first** CRDT Save offline without the shared baseline. Requiring
that one-time shared basis removes the need to reconcile ordinary legacy edits
or automatically merge incompatible upgraded roots. The exact authority/bootstrap
mechanism remains a design gate, not an implemented protocol claim.

### Alternatives

- Allow fully independent snapshot activation: guarantees offline first-Save
  availability, but differing roots need preserved branches and a reconciliation
  design. No silently losing upgraded branch is allowed. This is more complex.
- Use a common immutable task-creation seed everywhere: avoids seed races only if
  the subsequent v3 scalar history is also represented consistently. Late or
  missing historical replacements must not change character identities already
  edited. That conversion algorithm is unproven and larger than one common cut.
- Automatically rebase differing roots: plain full-string events do not carry
  character intent. A deterministic diff/three-way mapping may retain insertions
  but cannot generally recover intended deletion/anchors. Do not advertise that
  as equivalent to native shared-basis CRDT merging without stronger policy/tests.
- Keep LWW for now: no bootstrap dependency, with the existing visible loss of
  concurrent text edits. This remains preferable to silently losing upgraded
  edits behind an unproven migration.

Recommendation: implement the approved legacy loser policy; prefer the one
shared baseline and one-time sync limitation for a first adoption. No production
activation or recovery operation is implemented. The separately frozen
[activation-policy matrix](../experiments/yrs-spike/evidence/activation-policy-matrix.json)
extends acceptance requirements without changing earlier frozen assertions. Its
separate [four-case draft extension](../experiments/yrs-spike/evidence/activation-draft-policy-matrix.json)
adds editing gates and explicit captured-base handling. These frozen documents
retain their pre-implementation `not-run` entries. The isolated
[activation coordinator](../experiments/yrs-spike/activation_lab/README.md) now
passes all22 policy cases plus four native-preparation and four stronger recovery
cases on Linux. [Results](../experiments/yrs-spike/evidence/activation-results.json)
record actual TaskStore compatibility, native pending-state restore,
fresh-process replay, draft/controller handling and the five reproduced fixes.
This validates the bounded behavior with an explicitly configured issuer; it
does not establish production bootstrap agreement, crash-safe Undo or the new
coordinator's Windows/Android acceptance. The separate Android editor lab has
partial parent-reported runtime/OS-IME acceptance; remaining checks are pending.

## Field and actor bindings

Proposed packet context: `space_id`, `entity_id`, `field`, `epoch_id`,
`seed_sha256`, `codec`, `adapter_version`, actor-to-writer/batch bindings and exact
base64 update. Canonical record chains already protect event bytes; do not add a
second mutable source-of-truth file. Keep these bindings in canonical events and
cache their index in SQLite. Equal seed strings in a task title and notes are
still different fields. Recurrence successors get separate field identities.

Reserve actor1 only for the exact historical seed. Each captured edit batch gets
an immutable UUID before preparation; derive the candidate actor with a domain-
separated digest and persist the prepared bytes before publishing. Retries reuse
that exact batch, while a new draft gets a new UUID. Rebuild actor ownership from
canonical bindings after cache loss. The 53-bit mapping can collide: reject a
conflicting writer/batch binding before applying bytes, preserve both originals,
and report the conflict. It is not a mathematical uniqueness guarantee. A future
64-bit native-only actor option would reduce collision risk but needs a deliberate
JavaScript/Yjs interoperability decision; it is not needed for this bounded lab.

Session actor IDs and thread-local handles in the current spike are test fixtures,
not this durable allocator. Production requires owned document handles/lifetimes
and serialized calls rather than relying on incidental OS-thread placement.

## Checkpoint and budgets

Load materialized task strings for normal lists; load native state lazily for the
edited/changed field. Verify checkpoint context, codec/version, length, digest
and canonical replay frontier before reuse. Invalid disposable cache rebuilds
from untouched canonical records. Unknown required canonical semantics stop
explicitly and must not advance an ingestion checkpoint. Full native encoding
retains delayed dependencies; rendered strings and ordinary diffs do not.

Visible content, one operation and retained history need independent limits.
The lab's current65536 budget is not suitable for all three. Benchmark the
proposed separate budgets before adopting them, including long-lived paragraph
replacement, pending dependency growth and restart. Use bounded decoding work
and an eviction policy; measure native memory separately from Flutter rendering.
Budget exhaustion preserves records and the draft and explains why Save cannot
complete. It does not prune history, rebuild a smaller authoritative string,
change epochs or pretend a received record was applied. Coordinated compaction
would be a separate user-approved maintenance design.

The current title500/description10000 limits come from production event
validation. The checkpoint/pending behavior comes from pinned Yrs0.28 source
and the recorded A04 experiment. The remaining policies are our recommendations,
not claims supplied by the library or decisions already made by Lee.
