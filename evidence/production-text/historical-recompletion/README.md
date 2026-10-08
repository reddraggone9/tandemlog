# Historical recompletion implementation checkpoint

Lee's accepted preservation policy now has a separate required record,
`task.completedKeepingSuccessor`. It completes the parent while referencing the
existing child's original scalar initialization, without creating a successor
snapshot or contributing parent text. Original v3 scalar/native bytes, identities,
hashes and clocks are unchanged. Known mismatches reject before receipt preparation;
self/forward same-writer references reject even when the source is missing.

Six actual native storage cases were frozen red before implementation. They pin
offline convergence/duplicate delivery, child context/draft and scoped Undo,
completed/deleted children, exact cold reconstruction and zero-read warm reopen.
The initial deleted-child fixture incorrectly queried the visible list; its
separate corrected-red commit uses stored views and retains the original diagnostic.
Three wire/domain cases also cover source substitution, strict keys and delayed
forward-clock rejection. All nine pass.

The earlier guard test now explicitly submits `task.completedWithText` against the
independently initialized child. All its original no-receipt, unchanged canonical,
empty outbox and unchanged-view assertions remain. The high-level completion
action is covered positively by the new preservation suite and bundled GTK flow.

- All 500 unit/widget tests pass against the production Linux library.
- Analysis is clean; the focused storage/wire suite passes 36 cases.
- Actual bundled Linux Debug checkbox recompletion passes, retaining exactly the
  child and appending the required parent record. Light-theme Before/After pixels
  were inspected at 1280×720 and 100% text scale; the resulting UI says the next
  occurrence was kept. The same bundled flow passes in dark theme, with a distinct
  child title and independent notes. Its [Before](historical-recompletion-before.png)
  and [After](historical-recompletion-after.png) pixels were also inspected.
- Native Rust/Yrs source and both lockfiles are unchanged from the shared-history
  checkpoint; prior 107 native/four Rust/36 tooling gates remain applicable.
- Independent architecture/correctness/security review and Android/Windows native
  acceptance and desktop/Android demo videos remain pending. This is not release
  acceptance or stable promotion.

The focused suite, full suite, analysis and dark native-flow logs are retained
beside this file. Additional logs and captures remain under
`/workspace/recovery/historical-*`.
No live synced data was used. Existing experiments and files remain preserved.
