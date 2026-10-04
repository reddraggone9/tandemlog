# Ordinary-width reconciliation — proposed, not released

The first content-measured candidate2a251 improved enlarged text but raised its
normal single/bulk thresholds to304/432px. That candidate and its original media
remain preserved as history. It did not fully resolve Lee's ordinary-width
request. Build45 remains paused; this working proposal changes no release version,
published notes, prior media or production branch.

The compact proposal removes redundant decoration space:4px leading padding,
2px outline gap,48px suffix target and Flutter's4px text-to-suffix gap give58px
actual chrome. The threshold adds2px caret clearance. Blank Time has8px chrome
and reserves no absent clear button. Stable full-value/placeholder budgeting
prevents the controls changing layout merely when Time is entered or cleared.
Calendar and clear targets are48×48, preserving the prior2a proposal; published
build44 native targets were40×40. Scheduling apply checkboxes now explicitly
use padded48×48 targets (published build44 used40×40). Bulk allocates the5:3 ratio to the inputs themselves;
the two fixed checkboxes sit beside those inputs, instead of reducing the narrow
Time flex cell. Apply keys/commands and persisted meaning remain unchanged.

| Available row width | Published build44 | Prior2a proposal | Compact working proposal |
| --- | ---: | ---: | ---: |
| Single100% |300|304|288|
| Bulk100% |400|432|384|
| Single130% |390| — |322|
| Bulk130% |520| — |418|
| Single200% |600|443|433|
| Bulk200% |800|541|529|

These are measured native Linux limits for the tested font/theme, not constants
for every platform. At361px available width and130% text, build44 stacks while
the compact proposal fits both populated controls. At290px/100%, published single
editing stacks while the proposal fits. Bulk fields remain fully populated at
400px/100% and440px/130%, with the actual input5:3 split and48px targets.
A blank normal Time gains24px of usable text space (32px→8px chrome).
The reference crops do not report their exact text scale, viewport or editor
mode. A361px row can stack under the published130% single threshold390px or the
published100% bulk threshold400px; this is an explanation of possible conditions,
not a claim that the reference used a particular scale or mode.

The three proposed gallery images contain only centered Before/After labels and
real cropped native UI. Engineering captions are kept here and in source/evidence
JSON. Historical-time-fields is the already-shipped build43→44 presentation;
normal-width is matched dark401px viewport/361px row/130%; enlarged-width is
matched dark520px viewport/480px row/200%. Every pair uses matching synthetic
data, theme and scale. Both candidate widths and raw captures remain reviewable.
No previous evidence or annotated media was deleted or rewritten.

Focused native TaskEditor capsules and boundary tests establish geometry, text
space, proportional inputs,48px targets, blank hints, focus/composing preservation,
calendar opening, clearing and validation at100/130/200% as applicable. They are
not full application/storage coverage. The separate production-app
`date_time_rows_test.dart` rerun covers Save, clean Cancel, canonical preservation,
precision, timezone and simulated keyboard insets, at its original four app
geometries. Relevant32 widget/editor tests and formatting pass.

A transient23px picker overflow came from a mismatched harness:logical portrait
constraints were applied while the actual native window/Navigator media still
reported landscape bounds. The failed diagnostics/capture are preserved. After
aligning the native window and root Navigator media before opening the picker,
both published and candidate sources are clean:329×1000/100% gives a297×568
surface;401×1000/130% gives369×738.4. Bounds agree between both sources. The picker
was not redesigned. Boundary tests now share the modeled viewport/scale with the
Navigator instead of injecting media only below it.

Native Linux evidence is not Windows/Android or real IME acceptance. Controller
composition tests cover preservation across resize; exact Android/device
acceptance remains a separate gate. Independent media/editorial review and root
acceptance are pending. No signing, publication or main work is authorized here.
