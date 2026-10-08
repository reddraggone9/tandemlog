# Shared B-style tag control

Lee explicitly approved the shared B-style plan at2026-10-08 13:01:08UTC.
Supported quota77% at13:01:14UTC passed the feature gate. This isolated branch
starts from frozen combined checklist acceptance heada960c882. Its APK and
acceptance branch remain unchanged. No release or stable promotion occurred.

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

Implementation, focused/full test results, independent final code review and
source-bound Linux screenshots/video are in progress. Exact new Android
affected-flow acceptance remains pending. Linux inspection cannot establish
Android keyboard/accessibility/provider behavior or Windows runtime acceptance.
The frozen checklist candidate's separate parent-run Android installation is
not acceptance of this feature.
