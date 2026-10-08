# Supported Windows application-test route

Prepared against checklist application source `7d6a8bd8baa74e136ce26b8d75a138e47a9adf0d`.
The preserved candidate branch remains `eb68b46259f745e86ec9f41c144d473f19d0fb0f`;
its later changes are documentation/evidence only.

The repository already supplies native Flutter integration entrypoints for the
changed checklist workflows. An x64 Windows host with the approved Flutter toolchain,
Visual Studio desktop C++ / MSVC workload, Python 3.11+, Rust 1.99.0 and
prepopulated locked/offline Cargo build inputs can run these in an isolated exact-source checkout:

```powershell
git rev-parse HEAD
flutter doctor -v
flutter test integration_test/checklist_workflow_test.dart -d windows
flutter test integration_test/checklist_lifecycle_test.dart -d windows
```

Run the two commands separately, retain their exit codes and complete logs, and
record source SHA, host/toolchain versions and hashes of the generated debug
application/DLL. Do not broaden resources or install/upgrade dependencies as part
of this route without the existing authorization. If required tooling is absent,
report that blocker.

The workflow entrypoint covers two actual application flows: desktop dark at
1200x850/100% and narrow light at390x820/200%, repeated item editors, separate
Save/Cancel, completion warning cancellation, incoming peer changes renewing
consent, and fresh unchecked recurrence copies. The lifecycle entrypoint adds
seven native application gates for Save/late acknowledgement, capture ownership,
Undo/close coalescing, app disposal and user changes. These are test-runner inputs
through Flutter `WidgetTester`, not OS mouse/keyboard automation.

Both entrypoints construct fresh temporary synthetic shared folders and pass
explicit `TandemlogApp(profilePath:...)`; they do not open the live profile.
Their helper `captureNativeFixtureUi` returns immediately on Windows, before
calling any screenshot/desktop-control subprocess. The existing Linux-only
xdotool/import capture helper is not a Windows control route. Do not substitute
shell mouse/keyboard input, CUA calls or GUI takeover for unavailable tools.

This route is feasible from repository source inspection and passed9 equivalent
Linux native flows; it has **not been executed on Windows in this cloud task**.
Passing it would add Windows source-bound native application/lifecycle evidence.
It rebuilds a debug test application, so it does not establish manual visual
acceptance or execution of the downloaded release executable, physical display
presentation, real assistive technology or Android SAF/IME behavior. Keep those
claims and the exact downloaded-artifact acceptance separate.

Independent source review found no route blocker or acceptance overstatement.
No Windows command was executed during that review.
