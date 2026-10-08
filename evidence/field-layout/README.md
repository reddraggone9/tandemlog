# Sort-bound and tag-filter field spacing

The fix leaves room between the Sort-date explanation and the floating Minimum
days label. Find tags uses consistent query padding, with clear/expand controls
aligned to its final row after selected chips wrap.

Six frozen geometry regressions failed against `eb68b46`: normal/enlarged floating
labels, and empty/selected/wrapped tag-query caret/control gaps at260/390px and
100/200% text. The corrected control measurement uses the full IconButton target,
not its inset Tooltip child. Both the original and corrected baseline red logs
are preserved. All42 affected widget tests and analysis pass.

The same three tests also pass through their registered aggregate entrypoint.
Three actual native Linux GTK debug application workflows pass:1200x850 dark100%,
390x850 dark100%, and390x850 light200%. Nine actual PNGs show the affected fields.
Tests cover focus, empty and selected query, Escape, chip selection and clearing;
editor Cancel and filtering retain every synthetic canonical byte. A separate
actual main-app demo uses real X11 pointer/button/keyboard input at1200x850 dark.
Its recording retains the inputs and states, removing only waits between requested
action batches. The pointer is visible in decoded frames. The demo's shared files
also remain byte-identical; its receipt lists their hashes.

Independent review reran42 tests and inspected all nine native screenshots,
accepting production blobs `797ae76c58cfdb6b5b1a4e04ab68bca11d31c116` and
`801bcd8437017f0394901b784791e4ae6fb6880f` with no must-fix. Independent video review decoded3/12/15/30-second frames, confirmed the visible
arrow and affected states, and accepted the36-second recording. Source, media
hashes, trims and review scope are recorded in `ui/media-receipt.json`.

Reference grounding: the supported current Library resolved-reference helper
returned HTTP403 for all three originals (`libfile_0c8e6320c1288191a405cb721ef5816b`,
`libfile_1df11331f0ec8191bc6a734ade1a82b4`,
`libfile_c290c53da31881918598989ed0586eb4`). The parent inspected the actual original
pixels and explicitly authorized its verified observations as the fallback. The
first shows explanation/label crowding; the latter two show different query/caret
gaps relative to the underline before/after selection. Those observations match
the frozen geometry failures. No local original-image inspection is claimed.

Actual Android/Windows visual, physical IME and assistive-technology acceptance
remain pending. These Linux results do not establish those gates; no publication
or stable promotion was performed. The already reviewed checklist candidate is
unchanged. This branch is separate from tag-entry autocomplete exploration.
