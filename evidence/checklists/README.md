# One-level checklist storage component

Isolated branch: `feature/one-level-checklists`, based on shared-history native
candidate `c1823856be3f2b5aada5aa6960e7fbe9023f918f`. Neither recovered alternate
experiment was stacked into this branch. Candidate/native acceptance work and the
performance analysis branch remain separate. No live synced user data, published
release, dependency/native vendor source or frozen historical fixture was changed.

This checkpoint implements the domain, additive canonical item/copy meanings,
SQLite aggregation, native item text/receipt integration, recurrence and scoped
Undo protection. It does **not** implement the item editor UI or unfinished-item
completion warning. `expectedChecklistSnapshot` is the command guard prepared for
that UI. [ADR0011](../../design/decisions/0011-one-level-checklists.md) records accepted
product behavior and remaining gates.

## Frozen gates and independent findings

- Eleven native storage gates were frozen before implementation (`a3b730d`);
  valid failures are retained in `red/storage.txt`.
- Independent correctness review froze eighteen delivery/proof gates (`9b36fe7`),
  covering delayed parents/anchors/proofs, strict kinds, exact membership/order,
  native copies across generations, child-owned moves/checks and private drafts.
- Security froze two native gates (`d22cff8`): historical scalar-mode preservation
  without parent activation, and a949279-byte900-item/3000-head decode frame.
  Frontier validation now occurs once, retaining exact native field proof/hash
  admission; the original AOT reproduction improved7.029s→110ms. This is bounded
  record admission evidence, not an end-to-end replay performance claim.
- Independent correctness review froze exact-prefix scalar baseline controls and
  canceled task/item capture regressions (`7225e24`, `4da932f`, `def8771`, `e8b566c`).
  Protection includes durable undone/deleted child work but never future activity
  outside the immutable baseline prefix. Capture preserves canonical successor
  suppression metadata and checks containing-task availability before documents
  or actor leases open.
- Architecture review froze five local canceled-parent operation regressions and
  a merged item Save result (`42644e6`), plus a passing genuine delayed peer-work
  restoration gate (`87011d8`). Local availability guards do not reinterpret
  incoming canonical history or discard an existing exact prepared receipt.

All red evidence remains in this directory. Tests use fresh synthetic folders
and preserve them for diagnostics. Assertions and historical bytes were not
regenerated to make failures pass. The only existing test expectation changed
is the unreleased native-enabled cache version15→16; scalar cache13 remains.

## Final component validation

All550 Flutter unit/widget/storage cases pass with the actual production native
FFI library; this includes43 added checklist cases. Analysis is clean and formatting
checks133 files without changes. The37 tooling/provenance cases and all107 frozen
native admission/worker contracts pass. No Rust/native source changed. Library
SHA256: `a9b0c51f4f6cf347e321d9f47a0dec6161be161adfca44eb5be60c7db7a37e56`.
Full logs are tracked alongside this report. The native contract suite generates
an older experimental timing file as a side effect; that measurement was preserved
in `/workspace/recovery/checklist-native-contract-performance.json`, and the
pre-existing tracked research result was restored unchanged. That diagnostic is
not a checklist performance gate.

Independent architecture re-review accepts the core with no remaining must-fix;
correctness re-review passes exact-prefix/capture fixes, and security re-review
accepts bounded decoding and historical preservation. Availability/merged-row
fixes also pass the architecture review's native regression set. These are
component reviews, with UI and exact-artifact platform gates still pending.

## Remaining implementation and acceptance

Next: freeze item editor/warning workflow gates, wire explicit native item
Save/Cancel and ordering/status/deletion, resolve item private drafts before
navigation/task Undo, then warning confirmation with refreshed checklist snapshot.
Item actions are independently durable from the parent editor; avoid a misleading
multi-entity Save transaction. Keyboard and checkbox completion share one guarded
application path, with re-confirmation after incoming item/status changes.

Run and inspect the actual native Linux workflow at desktop/narrow sizes, both
themes and enlarged text; record a pointer-visible demonstration. New checklist
Windows/Android exact artifacts and affected native acceptance are still required.
The earlier c182385 candidate's partial Windows/Android results do not establish
checklist acceptance. Stable feature promotion remains Lee's decision.

Historical prefix processing still has the previously reported CPU scaling debt;
checklist validation adds bounded item work but no claim of linear replay, total
heap/RSS bounds or acceptable long-history mobile startup. Revisit against the
actual device budget before stable checklist promotion; owner/exit are recorded
in [architecture](../../design/architecture.md).
