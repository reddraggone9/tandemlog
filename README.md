# Tandemlog

Offline household tasks in Flutter/Dart. Canonical per-device JSON logs live in a selected shared folder; SQLite is a private, rebuildable cache. Folder transport is independent of the application and sync provider.

Tasks support folder/user setup, capture/edit, dates and times, tags, recurring tasks, completion history and targeted Undo. Start with [current status and commands](design/status.md), [design index](design/README.md), and [runtime evidence](design/runtime-qa.md). Native API30 shared-folder and lifecycle evidence is recorded with its limits; wider phone/provider coverage remains separate. Windows installed checks run on native hosted Windows, while Linux is the primary desktop visual QA target.

Games, nutrition with adaptive expenditure estimates, inventory and assisted ingestion remain [future modules](design/future-modules.md). No server or Rust bridge is required.

Find Android, Windows and Linux installers on [Releases](https://github.com/reddraggone9/tandemlog/releases). Stable releases use Latest; experimental downloads are marked **prerelease**. Durable v3 histories remain backward readable from first stable 2026.10.0 onward. See [release procedure](design/releases.md) and [installation/signing limitations](packaging/README.md).
