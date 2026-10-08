# Integrated queued fixes — native acceptance handoff

Exact final application/test source: `17ae5e5619bbd890a9778ffe39b1c94156086bb3`,
branch
`preview/checklists-queued-fixes`. CI run
[37744992534](https://github.com/reddraggone9/tandemlog/actions/runs/37744992534)
binds to earlier composition source `8613c84245632242b36e6912a55556337f55b40b`.
The subsequent commits preserve a compact-viewport test failure and make the
search workflow assert disabled controls in both responsive forms, with DPR1 and
teardown reset; application inputs are identical. They have independent review.
Final-source CI [37747198468](https://github.com/reddraggone9/tandemlog/actions/runs/37747198468)
completed successfully on Linux, Windows and Android, including the final native
aggregate and packaging checks. The [final CI receipt](queued-fixes-final-ci-receipt.json)
binds its exact source and reported archive digests. Hosted Windows debug app
flows have since passed as recorded below; installed-release/manual Windows and
Android acceptance remain pending. Read the [queued-fixes receipt](https://github.com/reddraggone9/tandemlog/blob/a960c882c06c018a1e721e7459f08dbe4d17bed3/evidence/queued-fixes/README.md)
for exact final-head CI/native bindings.
This composes reviewed rank `064cac1`, bulk Apply semantics
`9d5a5aa` and field spacing `3b03e62` onto checklist candidate `eb68b46`.

The preserved checklist candidate is unchanged. Tag-entry trials `5dbfbf6` and
Kotlin/AGP/Gradle audit `acdbd4f` are separate; no autocomplete choice or dependency
update is included. App release version remains 2026.10.2-rc.3+45. This identifies
an internal exact-source acceptance candidate, not a new published release.

Independent composition review confirms main/domain/store match the accepted
rank source, picker matches field spacing, TaskEditor combines the reviewed
semantic labels and spacing gap, and every native registration appears once.
Existing assertions, checklist lifetimes, native dependencies and released v3
fixtures remain unchanged. Full 599 Flutter tests, 37 tooling tests, analysis and
148-file final format checks pass. The full aggregate native result and hosted CI
artifacts must be read from their final receipts, not inferred from these checks.

## Supported Windows app-runner route

The [reviewed checklist route](windows-app-runner-route.md) applies, using this
exact source in a separate checkout. Run each native Flutter entrypoint separately:

```powershell
git rev-parse HEAD
flutter test integration_test/checklist_workflow_test.dart -d windows
flutter test integration_test/checklist_lifecycle_test.dart -d windows
flutter test integration_test/inbox_flow_test.dart -d windows
flutter test integration_test/bulk_apply_semantics_test.dart -d windows
flutter test integration_test/field_layout_test.dart -d windows
flutter test integration_test/task_flow_test.dart -d windows --plain-name "workspace search preserves filters drafts and completion sections"
```

The first two provide 9 checklist flows; the additional entrypoints provide 4 Inbox,
2 bulk, 3 field-spacing and 1 responsive-search flow (19 total). Every app/profile/folder is fresh and synthetic.
All screenshot/recording/pointer subprocesses return early on Windows; these
commands use Flutter's app test runner, not shell mouse/keyboard control or CUA.
Leave optional Linux capture variables unset. Required x64 Windows/MSVC, pinned
Flutter, Python 3.11+, Rust 1.99.0 and locked/offline Cargo inputs remain prerequisites.

Hosted [run 37754442151](https://github.com/reddraggone9/tandemlog/actions/runs/37754442151)
passed all 19 flows at `7b6cd65ed7db8ff8b5025abacba503e5c2f812c3`, whose application,
native and integration-test inputs match preserved candidate `a960c88`. Independent
review verified the downloaded receipt archive (14,342 bytes, SHA256
`ae3d4be3ccbe0409546e650170aebc4a9b902b98b7c6e197a09d1fee02873669`), six raw-log
hashes, exact counts, exits and startup/readiness markers. The
[immutable result and receipts](https://github.com/reddraggone9/tandemlog/blob/50f12459ab32c65715665a188ddf7a47cc281cf5/evidence/windows-app-flows-37754442151/README.md)
retain runner-measured debug payload hashes; payload binaries were not archived
for consumer rehashing, and DLL loading was source-declared without module
enumeration. This establishes hosted Windows debug app/lifecycle evidence.
Installed release-artifact execution, manual visual and native assistive-technology
acceptance remain pending. Do not bypass unavailable desktop-control APIs for them.

## Additional Android/manual affected flows

Use a fresh synthetic space, existing resource caps and approved native artifact:

- Capture two lines above two previously reordered organized tasks; save notes on
  each to leave Inbox. Their entered order stays above the older tasks after
  restart/peer import. A dated task still follows its date group. The rank fixture
  generator refuses existing output directories.
- Exercise creation-only durable prefix, foreground/background refresh and late
  original suffix where the fixture transport supports injection. Retain original
  IDs/read-only retry and truthful creation disclosure. A permanently absent
  reserved suffix remains blocked under the existing manual recovery policy.
- Verify field-specific Apply labels/checked state and activation change only the
  selected field. Distinguish Due time from Start time, occurrence fields, tags
  Add/Remove and Assignee, including enlarged text and disabled Save state.
- Inspect floating Minimum days at 0 against the Sort-date explanation. Compare
  empty/selected/wrapped Find tags query/caret gaps and clear/expand controls,
  physical IME metrics, both themes and enlarged text; retain chip/filter behavior.
- Repeat the existing checklist item Save/Cancel, completion consent/race,
  recurrence copies, independent successor/Undo, SAF/lifecycle and peer gates.

Record actual OS/device/build and visible-input Android/Windows demos where tools
permit. Linux screenshots/videos are already source-bound and independently
reviewed on the separate branches; they do not replace these platform gates.
Android cap approval, physical Android acceptance and Windows manual visual tools
remain coordinator-owned blockers. No publication, stable promotion or resource
cap change is performed by this handoff.
