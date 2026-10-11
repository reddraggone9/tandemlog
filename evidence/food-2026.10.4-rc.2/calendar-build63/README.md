# Shared calendar correction — build63 preparation

Actual Android build62 is held for wrapped/clipped two-digit dates at320dp/200%.
The same issue reproduces in frozen build62 Tasks on actual Linux with matching
viewport, scale, theme, date and safe padding. Stable56's unchanged picker call
and pinned SDK corroborate shared existing behavior; old Tasks Android runtime
was not inspected.

The shared input now measures all localized day labels with actual font metrics
and fits them to the pinned Material3 portrait grid in both dimensions. It changes
only day typography when needed; user TextScaler, full-date semantics, selection,
other theme fields and full-cell targets remain. No format/dependency/data change.
Geometry is scoped to current default actions/English labels and pinned3.47.5;
future SDK or custom-action changes need renewed layout checks.

Focused24 and actual Linux12 checks pass, including both themes,320×640100/200%
and390×640200%, all31 glyphs, date semantics, preserved scaler and10/17 selection.
The normal baseline passes;200% baseline fails day10's single-line assertion.
Exact source inventory and logs retain attribution. The pointer-visible2.6s Linux
scripted demo is `native-final/native-linux-scripted-preview.mp4`; it is not an
Android touch attestation. Cropped matched dark Before/After lives in `../media/`.

Build62 reported Android passes stay attributed to62. Replacement63 complete
hosted/artifact gates and exact Android calendar acceptance remain pending, as do
SAF child switching/return with workspace-cleared Undo and cold new-v2 fixture UI
replay. No publication or stable promotion occurred; parent acceptance/clearance
remains required. Private importer injections and live data operations are excluded.
