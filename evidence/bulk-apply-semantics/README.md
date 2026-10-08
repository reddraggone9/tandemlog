# Field-specific bulk apply accessibility

Branch `fix/bulk-apply-semantics`, based on checklist checkpoint
`eb68b46259f745e86ec9f41c144d473f19d0fb0f`. Production changes only the labels
on existing native Flutter checkboxes; no persisted fields, dependency or native
text engine changes.

All ten schedule toggles and Assignee now expose distinct `Apply …` accessible
names. Start and Due time retain their full context when the visual Time caption
is shared. Checkbox checked/disabled/focus/actions remain native. Add tags and
Remove tags stay distinct text inputs; neither receives an invented apply toggle.

## Frozen regressions and verification

`red.txt` freezes four widget failures against the baseline's missing names.
`native-red.txt` freezes the same defect through two compiled production-app GTK
workflows before the implementation. Later fixture corrections dispose test
semantics handles explicitly, inspect the EditableText semantic node, and compare
the complete normalized original schedule after native Save; these preserve the
missing-name failures and strengthen the affected behavior checks.

All37 editor/widget cases pass (`editor-green.txt`), including all11 apply names
at900px/100% and390px/200%, actual semantic activation with one checked field,
touch reversal, Space activation, retained disabled names with no tap actions
during Save, and distinct Add/Remove tag fields. The new tests retain existing
targets (48px for direct date/time toggles; at least40px for the other desktop
checkboxes). They do not establish native assistive-technology acceptance.

Both actual GTK workflows pass (`native-green.txt`), at1200×850 dark/100% and
390×850 light/200%. They open the real two-task bulk editor, select only Due time
through its semantic action, reverse it with Space, reapply by touch, and Save.
Independent native peer replay observes each original schedule unchanged except
Due time clearing, with original title/Assignee and the added `reviewed` tag.
Every fixture is fresh, synthetic and retained; no live synced data is accessed.

Analysis and format checks are recorded beside these logs. Independent
correctness review reran the four new widget cases and inspected the production
labels, original-schedule assertion and four actual GTK screenshots; no must-fix
was found. Final exact-commit scope confirmation is delivered to the coordinator.

## Pixels and demonstration

`screenshots/` contains four inspected real GTK captures covering the date/time
controls and the lower tags/Assignee area in both geometries. Existing visual
captions/layout are retained. The enlarged modal scrolls; long occurrence labels
ellipsize visually while accessible apply names remain complete. Save/Cancel are
reachable. These are Linux viewports, not Android images.

`bulk-linux-gtk-debug.mp4` records the actual Linux GTK debug app with a visible
X11 pointer and an explicit scripted-workflow label. Activation comes from the
integration test's semantic, touch and Space actions; the pointer identifies
the control. The clip shows Due time apply/reversal, tag entry, unchecked Assignee,
Save and the resulting rows. It is neither a manual screen-reader demonstration
nor an Android or Windows recording. Decoded representative frames were inspected
for pointer visibility and the meaningful states; metadata/hashes are in
`media-receipt.json`. The optional capture hooks are disabled in ordinary tests.

## Remaining platform gates

Exact rebuilt Windows/Android affected acceptance, native screen readers
(TalkBack/Windows narrator or equivalent), Android touch/keyboard behavior and
an Android video remain separate pending checks. The coordinator retains
publication/integrated-candidate gates and existing resource limits. This branch
has no push, CI dispatch, release or stable promotion.
