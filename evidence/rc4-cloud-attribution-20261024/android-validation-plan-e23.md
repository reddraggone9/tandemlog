# Android native validation plan — exact e23f00f

Snapshot:2026-10-25 01:49UTC. Prepared for the parent's existing local executor;
not executed by cloud. This is development runtime validation, not a release,
live cutover, owner-signing request or hardware presentation acceptance.

## Source and artifact preconditions

- Product source: `e23f00f9640ee5724f4b646d37bc352ca58dc6f1`, branch
  `fix/rc4-task-latency-20261022`. Later documentation-only successors may be
  present; verify the actual app inputs, not just the branch name.
- Exact build: [CI40151805818](https://github.com/reddraggone9/tandemlog/actions/runs/40151805818),
  Android job `121044713164`. At this snapshot its `android` artifact has not
  appeared. Wait for that job's successful build/payload verification, resolve
  its actual artifact ID/SHA256 and verify the downloaded archive and APK.
  Preserve the original CI metadata and APK hash with the receipt. Do not
  substitute prior5dc artifact12582355075 or rebuild and retain its attribution.
- Check the extracted APK's actual manifest, ABI and signature. Current source
  declares package `com.reddraggone9.tandemlog`, version
  `2026.10.7-rc.5+100`; this is an existing development version, not a new RC.
  The CI artifact is a **debug APK**, not the owner-signed release candidate.
  No signing configuration, credential or version change is authorized.
- Use an isolated compatible debug installation. Do not overwrite an owner-signed
  installation or uninstall/reset a retained profile to get around a signature
  conflict. Select a previously authorized empty disposable lab instance instead;
  otherwise report the exact install blocker for coordination.

## Device and foreground boundary

Use only the **previously isolated Farnsworth Android emulator lab**, through the
existing authorized local-executor route. Read its current ownership/device
receipt first; confirm the exact emulator serial, API/ABI, viewport/density,
running processes and settings before targeting ADB. Historical accepted labs
used Android11/API30 x86_64; that is a qualification, not proof of today's live
instance. Never select the first available device or use an attached real device.
Do not create persistent services/access or reuse a personal Android profile.

The test **requires foreground UI interaction inside that isolated Android
emulator**: real app launch, pointer/touch, native IME, dialogs and the system SAF
picker. It can run with the emulator's display captured inside the existing
isolated lab; it does not require or authorize foreground input on Leela or the
user's Windows desktop. It is not an ADB-only installation smoke check. Cloud
does not access the device. Parent/local executor coordinates any lab/startup
permission missing from the existing environment route.

## Fixture and evidence preparation

1. Preserve the lab's original settings and ownership receipt before changes,
   including Show taps, pointer/IME, density, font scale and theme. Keep precise
   restore information privately. Start screen recording with visible Android
   Show taps and inspect a sample to prove the indicators and keyboard appear.
2. Bind only a new, explicitly public synthetic workspace in a lab-owned empty
   folder/SAF tree. Use synthetic participant/task names and no real peer folder,
   account, personal fixture, notification or retained history. Avoid live
   conversion/adoption; fixture preparation is outside all action timers.
3. For realistic growth use the exact source's existing
   `tool/performance/benchmark.dart generate` / `synthetic_fixture.dart` contract:
   `1320`, `2640`, `food:2640`. Compile/run with reviewed native assets in the
   local executor's approved toolchain. Retain the generator/source/native hashes,
   `syntheticOnly` manifest and sealed canonical file hashes. Create separate
   workspace/profile copies; never alter the sealed originals to make UI pass.
   Confirm current-format admission through the real app and one isolated writer
   per workspace. Record legitimate synthetic setup appends separately.
4. Keep before/after closed copies of canonical files and a complete expected
   action ledger. SQLite/private profile captures must come from a stopped
   compatible debug app, using the existing lab recipe. Do not copy an open WAL
   database as a coherent snapshot or introduce broad filesystem grants.

## First focused workflow: the repaired Undo/Cancel regression

On a small new three-task fixture, use actual touch/native text input:

1. Open task1, change Title, Save; verify the editor closes, the row updates and
   Undo is enabled. Assert one exact text-edit record for task1.
2. Reopen task1, type different unsaved Notes, press Undo. Check the unsaved-draft
   dialog, keyboard/focus and reachability. Choose Cancel. Exact Notes and editor
   remain, Undo is visibly enabled again, and canonical bytes match the saved
   state exactly: Cancel adds no action.
3. Press Undo again, choose Discard. The editor closes, task1's original Title
   and Notes return and Undo is consumed. Assert exactly one matching Undo record
   with the original Save's exact target/reference. Tasks2/3 remain unchanged.
4. Independently replay the closed canonical result into a fresh disposable
   profile. Verify all three tasks, exact two action additions, original byte
   prefixes and no extra canonical writes during replay/cold reopen.

## Broader RC4 native functional/visual coverage

Reconcile every interaction in `tool/performance/coverage-v1.json` against the
actual controls; use its unchanged metric IDs and `design/performance-gate.md`.
The storage suite's232 labels do not establish full native UI acceptance.

| Family | Native workflows and correctness checks |
|---|---|
| Task entry/editor | Capture1/3 lines; Title, Notes, both, no-op and Cancel; Save/Undo in open/closed editor; imported and derived targets; keyboard/focus and narrow dialog layout. |
| Task commands | Schedule/tags/assignee; delete/restore; manual reorder and bulk edit/delete/reorder; selected/filtered rows and no-op. Verify expected exact records/order and Undo. |
| Completion/checklist | Complete/reopen; checklist decline/confirm; add/edit/cancel/toggle/reorder/delete/Undo; first untouched copied item and derived successor protection; native ownership/readiness unchanged. |
| Food | Add1/3, open/edit/cancel, descriptive/brand changes and bulk confirmation, remove/restore and every session Undo; Stock/Deleted/retention filters, calendar, search and grouping. Include imported Food and500-container stress. Do not invent a UI for an API-only contents metric. |
| Navigation/readmodels | Tasks/Food navigation, remembered section, modes/search/assignee/tag/brand/location filters; user switching, cold/warm reopen and real visible publication. |
| Peer and failure | Synthetic peer Task/Food changes while the other section/editor is open; newer peer edits survive Undo; rejected Save retains continued typing/native session; owner-only partial-tail repair with exact-once receipt. |
| Startup/history growth | First useful screen and clean reopen across all3 histories; startup maintenance and first-use derived/copied actions. Compare Task-history and Food-history growth separately. |

Run ordinary portrait and narrow/enlarged text in both themes; retain actual
viewport/API/ABI and native screenshots. Check loading/empty/error states and
touch targets as relevant. A blocked or unimplemented case remains pending,
with exact action and reason; do not weaken an assertion to finish the list.

## Timing and final receipt

Ordinary input-to-visible acknowledgment retains the below100ms objective;
preserve every existing stricter storage limit and paired-growth rule. Declare
the native action's input/acknowledgment endpoints and intended budget before
initial measurement, including first-use/history shape. No post-observation
calibration/headroom or looser target is authorized. Emulator/ADB command elapsed,
screenrecord frames, framework post-frame and hardware presentation are distinct.
Do not label ADB transport wall time or Linux/Android software rendering as
hardware latency. Missing faithful native timings remain an acceptance gap.

Retain failed attempts, source/artifact/device pins, the action ledger, original
capture, labelled cuts, screenshots, independent prefix/replay/projection checks
and settings/process cleanup proof. Minimal honest video is sufficient; remove
only labelled idle pauses and preserve action speed. Restore exact original lab
settings and stop only owned processes; preserve fixtures needed for review.

Report functional/visual, timing, integrity and cleanup outcomes separately.
Owner-signed exact candidate acceptance, real foreground Windows full-action
timing, physical ARM/API36 coverage and any release remain separate prerequisites.
No device execution, live data change or signing operation is authorized here.
