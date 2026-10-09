# Next-preview notes and media

Covered application range: released RC4 source
`44344407200b61d38d7b33f22c0ace715376fd6f` through reviewed implementation
`d7a732eba7494589ef66e2ae1629911273c88a3d`; final test/evidence follow-up is
`66d031eaf08b47fb033adb49d538182f7eff9c01` with identical production inputs.

The two proposed bullets describe only new inline checklist/task-menu behavior
and the unfinished-checklist consent progress fix. Shared history, original
checklists, tags, initial order, bulk accessibility/failures and field spacing
were already in RC4 and are not repeated. The small progress fix needs no image.

The single dark comparison shows the same six unchecked items under the same
synthetic parent, moving from the parent editor to the list. Raw PNGs are retained
in `evidence/inline-checklists/`; both are actual GTK production-main captures at
1200×850 and normal text. Before is local RC4 release mode; After is feature debug
mode. Full histories differ at capture times; the crops exclude the unrelated
demo item under another parent. No live data appears.

The SVG document embeds unchanged original PNG bytes, clips at recorded integer
coordinates and displays at 1:1 scale, with only centered Before/After labels and
a dark canvas. Inkscape rasterization preserves both crops byte-for-byte in RGBA.
`media-receipt.json` binds source hashes, crop geometry and output hashes.

Independent editorial review, immutable publication link, fresh hosted CI,
main-only signed-candidate gates, exact final native acceptance and fresh quota
remain distinct prerequisites. This media adds no native acceptance scope.
