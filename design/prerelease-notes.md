Experimental task-management preview. Use a new dedicated test folder and synthetic/noncritical tasks. No stable release or daily-use guarantee.

Includes folder selection, household user selection/creation, task capture, edit, completion and targeted undo, with canonical JSON logs and a rebuildable private SQLite cache.

- Linux: native release bundle, extract then run `tandemlog`. Requires a compatible Linux GTK desktop. Native Linux workflows, restart, error handling and integration tests were exercised.
- Windows: unsigned portable x64 ZIP; extract the entire bundle and run `tandemlog.exe`. Built on a native Windows runner with domain/storage tests. Interactive Windows launch/UI acceptance remains pending. Windows may require the Microsoft Visual C++ runtime and show an unsigned-app warning.
- Android: test-only debug APK, signed with an ephemeral CI debug certificate. Native app launch and SAF grants/restart/remote replacement remain **unverified**: this cloud's software emulator failed before app installation. Do not treat compilation as Android acceptance. Subsequent candidates may use a different certificate and require uninstall/reinstall; preserve the shared canonical folder first. Private settings, grants and cache can be lost on uninstall.

No production signing credentials are used. Android debug performance is not representative of release startup. Provider-specific sync and real phone-to-phone behavior still need device tests. Separate users are attribution, not access control; this version is all-shared.

No recurrence, deletion, durable drafts, nutrition, inventory, games or private spaces. Malformed/unknown history visibly blocks writes; recovery guidance is in `design/recovery.md`.

This GitHub release is marked prerelease and is not Latest. Preview-aware clients may opt in; stable-only clients have no stable build available yet. Checksums accompany all bundles.
