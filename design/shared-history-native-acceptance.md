# Shared-history candidate native acceptance

Application changes are independently reviewed through `f952744`. Use the exact
source revision and CI artifact IDs/hashes in the candidate receipt returned by
the cloud task. A successful build is separate from the affected native flows
below. No candidate publication follows until the platform gates pass.

The Android artifact is a debug, test-only APK with the existing package
`com.reddraggone9.tandemlog`, three native ABIs and an ephemeral debug signer. It
is not an owner-signed release update. Run it on a dedicated synthetic lab
device/emulator with no live profile. The Windows installer is unsigned and
retains the normal AppId; use an isolated lab account and set `TANDEMLOG_PROFILE`
to a fresh QA directory before launching. CI also preserves the exact verified
Release directory as `tandemlog-windows-x64-unsigned-portable.zip`; unpack it in
a new QA directory and verify every file against `windows-portable-provenance.json`.
The provenance binds the complete executable/DLL/assets payload to the commit,
CI run and archive SHA256. Portable QA does not require installer extraction or
replace the separately required installation lifecycle gate. The manifest proves
integrity rather than signing: bind it to the trusted GitHub run/artifact, extract
into a fresh directory and reject extra files. Both may display the unchanged
2026.10.2-rc.3 package version: identify this candidate by its exact revision and
file hashes, not a newly announced release name.

## Reproducible historical fixture

Copy every file from
[`qa-fixture/shared`](../evidence/production-text/shared-history/qa-fixture/shared/)
unchanged into a new synthetic sync folder. Verify the hashes in
[`manifest.json`](../evidence/production-text/shared-history/qa-fixture/manifest.json).
These are actual retained test records, not manually rewritten canonical bytes.
Use a fresh local profile on each peer; do not copy writer identities or caches.
On Android grant the new folder through the real DocumentsUI/SAF chooser. Select
the existing **Synthetic** user. On Windows the equivalent settings file is
`{"folder":"ABSOLUTE_QA_FOLDER","user":"USER_ID_FROM_MANIFEST","appearance":"dark"}`
in the new private profile. This fixture starts with reopened **Parent** and its
independent **Independent child** occurrence, already explicitly initialized for
shared text.

## Affected native flows

1. Open the fixture cold, restart warm, edit the child's title/notes and save.
   Edit the old parent independently, then complete it. The parent leaves Open;
   exactly one existing child retains its text, schedule, tags, order and status.
   Existing feedback says the next occurrence was kept. Undo/reopen affects the
   parent and retains the child. Repeat with completed and deleted children.
2. Hold a private child draft on peerA while peerB recompletes the old parent.
   Import through actual folder transport. The draft and committed child text
   remain independent. Save and scoped text Undo preserve child ownership.
3. Create a new native recurring task and copy its canonical starting folder to
   two fresh-profile peers. Offline, each inserts a distinct suffix into the
   parent text and completes it. Exchange every complete writer stream. Both
   peers converge on one deterministic successor containing both observed edits.
   Preserve a child's own edit while the other completion arrives. Later edits
   to the old parent do not enter this existing child.
4. Undo one of two concurrent parent completions: the other still completes the
   parent, and inherited child text does not unmerge. Session Save/Undo retracts
   only locally owned text work after a peer update. Restart and cache loss must
   reproduce the same text/status without rewriting canonical records.
5. Deliver a valid completion/Undo before its referenced source on a copy of the
   lab fixture. Missing dependencies stay pending with preserved known content
   and draft/receipt ownership; arrival resolves without a guessed seed. The
   frozen `historical_delivery_test.dart` and `closed_runtime_actor_test.dart`
   provide the exact domain/native dependency and actor-collision gates.
6. On Android exercise real IME composition, multiline notes, narrow layout,
   enlarged text, both themes, force-stop/relaunch and SAF stream replacement.
   On Windows exercise keyboard completion/Undo, Unicode folder paths, restart
   and install/replace/uninstall preservation in the isolated profile.

For every flow record artifact SHA256, source commit, OS/device/API/provider,
theme/text scale, observed result and any gap. Hash canonical files before/after
restart/cache reconstruction; new commands may append their own records, while
existing records remain byte-exact. Retain all synthetic evidence. Provide an
actual Windows/desktop and Android video with visible pointer/Show taps and
inspect representative frames. Linux evidence is not Android or Windows evidence.

Cloud coverage includes 507 Flutter tests,37 tooling/compiler checks, independent
review, actual Linux GTK creation/remote draft/Save/scoped Undo/legacy setup,
historical recompletion and dark200% narrow restart. See the
[review receipt and explicit performance limits](../evidence/production-text/shared-history/review-gates/README.md).
Checklist behavior and the separate autocomplete/rank/layout/accessibility/
dependency queue are not part of this candidate.
