# Independent review of the isolated Undo proposal

Reviewer: existing `checklist_model` worker, Sol6.1, read-only.
Scope: exact official Yrs0.28.0 source copy and proposed restoration-loop change;
current wrapper source; observed repeated-owner failure and isolated test results.

Outcome: supports the isolated patch for the observed replay blocker; no blocking
defect found. This is a recommendation, not adoption or release acceptance.

- `diff -rq` reports only `yrs/src/undo.rs` changed from the pinned source.
  The external engine `lib.rs` is byte-identical to the repository engine.
- `ID` derives total order over immutable client and clock. Sorting by this key
  is independent of allocator and HashSet seed.
- `redo()` allocates the next local clock per visited item, explaining the
  differing reconstructed identities.
- Recursive parent redo retains HashSet membership checks. Other relevant
  traversals use ordered ranges or boolean scope checks. No further
  nondeterministic identity-allocation traversal was found in this path.
- Retain the exact patch/source hash, regression evidence and upstream MIT notice
  if adopted. This does not prove general determinism across all Yrs features.

Earlier adapter/store review also found the pending-operation identity bypass;
its original failing regression and checked native binding fix are retained.
It recommended partial registration coverage. The new acknowledged-but-untracked
Save regression verifies that older Undo now fails before compensation append;
exact retained registration retry succeeds without changing existing history.
