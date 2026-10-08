# Integrated queued fixes — native acceptance handoff

Exact application/test source: `8613c84245632242b36e6912a55556337f55b40b`, branch
`preview/checklists-queued-fixes`. CI run
[37744992534](https://github.com/reddraggone9/tandemlog/actions/runs/37744992534)
binds to that SHA. This composes reviewed rank `064cac1`, bulk Apply semantics
`9d5a5aa` and field spacing `3b03e62` onto checklist candidate `eb68b46`.

The preserved checklist candidate is unchanged. Tag-entry trials `5dbfbf6` and
Kotlin/AGP/Gradle audit `acdbd4f` are separate; no autocomplete choice or dependency
update is included. App release version remains2026.10.2-rc.3+45. This identifies
an internal exact-source acceptance candidate, not a new published release.

Independent composition review confirms main/domain/store match the accepted
rank source, picker matches field spacing, TaskEditor combines the reviewed
semantic labels and spacing gap, and every native registration appears once.
Existing assertions, checklist lifetimes, native dependencies and released v3
fixtures remain unchanged. Full599 Flutter tests,37 tooling tests, analysis and
143-file format checks pass. The full aggregate native result and hosted CI
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
```

The first two provide9 checklist flows; the additional entrypoints provide4 Inbox,
2 bulk and3 field-spacing flows. Every app/profile/folder is fresh and synthetic.
All screenshot/recording/pointer subprocesses return early on Windows; these
commands use Flutter's app test runner, not shell mouse/keyboard control or CUA.
Leave optional Linux capture variables unset. Required x64 Windows/MSVC, pinned
Flutter, Python3.11+, Rust1.99.0 and locked/offline Cargo inputs remain prerequisites.

Record source/host/toolchains, exit codes and complete logs, plus rebuilt debug
application/native DLL hashes. Windows execution remains pending here. Passing
these tests would add source-bound native app/lifecycle evidence; it would not
establish manual visual acceptance or execution of the downloaded release payload.
Do not bypass unavailable desktop-control APIs to obtain the latter.

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
- Inspect floating Minimum days at0 against the Sort-date explanation. Compare
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
