# Text merge adoption choices — proposal, 2026-10-04

Status: options for Lee's review. The isolated lab is authorized; production
adoption and these new durable event meanings are not. Existing stable-v3 logs,
wall-clock causal ordering, Undo meaning, task schedules and shared folders stay
unchanged. [Prototype evidence](text-merge-prototype.md) records what was run.

| Boundary | Alternatives | Recommendation | Decision owner |
|---|---|---|---|
| Old scalar writers | Convert arriving whole strings to delete/insert; start a replacement epoch; require upgraded writers and report incompatible late work | Explicit writer upgrade before text activation. Preserve v3 projection before activation; retain and report later unupgraded scalar edits rather than silently applying or dropping them | **Lee:** coordinated upgrade and incompatible-old-writer behavior, before adoption |
| Field/seed routing | Rely on equal seed text/client IDs; bind every packet to its document and shared seed | Validate space UUID, entity UUID, field, epoch UUID, exact seed SHA256 and codec/adapter version before native decode | Engineering detail implementing an approved protocol |
| Actor allocation | Active-process counter; hash writer UUID; distinct immutable edit-batch identity with collision checking | Derive a nonreserved 53-bit actor from field/epoch/writer UUID/edit-batch UUID; persist the prepared batch and bind each actor to its origin. Detect collisions explicitly; never reuse a cancelled or retried batch for different content | Engineering detail; no new user preference |
| Checkpoint | Rendered string or ordinary diff; complete native state with a verified replay frontier | Rebuildable SQLite field checkpoint: full state including pending structs/delete sets, exact context/version/hash, source chain heads/frontier. Retain original canonical update bytes | Engineering detail; accepted cache/canonical boundaries already apply |
| Resource limits | One limit for visible text/update/history; unlimited native history; separate measured budgets | Preserve current title500/notes10000 UTF16 limits; start testing 1MiB decoded update, 8MiB field checkpoint and 64MiB active native cache with lazy loading. These are proposed test budgets, not accepted limits | Engineering tuning; **Lee** if visible limits change or history compaction/repair is proposed |

## Writer upgrade and one shared activation

For `Buy oats`, a later old client replacing the field with `Buy oats; check
cupboard` cannot express which characters it intended to delete. Converting that
string against the received merged document could erase a concurrent `and fruit`.
Choosing whole-field LWW would preserve convergence but defeat the requested
text merge. Neither should happen silently.

Recommended cutover: synchronize and stop old writers, upgrade them, then create
one immutable activation/seed per existing field from its actual final v3
projection. New readers still replay every earlier v3 event with its original
meaning. An explicit reader/writer boundary prevents an informed old client from
writing; genuinely offline stale clients may still append old-format logs. Their
late records remain untouched and produce an explicit incompatible-writer error
with a recovery choice, not receive-time rewriting or silent exclusion. Activation
records must identify the observed writer frontiers, so admission does not guess
cutover from wall-clock timestamps. Concurrent incompatible activations fail
explicitly instead of selecting a seed that loses another epoch's edits.

This requires Lee's approval of a coordinated upgrade and the recovery behavior.
A concrete recovery proposal can offer the preserved old edit for manual merge;
it must not automatically replace the CRDT document or rewrite history. No such
migration/recovery operation is implemented by the lab.

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
