# Build59 Food keyboard-layout correction

Actual Android build58 acceptance found that even its two-line Edit1 title and
Cancel/Save consumed all available height at320dp/200% with Gboard open. Build58
is blocked from publication; its successful upgrade/persistence checks retain
their own source/APK attribution in the [handoff](../../../../design/food-native-acceptance.md).

The correction puts title and fields in AlertDialog's single constrained
scrollable viewport above actions. Dirty-close confirmation also scrolls.
The obscured page and closing-keyboard transition retain their geometry; active
in-page text input keeps normal resizing. A viewport-height notification reveals
the current dialog's attached focused input after animated inset resizing.
Controllers, full edited-target count, font scaling, observed targets, pending
Save and durable storage behavior remain intact. No dependency or format change
is included. Bazaar metadata and Flatpak data paths are queued separately.

## Tests first and independent review

`red-focused.log` reproduced a zero-height field viewport against a48px editable
line and a30px underlying-page overflow. Shared scrolling alone still left that
page overflow and a32px dirty-confirmation overflow (`shared-scroller-only.log`).
Route-current resizing alone overflowed during Save/closing IME
(`matrix-first.log`). Stricter already-focused-input assertions then exposed
caret reveal before test-assisted scrolling (`matrix-auto-focus.log`). The first
85-test run exposed traversal of a deactivated old focus element
(`unit-final.log`); the attached-render guard corrected it.

The final production bytes pass85 affected widget tests (`unit-final-r2.log`).
Those tests preceded the final platform-aware action assertion and additional
helper/Back assertions. The separately strengthened final12-case matrix passes
in22seconds (`matrix-final-r5.log`), with clean analysis and formatting.
The first GTK run's32px desktop action failed a48px phone-only fixture assumption
(`native-final.log`); desktop32px and Android/iOS48px assertions now preserve
platform behavior. The intermediate native matrix passed (`native-r3.log`).

The final actual GTK integration passes one complete matrix case in6:16
(`native-final-r4.log`): dark/light ×100/200% × Add/Edit1/Edit100. It uses320×640
logical pixels,24px safe top and simulated280px keyboard insets. It checks
already-focused name and reopened date before manual scrolling, every input and
certainty popup, helper beginning/end, invalid calendar rejection without state
mutation, full error, keyboard close/reopen preserving draft, Cancel and route
Back→Keep editing, and successful Save across the exact physical count. Save
keeps simulated IME open through modal exit to catch closing-page overflow.
Back is a Flutter route event; actual Android keyboard/Back ordering is pending.

The native run used [this executed fixture](native-r4-executed-fixture.dart.txt).
After it ended, final source added only a nonempty selected-glyph-box assertion;
the final12 widget tests above and required hosted native aggregate exercise
that guard. The production UI hashes stayed unchanged. This distinction is
bound in the [manifest](manifest.json), [architecture review](architecture-code-review.json),
[build59 supplement](architecture-build59-supplement.json) and
[independent UX/pixel review](final-r4-source-native-ux-review.json).

## Actual pixels and demonstration

All120 captures are original native X-window pixels, ten states per case.
The warmup frame is excluded. At200%, the long title, helper and discard
explanation can scroll; focused input/caret and actions remain visible.
The independent reviewer accounted for every capture:50 new/changed images
viewed directly and70 exact SHA256-byte-identical to previously viewed images.
The manifest retains every byte count/hash and current production/test bindings.

[30-second desktop demo](native-linux-build59-keyboard-demo.mp4) shows dark200%
Edit100, focus/caret, helper scrolling, invalid-date error, keyboard transitions,
discard/Keep editing and valid-date typing/Save input. It is a continuous trim
and native-window crop of the original matrix recording; the original hash/path
is retained in the manifest. The actual X crosshair marks scripted pointer
inputs, independently decoded for inspection. [Demo receipt](demo-verification.json)
records cropping/timing and platform limits. No image repaint or generated UI
is used. These are Linux GTK debug pixels with simulated insets, not Gboard,
Windows or human-user acceptance.

## Remaining delivery gates

Build59 needs a fresh successful signed candidate with its full hosted matrix,
exact original installer/source/signature/native-payload identities and fresh
Linux/Windows installed lifecycles. Windows manual GUI remains RC-waived.
Actual Android must pass the combined Gboard/title/text/error/field matrix,
Cancel/Back/dismiss/reopen, blank/valid-date persistence and stable56 upgrade on
that exact APK. Existing build57/58 receipts retain their original attribution.
Final notes/media review binds the actual frozen stable→candidate range.
Publication awaits exact Android acceptance and the parent's private quota
snapshot under the existing Food override; stable2026.10.3 remains Latest.
No live data or source import was used.
