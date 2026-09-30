# Tandemlog

Offline household tasks in Flutter/Dart. Canonical per-device JSON logs live in a selected shared folder; SQLite is a private, rebuildable cache. Folder transport is independent of the application and sync provider.

The first task slice implements folder/user setup, capture, edit, completion and targeted undo. Start with [current status and commands](design/status.md), [design index](design/README.md), and [runtime evidence](design/runtime-qa.md). Android shared-folder behavior is an acceptance gate, not yet a proven capability. Native Windows QA requires Windows.

Games, nutrition with adaptive expenditure estimates, inventory and assisted ingestion remain [future modules](design/future-modules.md). No server or Rust bridge is required.

Experimental downloads use GitHub **prereleases**, never Latest; no stable build is available yet. See [build/release procedure](design/releases.md) and [installation/signing limitations](design/prerelease-notes.md).
