> Deferred by Lee on 2026-10-18. This investigation is not an implementation or release requirement. Optional duplicate installation names and distinct immutable writer IDs are the approved simpler route.

# Optional device names and abandoned-history adoption

Status: device naming is approved for the disposable unified-log implementation.
Adoption is a design proposal only; no adoption, retirement or old-file deletion
is implemented or authorized by this document.

## Names

Writer UUID remains immutable. An ordinary versioned writer-name event in that
writer's one app-wide chain sets or clears an optional human label. A later event
renames it; the highest admitted sequence from that writer wins. Names sync with
history. No machine hostname is collected automatically. Trim input, bound it,
reject control characters, and treat blank as unnamed. Display an unnamed device
with a short UUID suffix and retain the full UUID for unambiguous identification.
Duplicate labels are permitted and never establish identity or authority.

The events retain earlier names so future history browsing can distinguish the
current display label from a label at an earlier point. Historical authorship is
always the original immutable writer; a rename does not rewrite event payloads
or attribute another writer's events to this installation. Naming another
writer, transferring custody, and changing authorship are different operations.

## Adoption can be an ordinary operation among capable readers

A current installation can preserve a retired writer's complete sealed semantic
history by appending a versioned adoption transaction to its own chain. The
transaction contains a claim plus one position per included event, with original
semantic event IDs, writer, clock/tie-break keys, payloads, hashes, references and
native packets intact. All new positions use only the current chain's allocator
and predecessor; they do not continue the retired writer's sequence or a nested
active substream. Original authorship and current storage custody remain
distinct.

The claim binds source workspace, retired writer, exact complete source head,
record count/digest, conversion/schema version and coverage of all included
semantic records. It requires explicit confirmation that this exact writer is
permanently retired. A copied filename, a matching display name, silence on the
network or a renamed device cannot authorize it. Hash chains establish content
continuity, not authenticated ownership or proof that an unseen suffix does not
exist.

An updated peer can admit the transaction during normal refresh, with no restart
or workspace-wide writing pause. This is different from the initial v3/Food to
unified-format cutover. The initial format/reader must specify adoption semantics
before enabling such transactions; existing old binaries cannot learn a new
format without updating.

## Required invariants

- Deduplicate by source-qualified semantic identity and exact canonical content,
  not by custody writer or copied-file path. Originals plus adopted copies must
  contribute exactly once, including consumption, tombstones, Undo and native
  text. Identical copies are harmless; same ID with different canonical content
  is a global safety failure.
- Multiple current writers may simultaneously adopt the same retired source.
  They may hold redundant physical copies, but semantic results and original
  attribution remain identical. Do not pretend that independent local claims
  create a globally exclusive custodian. Any designated cleanup coordinator is
  an explicit policy, not a winner inferred from a device label.
- Stable source identity/content and the claimant's pending command receipt make
  retries repeat-safe. A crash must resume the reserved exact transaction rather
  than allocate a second adoption command. Validate every payload before either
  domain publishes; an incomplete frame publishes none of the adopted effects.
  Protect its observed physical prefix independently from its published prefix.
- Retain the source's original hash/lineage evidence. The adopter's new physical
  chain provides custody, not a replacement for original native frontier hashes.
  Peer references continue to target original semantic events.
- Existing Undo retains its original target and meaning. Custody alone does not
  make the adopter the original writer or silently grant new Undo ownership.
  Acting on a retired writer's contribution needs an explicitly defined
  versioned permission/ownership rule; never fabricate a new write as the
  retired writer. This policy must be agreed before an adoption UI offers it.
- A later record beyond the sealed retired head, a changed prefix, an unaccounted
  source identity or conflicting retirement claim stops writes for reviewed
  recovery. Never silently discard that history or automatically extend a seal.
  Capable offline peers must check their own trusted observations against the
  claim when it arrives.

## Old file removal and limits

Do not remove the old file merely because an adoption button returned success.
First require complete canonical readback, exact coverage verification,
durable publication/recovery evidence and the agreed replica/backup policy.
Missing-source checks must recognize verified adopted coverage of that same
original head; they must not erase its trusted observation.

With asynchronous sync, deletion can arrive before the adopted replacement.
A capable reader must preserve its last admitted state and wait in diagnostics
until coverage arrives. Avoiding even that temporary loss of availability needs
acknowledgements before removal. Ordinary adoption can avoid a coordinated
restart while still postponing deletion until required acknowledgements exist.
An offline peer can eventually converge from the complete adopted transaction;
it cannot be guaranteed uninterrupted access to history it has not received.

The app cannot prove the human retirement promise or discover every disconnected
copy. A source head that is complete locally may still omit a suffix known only
to another offline device. Adoption therefore needs an explicit retirement/head
assertion and a late-tail conflict policy; it cannot truthfully promise
unconditional autonomous adoption with no possibility of later reconciliation.
No production inventory or originals are inspected for this proposal.

## Practical future interaction

A future History/Devices screen could show optional label, short immutable ID,
last known head and custody/retirement status. "Adopt abandoned history" would
preview the exact source identity, coverage and any pending/conflicting records,
then ask for explicit permanent-retirement confirmation. Progress should
distinguish saved transaction, synced coverage and whether cleanup is safe.
A renamed device never substitutes for these checks.

Before enabling writes: prove original-plus-copy and simultaneous-adopter
deduplication, offline readers, late tails, missing-source/coverage transitions,
Undo/native lineage, restart at every reservation/append/acknowledgement point,
and deletion-before-adoption delivery. No destructive adoption is included in
the current implementation milestone without the user's decision on this plan.
