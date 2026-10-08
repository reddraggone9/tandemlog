# Checklist candidate with reviewed queued fixes

Branch `preview/checklists-queued-fixes` composes checklist `eb68b46` with the
independently reviewed initial-rank, bulk Apply semantics and field-layout fixes.
Final application/test source is
`17ae5e5619bbd890a9778ffe39b1c94156086bb3`.
Tag-autocomplete trials and dependency audit remain separate. Released scalar v3
fixtures, native dependencies/protocol and application version are unchanged.

## Tests and review

- Composition source `8613c84`: 599 Flutter tests and 37 tooling tests passed;
  analysis and formatting passed. Application inputs are byte-identical at final
  source `17ae5e5`; its analysis and 148-file formatting checks also pass.
- Screenshot-enabled aggregate native execution found a test-only responsive
  cast failure: a compact Filter control is an `IconButton`, while the test
  expected a `ButtonStyleButton`. Frozen red `e575473` and complete failed-run
  log are preserved in `red/` (65 passes, one failure).
- `509e41c` asserts the correct control type at both widths, disabled state and
  unchanged query, then retains all existing business expectations. Its focused
  actual GTK workflow passed. Final `17ae5e5` pins DPR1 with teardown reset;
  the same focused actual GTK workflow passed again, including both widths.
- Independent architecture review accepted the composition; independent
  correctness review accepted both responsive test corrections and the native
  Windows handoff. No assertions were skipped and no resource caps changed.

The full screenshot-enabled native aggregate passed **66 tests** at compiled
source `509e41c` (13:47). Final `17ae5e5` changes only the reviewed DPR1/reset test
guard, with its focused native workflow separately passing; application inputs
are unchanged. Exact scope is recorded in `native-receipt.json`.
Logs in `green/` retain exact command output. The reviewed native library SHA256
is `a9b0c51f4f6cf347e321d9f47a0dec6161be161adfca44eb5be60c7db7a37e56`.
All profiles and shared folders used in these workflows are fresh and synthetic.

## CI and remaining acceptance

[Composition CI 37744992534](https://github.com/reddraggone9/tandemlog/actions/runs/37744992534)
completed successfully on Linux, Windows and Android at exact source `8613c84`.
`composition-ci-receipt.json` preserves API source/job/artifact bindings and
reported archive digests. These are not consumer archive-byte verification.

[Final-source CI 37747198468](https://github.com/reddraggone9/tandemlog/actions/runs/37747198468)
binds to `17ae5e5` and remains pending at this checkpoint. Neither successful
compilation nor Linux screenshots establish Windows/Android manual UI acceptance.

The [native acceptance handoff](https://github.com/reddraggone9/tandemlog/blob/analysis/shared-history-performance/evidence/checklists/queued-fixes-native-acceptance.md)
provides 19 isolated supported Flutter Windows app-runner flows. Windows execution,
manual visual acceptance and Android acceptance under coordinator-approved caps
remain pending. No shell Windows mouse/keyboard bypass, cap increase, publication,
stable promotion, live-data mutation or old-task/file disposition occurred.
