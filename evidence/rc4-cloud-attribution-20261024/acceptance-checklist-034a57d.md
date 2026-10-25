# Remaining acceptance and Android delta — product034a57d

Checkpoint2026-10-25. Public engineering review only: no new product patch,
benchmark, CI dispatch, device operation, release or live change.

## Current evidence

- Exact CI40167598688 passes Linux/Windows/Android,1515units,174tools,203native
  Linux workflows and original/deterministic normal-close checks. Its hosted
  performance gate remains **failed:5absolute maxima,3paired metrics**, including
  one paired median. [Retained attribution](remaining-performance-triage-034a57d.md).
- Parent now supplies completion of the **three predeclared current034a57d
  Farnsworth reference observations**: each has zero absolute median/max and zero
  paired median/max misses; all118source/5390compiled pins, fixture correctness,
  sample counts and package checks pass. No timing retry/replacement. Manager
  finished07:59:11UTC; all4owned units absent/inactive,MainPID0,source clean.
  [Qualified supplied receipt](reference-034a57d-final-supplied.json). Cloud has
  not accessed the raw local files. Supplied reportSHA256:
  `73629403341640bcf0185e6e3db710e2e44b1d74079be56f98f6200d5a10a32b`.
- This closes the planned current-source **reference-measurement** gap. It does
  not waive the hosted failures, prove a virtualization cause, change gate-host
  policy or establish visible/hardware latency. No further benchmark is requested.
- Supplied **e23** Android emulator evidence covers repeated Task Save/Undo,
  Cancel/Discard,completion/Undo,Food validation/Add/Edit/Remove/Undo,cold reopen
  and4independent replays. It remains older-source evidence. Its narrow modal
  did not expose dirty-editor **Session Undo**; ordinary editor Discard coverage
  is not a substitute for that control.

## Exact-source Android artifact for the local executor

Use the existing passed build; **do not rebuild** or substitute the6e400f7/e23APK.

