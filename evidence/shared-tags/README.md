# Shared B-style tag control

Lee explicitly approved the shared B-style plan at2026-10-08 13:01:08UTC.
Supported quota77% at13:01:14UTC passed the feature gate. This isolated branch
starts from frozen combined checklist acceptance heada960c882. Its APK and
acceptance branch remain unchanged. No release or stable promotion occurred.

**Release/native acceptance is blocked.** The parent reports a reproducible
historical checklist recompletion defect in exact source `17ae5e5`: later old
parent text leaks into an independently edited successor and survives Undo and
cache rebuild. This branch inherits the affected core byte-for-byte. The exact
native sequence/fixture is awaited for a tests-first narrow fix and new candidate
retest. Passing tag CI does not resolve that core defect.

[Accepted interaction and context policies](../../design/decisions/0012-shared-tag-input.md)
describe one chips-above-query control for editing, bulk Add/Remove and Filter.
Original tag values remain opaque; new query parsing cannot rewrite their case,
spaces or leading marker. Existing domain validation and observed-tag references
remain authoritative.

## Frozen behavior gates

- b1b80aaa: two layout and three editor/removal regressions compile and fail
  against old production; [receipt](red/manifest.json).
- 8d0d22e0: eight failures including opaque original values, failed-Save draft
  retention and active-composition safety; [receipt](red/draft-safety-manifest.json).
- 619a6ccd and977aab86: independent accessibility controls, selected suggestions,
  separate bulk deltas/Apply state and save-time freezing;
  [first receipt](red/semantics-manifest.json),
  [extended receipt](red/semantics-controls-manifest.json).
- 1655938: actual Linux GTK reproduces the absent completed-task suggestion in
  the old editor at1200×850; [receipt](red/native-manifest.json).

The native workflow uses isolated synthetic profiles and the actual bundled
production text engine. It checks task-wide inventory, opaque selected tags,
Save/Cancel/Discard, bulk deltas and match-any filtering without history writes.
Desktop dark, narrow dark and narrow light at200% are separate geometries;
simulated keyboard insets establish Linux geometry only.

The [Before screenshot](native/before/editor-selected-desktop-dark.png) is actual
Linux GTK debug at the unchanged production base, viewed directly. Its
[manifest](native/before/manifest.json) records source, dimensions and digest.
It shows the legacy space-separated field without selected chips/suggestions.

## Current gates

Production `041c06488` and test source `8b13cd0e` pass independent correctness
and architecture review. The local [validation manifest](green/local-validation-manifest.json)
binds actual logs and artifacts: 621 Flutter tests, 37 tooling tests, three
actual Linux GTK tag workflows, clean analysis and 154-file formatting. The
final fixture corrections preserve field names despite merged semantic hints,
use the existing compact Edit selected action and avoid a redundant Escape
after selecting a suggestion; they do not change production behavior.

The [17 actual After screenshots](native/after/) and
[37.6-second desktop recording](native/shared-tags-linux-desktop.mp4) were
viewed directly and independently reviewed. Chips, query, selected suggestions,
bulk deltas and filtering remain legible at the recorded desktop/narrow/theme
and text-scale variants. The desktop pointer appears in the recording. Popups
can temporarily cover later fields/footer; collapse and dismissal remain usable.
The canonical Cancel/Discard and filter checks passed without history writes.

The first [three-platform CI](https://github.com/reddraggone9/tandemlog/actions/runs/37789101688)
passed Android and Windows but failed two legacy Linux native interactions.
Both failures were reproduced locally and corrected in test revision `5204e276`:
close the open popup before Cancel and use the chip's contextual removal tooltip.
The [red/green receipt](green/legacy-native-controls-manifest.json) preserves
all caret, canonical-byte, filtering and close assertions; both cases now pass
and independent review accepted the corrections. Production remains `041c06488`.
[The second full CI](https://github.com/reddraggone9/tandemlog/actions/runs/37792711739)
against exact `5204e276` passed Android, Windows, Linux units and contracts,
but finished the native aggregate at 68 passed and one failed: an open tag
popup intercepted a legacy bulk Save tap. The unchanged standalone case passed
locally; no local red reproduction is claimed. Test-only `ec2309db` now pumps
and dismisses the actual popup, verifies the pending query and Save hit-testing,
and compares the exact prior tag set after rejected Save. Its focused actual GTK
flow passed 1/0; independent review accepted the stronger checks. The
[qualified red/green receipt](green/bulk-save-controls-manifest.json) and
[CI receipt](green/ci-5204-receipt.json) retain the source and log bindings.
[Final full CI 37796892998](https://github.com/reddraggone9/tandemlog/actions/runs/37796892998)
passed all three platforms at exact `ec2309db`: Linux 621 unit tests and
69 actual native flows; Windows 619 unit tests plus two expected Linux-only
skips; four Cargo, 107 native-worker and 37 tool tests on both desktop runners.
The [final receipt](green/ci-receipt.json) binds decoded log hashes and reported
artifact metadata. Consumer archive/APK bytes and Android runtime are unverified.
The historical-recompletion blocker above remains unresolved.

Separately, [22 actual Windows native debug flows](https://github.com/reddraggone9/tandemlog/actions/runs/37790261412)
passed on `ff1d1f82`, including the three tag workflows; decoded logs, startup,
counts and source binding were independently reviewed. The isolated branch's
[qualified result](https://github.com/reddraggone9/tandemlog/blob/test/shared-tags-windows-native/evidence/shared-tags-windows/result.json)
records that later `ec2309db` changes only three excluded legacy aggregate blocks;
the seven selected test bodies and production inputs remain unchanged. Archive
digests/sizes are reported metadata, without consumer byte verification.

The [focused Android handoff](../../design/shared-tag-native-acceptance.md)
and hash-verified synthetic fixture provide known multiword/leading-marker tags
and completed-task inventory. Exact new Android affected-flow acceptance remains pending. Linux inspection cannot establish
Android keyboard/accessibility/provider behavior or Windows runtime acceptance.
The frozen checklist candidate's separate parent-run Android installation is
not acceptance of this feature.
