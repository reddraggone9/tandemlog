# Combined preview preparation

The merge-only source is `d99d03d3be03601d109a748b083e3fa2bdd0b578`.
Local checks used exactly those production/test/native inputs with the proposed
`2026.10.2-rc.4+46` pubspec metadata and documentation changes in the working tree.
The eventual frozen CI commit is recorded separately; these are local checks,
not evidence of that commit's hosted build or release payload.

`local-receipt.json` binds all 28 copied logs, source-binding/version-floor receipts
and screenshots by SHA256. Formatting checked 156 files without changing them;
analysis found no issues; all 628 Flutter unit/widget tests passed.

Actual Linux GTK debug execution passed the historical recompletion workflow
once, retaining the independently edited child and five checklist items through
recompletion and Undo. A second entrypoint in that invocation could not attach its
debugger. The failure log is retained. Launching the tag entrypoint separately
passed its three workflows; there were no product/test changes between launches.
The debug bundle used the reviewed native library SHA256 recorded in the receipt.

The 17 tag screenshots cover editor, bulk and filter controls at desktop and narrow
widths, dark/light themes and enlarged text. Twelve decoded RGBA images equal the
previously reviewed shared-B captures. Independent review found the other five differ only in 2x24px caret
visible/absent regions; all other pixels match.
Two historical screenshots show recompletion and subsequent Undo; the startup
frame is excluded from accepted UI evidence. This is Linux/Xvfb evidence, not
Android, Windows, physical display or signed installed-release acceptance.

Independent architecture review accepted source composition, documentation and
local receipt qualification. Correctness and security source composition gates
also accepted. Independent correctness review accepted the combined screenshots/receipt,
verified the production bindings and actual bundle native hash, and found no
layout/input regression.
Full composed CI, parent A16 retest and artifact-byte verification, fresh quota,
exact signed/native acceptance, UX audit and release-note/media range review
remain required. See [the current contract](../../design/final-preview-acceptance.md).
No main merge, signing or publication has occurred; stable feature approval is
absent. The original failed candidate and isolated replacement remain frozen.
