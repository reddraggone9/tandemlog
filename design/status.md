# Development status

Current state only (checked 2026-11-12 against `git tag`, `git log` and the code).
The dated log of every earlier build, trial and checkpoint is in
[archive/status-history.md](archive/status-history.md); per-release receipts are in
[releases.md](releases.md) and `evidence/`.

## Released

Stable **2026.11.1 / build 116** is Latest, published 2026-11-07 from `ef71b88`
(promotion of accepted 2026.11.1-rc.1/build115). [Receipts](../evidence/stable-2026.11.1/README.md).
It contains, at feature level (first stable release in brackets):

- **Tasks:** quick capture into Inbox, one or several at a time; tags; separate
  start/due date rows with optional times; recurring schedules matched against
  Obsidian Tasks; one-level checklists with item notes and ordering;
  collaborative title/notes editing across devices; assignees, Search and Filter;
  Completed view and reopen; bulk selection and editing; session Undo;
  exact completion instants ([ADR0035](decisions/0035-exact-completion-instants.md), 2026.10.7).
- **Food** (2026.10.4): physical containers with expiration, location and contents;
  Stock/Inbox, Retained and Deleted views; responsive editor pane (2026.10.6);
  products and purchases, keep-in-stock minimums and Running low, receipt import
  into the Inbox (2026.10.9, [food-products.md](food-products.md)); row selection,
  bulk editing and Move some (2026.10.10, [batch-selection.md](batch-selection.md)).
- **Agent interface** (2026.10.10): desktop `tandemlog-cli` and its MCP server for
  Tasks and Food ([agent-interface.md](agent-interface.md), install in
  [packaging/README.md](../packaging/README.md#agent-cli-tandemlog-cli)).
- **Activity log** (2026.10.11, redesigned in 2026.11.0): read-only cross-device
  history with values, day headings and details; 2026.11.1 groups multi-item
  changes into one expandable entry and names store links ([activity-log.md](activity-log.md)).
- **Storage:** unified per-installation action history (coordinated cutover,
  2026.10.7, [ADR0031](decisions/0031-coordinated-unified-cutover.md));
  one app-wide local database; 2026.11.1 keeps the decoded history in SQLite for
  fast start ([history-store.md](history-store.md)) and shows an Update screen
  when another device wrote with a newer version.
- **Platforms:** owner-signed Android APK; Windows installer and portable ZIP;
  Linux Flatpak bundle ([packaging/README.md](../packaging/README.md)).

## Implemented but unreleased

`main` (`c494196`) differs from the `v2026.11.1` tag only by release evidence
and documentation.

On branch `vex/food-keeps-for`, not on `main`: **Food shelf life ("Keeps for")**,
approved by Lee 2026-11-10 ([food-shelf-life.md](food-shelf-life.md); its Build
notes say what is built and tested). A format change (`product.edit` revision 2,
`container.add` revision 3), so it ships in one release and every device updates.

## Commands

The build needs Flutter 3.47.5 (pinned in `.github/actions/setup-flutter`) and the
Rust text engine (`.github/actions/setup-text-engine`, `tool/bootstrap_text_engine.py`).
These are the commands CI runs (`.github/workflows/validate.yml`), from the repo root:

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test tool bin
flutter analyze

# Unit tests and native workflows load the production text library by path.
python3 tool/build_text_engine.py --platform linux --output-dir /tmp/tl-native
export TANDEMLOG_TEXT_LIBRARY=/tmp/tl-native/libtandemlog_text.so
flutter test
python3 -m unittest discover -s tool -p 'test_*.py'

# Native Linux workflows (CI runs them as 4 shards).
xvfb-run -a dbus-run-session -- flutter test integration_test/task_flow_test.dart -d linux

flutter build linux --release
xvfb-run -a dbus-run-session -- python3 tool/measure_startup.py --workspace /tmp/tl-perf
python3 tool/build_agent_cli.py --platform linux --text-library build/linux/x64/release/bundle/lib/libtandemlog_text.so --output build/agent-cli
GRADLE_USER_HOME=/tmp/tl-gradle python3 tool/gradle_repository_policy.py install
GRADLE_USER_HOME=/tmp/tl-gradle flutter build apk --debug
flutter build windows --release   # on Windows
```

Run Linux integration tests and the Linux release build one after the other in a
checkout: they share `linux/flutter/ephemeral`. Release candidates, signing and
publication are workflow dispatches described in [releases.md](releases.md);
performance qualification is in [performance-gate.md](performance-gate.md) and
[performance-reference-qualification.md](performance-reference-qualification.md).

## Known limitations

- Workspaces last written by 2026.10.6 or earlier need the offline coordinated
  conversion before 2026.10.7+ opens them; the app cannot convert them.
  Installations older than the newest writer's format stop with "Update the app".
- Canonical history records the writing installation, not the active person:
  the Activity log shows the device only, and names are advisory, not
  authenticated. Undo covers only this session's own actions.
- Unsaved drafts and unfinished Save/import intent live in memory only; they do
  not survive the app being closed ([ADR0031](decisions/0031-coordinated-unified-cutover.md)).
- One shared household space; private spaces, games and nutrition logging are
  deferred ([future-modules.md](future-modules.md)); time tracking was dropped.
- Platform evidence limits: Android acceptance runs on an API 30 x86_64 emulator
  plus Lee's phone for the RC handoff; Windows has hosted builds/tests and
  installer lifecycle checks, not a manual GUI pass; broader real-phone/provider
  and permission-revocation coverage is not done ([runtime-qa.md](runtime-qa.md)).
- UX items deferred on 2026-10-31 (task selection checkbox meaning, Android 200%
  editor action row, raw provider URI in Settings, tooltip linger on section
  switch) are listed in [archive/followon-20261031.md](archive/followon-20261031.md#exact-deferred-list-ranked-owner-tandemlog-writer-revisit-next-ux-milestone);
  not re-checked since.
