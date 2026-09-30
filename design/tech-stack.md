# Approved stack

See [ADR 0001](decisions/0001-client-and-storage.md). Flutter/Dart, SQLite, canonical JSONL logs, native folder adapters. No Rust bridge. Tasks first; no future-domain implementation.

Current toolchain: Flutter 3.47.5 / Dart 3.13.4, pinned dependencies in `pubspec.lock`. SQLite uses the maintained `sqlite3` native-assets package rather than its retired companion library package. Android uses a Kotlin MethodChannel for document-tree permissions and file operations; desktop uses Dart files plus the Flutter team's file selector.

## Storage and runtime constraints

Android SAF provides URI capabilities, not paths. Retain the granted tree permission and enumerate child documents anew on each access. Keep SQLite and writer identity private, disable Android app backup of identity, and fail visibly on permission or provider failures. [Android SAF](https://developer.android.com/training/data-storage/shared/documents-files).

The app does not control BasicSync or any other sync provider. Select a local folder both apps can access. Verify provider-specific append/durability and replacement behavior. [Syncthing's replacement behavior](https://docs.syncthing.net/users/syncing.html) and the closed [September 2026 Android report](https://github.com/syncthing/syncthing/issues/10887) motivate tests; they do not establish that tree grants universally fail or succeed.

Native Windows builds require a Windows host with Visual Studio C++ desktop tools; run the same integration suite there and record actual Windows workflows. [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup). Linux builds require Clang/CMake/Ninja/GTK development libraries. Android builds require SDK/NDK/JDK; emulator acceleration availability is environment-dependent.

Web is not an implemented target. Do not spend effort on OPFS or web folder synchronization to avoid native QA. Current capability, measurements and commands belong in [status](status.md) and [runtime QA](runtime-qa.md).
