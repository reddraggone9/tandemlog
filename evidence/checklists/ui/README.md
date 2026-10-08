# Checklist UI/native Linux checkpoint

Reviewed application source: `7d6a8bd8baa74e136ce26b8d75a138e47a9adf0d` on
`feature/one-level-checklists`. Later evidence/docs commits do not change app
inputs. Shared-history c182385 and the separate performance branch are untouched.

## Verification and independent review

- All579 Flutter cases pass against the production native library (`flutter.txt`).
- All60 bundled GTK integration workflows pass (`native-aggregate.txt`), including
  two checklist editor/warning theme/layout flows and seven lifecycle regressions.
- All37 tooling checks pass. Analysis is clean;143 Dart files format unchanged.
- Linux debug main application builds. Exact native ABI and packaged notices
  pass the payload gate; `linux-demo-payload.json` hashes the complete demo bundle.
  Native library SHA256 is
  `a9b0c51f4f6cf347e321d9f47a0dec6161be161adfca44eb5be60c7db7a37e56`.
- Independent correctness review reran29 focused command/presentation tests,
  inspected component pixels and then seven actual GTK screenshot candidates.
  Security accepted immutable receipt/close guards. Host architecture review
  found disposal/global-wait issues; meaningful native reds precede their fixes.
  Final host architecture review accepts exact7d6a8bd with no remaining must-fix.

The GTK whole-app tests exercise repeated item Save/Cancel/Discard, an independent
private parent draft, checkbox and Space completion, Cancel with exact canonical
byte preservation, incoming-item renewed consent and fresh unchecked recurrence
copies. Lifecycle tests use actual LocalLogFolder/native documents and controlled
provider failures: late acknowledgement, route/lease teardown before Undo, forced
application disposal, confirmed/unknown Save plus exact-profile restart, and
Save/Discard before user navigation. They do not substitute for real SAF/provider
or operating-system force-stop evidence.

## Actual pixels and demonstration

`screenshots/` contains actual GTK captures:1200×850 dark at100% text and390×820
light at200%. The narrow parent editor scrolls behind fixed actions; clipped
offscreen content remains scrollable. Both warning choices and item Save/Cancel
remain visible in the inspected views. These are Linux desktop viewports, not
Android screenshots. A stale first “Test starting” capture was rejected and
replaced with the real main application's item draft.

[`checklist-linux-gtk-debug.mp4`](checklist-linux-gtk-debug.mp4) is54.93seconds,
1200×850 H.264/15fps, showing actual X11 pointer/button/keyboard input. It shows
adding multiline notes, item Save/edit/check/reorder, confirmed deletion and Undo,
completion Cancel, Complete anyway and a fresh unchecked ordered successor.
Only idle gaps between action sequences were removed; `video-trim.json` records
retained intervals. The196.4second raw capture remains in the synthetic recovery
folder. An earlier partial recording is retained separately, not presented as the
finished demo.

MP4 SHA256:
`785913a16dce5f43d143be575237ccd1c7903a5f1651d8a35ff3125a724ef6ca`.
Root and independent correctness review inspected decoded frames at4/20/39/50/54s;
the pointer is visible and the meaningful state agrees with the native fixture
receipt. This is representative-frame review, not a claim of uninterrupted
independent playback. Production native replay/history inspection verifies the
final ordered Map/Water bottle/Trail snacks copies, multiline notes, checked old
Water bottle and all unchecked successor items; inspection changes no canonical
bytes (`demo-state-verified.json`).

The new Library helper was fetched from the current skill into a fresh directory,
but its hosted tools/list call failed with HTTP401 before preparation. No Library
upload started. Media is retained here for the coordinator's supported retrieval
and saving workflow; no storage URL or successful Library write is inferred.

## Exact platform gates still pending

Hosted CI [run37739454257](https://github.com/reddraggone9/tandemlog/actions/runs/37739454257)
builds exact7d6a8bd. Android and Windows jobs have succeeded and produced artifacts;
the Linux job was still running when this checkpoint was prepared. See
`ci-receipt.json` for GitHub-reported archive IDs/digests. This consumer's download
attempt receives HTTP403, so their actual bytes are not independently verified
here. The coordinator must retrieve/verify exact artifact and internal payload
manifests before Windows/Android acceptance.

The [platform QA contract](../../../design/checklist-native-acceptance.md) and
retained `qa-fixture/` provide the exact synthetic starting history. Windows GUI,
actual Android SAF/IME/system Back/enlarged layouts and videos, and real assistive
technology remain distinct pending gates. Earlier c182385 acceptance does not
cover this checklist revision. Existing resource caps and historical-prefix CPU
debt still apply. No RC publication or stable feature promotion was performed.
