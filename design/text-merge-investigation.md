# Collaborative text — investigation, not an adopted protocol

Status: Lee requested a recommendation on 2026-10-04. No CRDT engine, bridge,
canonical format or Undo change is approved by this investigation. Settings
version/date-row presentation proceeds independently; the unpublished checklist
model is held outside the repository pending this decision.

## Current fields and loss scenario

Task `title` and `description` are plain strings in creation, partial edit and
recurring-successor events. Different-field edits survive; same-field edits use
the approved wall-clock/causal ordering and whole-field last-writer selection.
For example, from `Buy oats`, one offline device adds ` and fruit`, while another
adds `; check cupboard`: one whole string wins in the visible projection. Both
original operations remain in history. This is convergence, not text merging.

`user.created.name` has no rename operation today. Proposed checklist title/notes
have stable parent/item identities and independent fields, but scalar text would
have the same limitation. Ordinary tags already use observed set operations and
are excluded from the requested text merge. Recurrence rules, dates/times, zones,
assignee IDs and local paths are structured values, not collaborative prose.
Transient capture/search/editor controllers are local drafts.

Before Save, the editor refreshes and rejects an observed changed task while
retaining its draft. That protects against known changes; offline devices cannot
observe each other. Received rows do not replace the active text buffer. Current
Undo retracts original events and reprojects; that technique cannot simply be
reused for CRDT text because later changes may depend on earlier character IDs.

## Recommendation

Merge **plain-text Markdown source**, then render it when a separate rendering
feature is requested. Links, bullets and headings do not require a rich-text mark
CRDT. Lee accepts that simultaneous edits to the same location may yield awkward
or broken Markdown; convergence does not infer human intent. Peritext's rich-text
layer adds complexity beyond today's plain-string model.

Evaluate maintained Yrs first for a narrow native interface and selective Undo;
Rust Automerge is an alternative for historical draft branches and future rich
text. Neither is an established official Dart drop-in identified by this review.
A Rust/native bridge needs a concrete cross-platform spike and approval before
adoption; no speculative bridge enters the application now.

The bounded spike must prove:

- One shared canonical seed for a historical field: independently initializing
  equal strings can create unrelated character identities and duplicate text.
- Private granular draft operations against the captured baseline/fork; Save
  publishes a batch and Cancel publishes nothing. Diffing a stale buffer against
  the current received document can incorrectly delete remote inserts.
- Exact library update bytes in explicitly versioned payloads, retained causal
  dependencies and delayed/duplicate/reordered folder delivery across cache
  checkpoints. Do not regenerate diffs on replay.
- UTF-16 offsets compatible with Dart, emoji/combining text, IME composition and
  selection anchors; Yrs offset configuration needs explicit verification.
- Appended selective-Undo compensation retaining remote edits, and independent
  successor documents for repeating tasks, with successor-work protection.
- Windows/Android/Linux native integration, bounded text limits/storage growth,
  and startup with materialized SQLite state rather than full text-history replay.

## Compatibility decision before implementation

Frozen accepted v3 histories must retain their exact bytes and meaning. New
operations can be additive without changing the JSONL envelope; base64 engine
updates are operational data, not unused source-format provenance. Existing
readers fail explicitly on unknown required semantics. Define how new readers
interpret old whole-field replacements and how mixed old/new clients behave;
if this cannot be safe, require an explicit reader/protocol upgrade rather than
silently dropping or rewriting text. History/tombstone compaction is separate
coordinated maintenance, not an incidental SQLite migration.

Sources: [Yrs](https://github.com/y-crdt/y-crdt),
[Automerge text](https://automerge.org/docs/reference/documents/text/),
[Yjs updates](https://docs.yjs.dev/api/document-updates),
[Yjs Undo](https://docs.yjs.dev/api/undo-manager). These support the independent
engine research; the field/draft/Undo audit comes from the current repository.
