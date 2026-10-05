# Adopted Undo patch and recurring text checkpoint

Unreleased feature branch. All data and UI evidence are synthetic; original
canonical/frozen fixture bytes and user data are unchanged.

- [470 unit/widget cases](unit-widget.txt) pass against the actual adopted Linux
  library; [analysis](analysis.txt) is clean. The [nine proof/store cases](proof-and-store.txt)
  cover the later closed-prefix distinction and delayed third-writer frontier.
- [Dependency gates](dependency-gates.md): 98 unchanged native Python cases,
  four Rust cases, 35 tooling and four notice cases. One official67-file crate,
  one approved source change, original MIT notices; no other package update.
- [Bundled GTK recurring flow](gtk-recurring.txt) passes checkbox completion,
  exactly one inherited child, child title/notes contexts, Save and receipt Undo.
  The three checkpoints were visually inspected at1200×850, Dark,100% text;
  the editor remains coherent and the resulting child stays listed after Undo.
- Adopted and actually bundled library SHA256:
  `5d0a7b1b3e0e6b906e831bed562a45f8db03a2bf4f08c80d9dc0c29a6f169153`.
  This is native Linux Debug evidence, not release performance or Android/Windows.
- Actual two-folder/store workflow plus a third withheld stream verifies early
  child Save, stable lineage, peer inheritance, private draft retention, original
  actor ownership, selective Undo, completion protection, later-parent isolation,
  warm zero canonical reads and full cache loss with identical states/frontiers.
  Missing proof blocks new capture/Save before receipt preparation without
  changing canonical files/outbox; later arrival resumes owner refresh.
- [Historical mixed initialization](legacy-mixed.txt) refuses before receipt
  preparation and preserves canonical bytes/view. No scalar/native rebasing.

## Native whole-title assertion assessment

The broader GTK workflow found a causal whole-title replacement/Undo mismatch:
`Review household supplies` → local `Local pending review` → peer-observed
`Newer synced review` → local Undo displays
`Review household suppliesNewer synced`. The [diagnostic](gtk-causal-undo-failure.txt)
records real projected rows and UI. It is not an identity-commit failure: ordinary
character Undo restores our old deletions while removing original local suffix
identities reused by the peer. Independent actual-native probes establish approved character semantics:
`A → BC → DC → Undo = AD`; independent insertions give `AB → AXB → AXBY → Undo = ABY`.
Both peers converge. A new actual-store regression pins both results. The broad
flow now tests peer-owned append retention; old whole-field LWW protection stays
in historical fixtures. No algorithm/preservation guard is silently changed.
This can yield awkward prose, which the ADR explicitly discloses. The corrected
[Corrected bundled GTK aggregate](gtk-final-matrix.txt) passes all three flows.
The [final 35-case focused suite](focused-final.txt) also passes after the
affected-owner optimization; unrelated user arrivals no longer replay every
open inherited field owner.

## Windows checkout correction

Hosted run37253307957 stopped before Windows tests with
`Text engine packaging failed: Unapproved Yrs vendor inventory hash`. A real Git
checkout with `core.autocrlf=true` reproduces the same failure when the vendor
attribute is absent. The exact-byte `.gitattributes` rule fixes that checkout
while retaining all67 strict source hashes. The regression also preserves this
negative control; [all36 tooling cases pass](windows-checkout-tooling.txt).
The source inventory, patch and native algorithm are unchanged. A fresh complete
hosted run is required; the earlier partial run is not platform acceptance.

## Desktop demonstration

A separate paced [actual GTK demonstration run](gtk-demonstration.txt) passes
the same completion → child edit → confirmed Save → Undo workflow with readable
synthetic content. The inspected21.6-second,1200×850 Dark/100% recording has a
visible pointer and is delivered in Library as
`libfile_5eae142fd5fc81919f99b5d66c4c467e`. The video is native Linux Debug, not
Android, a sync-provider demonstration or release startup measurement.

Hosted full platform checks, exact signed Android runtime, long-history costs
and release acceptance remain pending. There is no new publication. The historical
isolated proposal logs elsewhere remain unchanged; current accepted ADR0010
supersedes their former pending decision status.