| Binding | Value |
| --- | --- |
| Source | `034a57dbc7092e242889d23d12e22091fed08b0c` |
| CI / Android job | [40167598688](https://github.com/reddraggone9/tandemlog/actions/runs/40167598688) / `121091718752` PASS |
| Artifact | `12588729911`, name `android`, available until2026-10-30 06:07:21UTC |
| Archive SHA256 | `f6474faab844df1250dd77c7722ccc4f496261d3438f6a7eb2c034313acd0078` |
| APK | `tandemlog-android-test-only.apk`,165629425bytes |
| APK SHA256 | `11e685b28a0c76d7159d67430321e30ecb16d5d1e4c7360a3a1e9e719b26f600` |
| CI debug certificate SHA256 | `5deef41d8133fb3f9a041215da536efbffceb7768baf4743af50f742b75f86e7` |
| Expected manifest identity | `com.reddraggone9.tandemlog`,versionName `2026.10.7-rc.5`,integer versionCode `100`,debuggable `true` |

[Full independent archive/APK/static receipt](android-artifact-034a57d.json).
Cloud verified the archive digest, APK digest, embedded checksum and byte equality
to e23 of the binary manifest, all3native text libraries and native notices.
Cloud has no Android SDK/signature/manifest tools and has not installed/launched
the APK. Actual manifest and signature-tool verification remain local preflight;
the CI signature text is provenance, not a cloud re-verification of the signature.

**The current debug certificate differs from e23's** (`9b0e3e85…25ff250c`).
Do not overwrite/uninstall/reset a retained e23 or owner-signed installation to
bypass a signature mismatch. Use a previously authorized **empty disposable lab
profile/instance**, preserving the old populated AVD/evidence. No signing change,
new credential, physical device or personal profile is authorized. Confirm the
exact owned emulator serial/API/ABI first; never target the first ADB device.

The local helper must check versionCode as integer100 and debuggable=true for
this exact debug artifact, and use the already corrected owner-specific imports.
Do not reuse its former string100/nondebug expectation or weaken those checks.
Verify archive, APK, certificate, manifest, native payload/notices/alignment and
installed package before UI work; retain every preflight refusal as infrastructure
evidence. A conflicting package is a setup blocker, not a product failure.

## Minimum Android delta from e23

The complete product diff is confined to:

1. **UTF8 count-only size guards** in CurrentOperation.decode,LogEvent.decode,
   FoodRecord construction and UnifiedRecord construction/decode; new helper
   preserves the original exact conversion whenever the conservative bound cannot
   prove a small value safe. No format,canonical serialization,error order or
   durability change. Full unit/oracle tests already cover malformed surrogates,
   byte boundaries, caller errors and frozen historical bytes.
2. **Linux-only GTK window/view/engine disposal** plus lifecycle QA. No Android
   embedding,Gradle,manifest,SAF,plugin/native payload or device lifecycle change.
   Exact Linux closure/native gates already pass; Android does not need to repeat
   GTK disposal tests.

For current-source Android development continuity, use **one fresh copy** of the
sealed public synthetic baseline fixture (reference pins verify original canonical
hashes), with a new disposable profile/SAF tree and the exact APK. No real/synced
folder,live conversion or mutation of sealed originals. Existing e23 generation
may be reused only after verifying those bytes; do not regenerate broad datasets.
Use the established bounded isolated emulator controller after comparison cleanup.
Expected focused UI work10–20minutes plus independent replay/cleanup, within its
existing finite deadline; do not extend it automatically for a blocked control.

Run actual native touch/IME interactions, retain screenshots/action ledger and
the closed canonical before/after copy:

| Delta check | Required observation / integrity assertion |
| --- | --- |
| Fresh admission | Exact currentAPK opens the synthetic Task/Food history without error; baseline Task rows/Food state match sealed expected state. Exercises current decode/admission paths. |
| Task Unicode Save/Undo | Save a Title and Notes containing ordinary ASCII,`Café`,CJK and a non-BMP emoji. Verify the native editor/row after Save,exact one admitted edit,then Undo restores the full baseline target without touching other rows. No malformed surrogate needs to be forced through the IME. |
| Food Unicode Save/Undo | Edit an existing synthetic container's name/brand with the same Unicode classes,confirm Save,then session Undo; verify exact confirmed receipts,baseline Food state and unaffected Task rows. This exercises FoodRecord and shared current/unified envelopes. |
| Cancel/Discard no-write | Type an unsaved Task change,Cancel the discard confirmation and verify continued typing; then ordinary Discard. Both boundaries leave canonical bytes unchanged and preserve the saved baseline. Keep this separate from the unexposed Session Undo case below. |
| Cold reopen and replay | Close normally,read back canonical files coherently,then reopen. No unintended appends,original prefixes unchanged,expected Save/Undo ledger exact. Independent fresh-profile replay matches full final Task rows and Food state,not only the visible edited row. |

A backgrounded Android activity is not a stopped app. Use the existing reviewed
lab stop/coherent-snapshot recipe before readback; do not copy an open WAL database
as a complete profile or interrupt an outstanding Save to obtain a snapshot.

No need to repeat all232storage metrics,all3growth benchmarks,all203Linux cases,
the full previous Food/completion matrix or artificial1MiB UI entry merely for
this equivalence-preserving delta. Those retained results keep their source and
scope. This focused receipt establishes current debugAPK/emulator continuity;
it is not broad native,owner-signed candidate,physicalARM/API36 or timing acceptance.

## Existing native gap to attempt separately

On the same empty lab only if the genuine app control is reachable, exercise
**dirty-editor Session Undo → Cancel → continued typing → Session Undo → Discard**
against a prior saved action. Cancel must preserve exact draft/caret/native session
and the Undo action with no canonical write; Discard must close the editor and
apply exactly the saved action's matching inverse while preserving newer peer
edits. The exact Linux suite already covers this regression; Android visibility/
focus/reachability is still unobserved. Do not replace it with ordinary Cancel or
Discard,edit product source,inject an internal command or change the UI to expose
it. If the narrow modal still lacks the control, retain screenshot/viewport and
the precise blocked step. Report the gap honestly instead of running broad tests
that cannot close it. A future actual UI change requires separate design/runtime
review and fresh evidence.

After native work, restore original lab settings and retain an independent closed
readback/replay plus exact owned process/unit/port cleanup proofs,including any
failed setup. Use the already approved controller/resource bounds and the parent's
local executor; cloud accesses no devices or foreground windows.

## Acceptance still open after that focused receipt

- **Hosted enforcing performance remains failed.** Three supplied current-source
  local passes are qualification evidence. Gate-host/policy changes require a
  separate explicit decision; no automatic substitution or looser limits.
- **Full-action native visible responsiveness.** Existing below100ms objective,
  stricter action budgets,first-use/history-growth cases and ownership/failure
  guarantees stay fixed. Linux/software-rendered,Android emulator,ADB elapsed,
  framework post-frame and hardware presentation are distinct endpoints. No new
  foreground Leela/physical-device authorization is implied.
- **Actual native coverage gaps**,including Android dirty-editor Session Undo
  reachability and eventual source-pinned broader platform/candidate checks,
  remain itemized rather than inferred from a build or the Linux suite.
- **Release/live cutover remain held.** A later exact owner-signed candidate must
  meet existing fresh candidate/platform/native/editorial gates and applicable
  acceptance. Actual physical-writer mapping,fresh frozen real-copy conversion/
  replay and explicit live-adoption/publication boundaries still apply. No such
  work is requested or performed here.

Cloud remains sole product writer until explicit handoff; hard stop-write is
2026-10-26 13:00UTC. The local executor performs only the coordinated immutable
artifact validation. No further product repair is justified by these local
reference passes alone.
