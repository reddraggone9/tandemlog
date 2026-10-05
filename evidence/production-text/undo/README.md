# Native Undo lifecycle checkpoint

Status: unreleased, blocked with the unpatched dependency; an isolated repair is
reviewed but not adopted. All fixtures, data and screenshots are synthetic.

## Observed defects and implemented safeguards

- Closed-editor replacements `Review → Check → Plan → Undo → Undo` produced
  `ReviewCheck`. A shared session owner preserves local redone links; each native
  preparation isolates the named stack item. Ineffective items cannot undo older
  Saves. [Original red](closed-editor-replacements-red.txt) and
  [focused green](focused-final.txt) retain literal assertions.
- The Dart adapter returned an existing preparation without checking the newly
  requested operation. Native binding is now always consulted. See
  [red](adapter-binding-red.txt) and the focused green log; same-operation retry
  preserves the original object/token/bytes, wrong-operation requests fail.
- Native Undo omitted the existing contextual newer-change status. The same
  active-later-history policy now includes native edits, excluding retractions.
  [Red](newer-status-red.txt), [green](newer-status-green.txt).
- An acknowledged Save whose Undo registration has not finished was absent from
  older owners. Affected Undo now blocks before preparing or appending a
  compensation, retaining exact canonical bytes and retry state.
  [Red](unregistered-save-red.txt), [green](unregistered-save-green.txt).

The real GTK 1200×800 Dark [restored Undo frame](session-second-undo-restored.png)
shows the original title, unsent capture draft, notes and date. The mixed-order
before/after frames retain tags, notes and the scheduled time. These internal
checks are not release media or Android evidence.

## Remaining replay defect

The expanded repeated-owner lifecycle fails with `session Undo replay differs
from live state`: [exact original failure](repeated-owners-original-failure.txt).
The real UI then accurately reports unavailable Undo registration because the
acknowledged compensation's native commit is still retained:
[diagnostic](native-registration-error.txt),
[actual frame](native-registration-warning.png). No assertions or exact-state
checks are loosened. The prior453-case green count predates this expanded
assertion and is only a historical snapshot.

Pinned Yrs0.28.0 [Undo traversal](https://github.com/y-crdt/y-crdt/blob/23b7f5693bbf9e7d26340c521ee8647f79bdfba2/yrs/src/undo.rs)
visits a HashSet of items to restore. `redo()` allocates fresh local clocks per
visited item; recreating the same history can thus assign different identities.
This is a wrapper replay assumption, not a claim that upstream promises identical
Undo packet bytes across independent reconstructions.

## Concrete isolated proposal

[Three-line patch](proposed-deterministic-undo.patch): retain the HashSet for
membership but visit items in immutable `(client, clock)` order. It changes only
that loop in an external copy of the exact official crate. No repository Cargo
manifest/lock, native dependency source, protocol, canonical history or frozen
fixture bytes have been changed for this proposal.

The [source and binary receipt](isolated-sorted-receipt.json) verifies the registry
archive against the existing lock checksum and all67 extracted official source
files. The trial library SHA256 is
`2ecac4a009bad24e4eb3e2d8dac788cc62add1120d1c28295578d481a5ac9fb1`.
It is a private engineering test library, not a user candidate or signed artifact.

- [454 unit/widget cases](isolated-sorted-full-unit.txt), including expanded
  save/Undo/close/new-owner cycles and canonical cache reopen/rebuild.
- [50 actual FFI/store/session/coordinator cases](isolated-sorted-focused.txt).
- [98 unchanged frozen native cases](isolated-sorted-python.txt).
- [Four Rust cases](isolated-sorted-rust.txt).
- [Clean analysis](analysis-final.txt);32 build/bootstrap Python cases pass.

Independent review confirmed only `yrs/src/undo.rs` differs, immutable IDs provide
an ordered key, and relevant recursive redo uses the retained set for membership.
Other allocation-relevant traversal in this path uses ordered ranges. No further
nondeterministic traversal was found here. This establishes the tested path, not
general Yrs determinism. Keep the upstream MIT notice if adopting it.

Recommendation: maintain this narrowly pinned patch with its source hash and
regressions instead of weakening receipt/state identity. Alternative: redesign
native snapshot ownership to avoid replaying Undo. Adopting a maintained core
third-party patch is a consequential maintenance choice; Lee's decision remains
pending. The patch is not part of app builds yet. Hosted CRDT CI, installed
Windows and exact signed Android acceptance consequently remain pending.
Concurrent recurring successor text also remains a separate product decision.
