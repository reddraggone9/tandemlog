# Inline checklist and task-menu follow-up

Executable source: `d7a732eba7494589ef66e2ae1629911273c88a3d` on
`feature/inline-checklists`, above the frozen completion-progress fix `308541e`.
Released rc.4/build47 source remains `44344407200b61d38d7b33f22c0ace715376fd6f`.
No new release/version/dependency/native or canonical-format change is included.

The list owns default-collapsed completed/total disclosure and inline item
controls, outside parent selection/focus and task drag/drop geometry. Each task
has a separate menu left of its drag handle, also available through right-click
and Context Menu/Shift+F10. Add checklist opens an empty block and focuses bottom
Add item without a canonical write; Delete confirms and affects only that row,
even with other rows selected. Item Save/Cancel remains independent from parent
editing. Direct item Delete retains confirmation and Undo. Sparse expansion
entries use existing workspace metadata; cache loss resets the preference.

## Frozen failures and checks

The initial native red fails on the missing task menu. Independent review then
froze the provider-refresh exception escaping menu Delete and a repeated item
Cancel callback popping the underlying task route. Both are fixed through
origin-scoped failure handling and one-shot/current-route decision guards.
Captured task-menu callbacks now carry the original workspace, just like child
commands and typed drag payloads. A refreshed changed checklist blocks movement
before any receipt is prepared; changed-parent consent blocks deletion.

- Analysis: no issues. Focused checks: 36 pass.
- Extended native host: 3 pass, including desktop dark and 390px/200% light,
  right-click/keyboard menus, two-selected-row single Delete/Undo, stale parent
  consent, repeated item decision, local expansion and no-write display actions.
- Actual workspace switching: 1 pass with matching parent/item IDs in two spaces;
  all six captured callbacks are rejected, both canonical byte sets unchanged,
  and first-space expansion restores on return.
- Migrated native checklist workflows: 2 pass, preserving desktop sidebar and
  narrow modal parent/item draft isolation, renewed warnings and recurrence.
- Existing lifecycle/completion run: 7 item lifecycle and 5 completion cases pass.
  Its raw log retains two obsolete checkbox-selector failures; those were fixed
  by scoping the parent tile and the two workflows separately passed. The mixed
  raw log is deliberately not labeled an all-green run.

Architecture and correctness independently accept the concrete executable
commit with no remaining must-fix. Hosted CI is
[37860886439](https://github.com/reddraggone9/tandemlog/actions/runs/37860886439)
at that exact source. Android build/native payload checks and Windows automated
unit/build/installed lifecycle checks were last observed green; composed Linux
native CI was still running when this packet was written. Terminal verification
and bounded Android affected-flow acceptance remain separate.

## Actual GTK visual evidence

All captures here are real Linux GTK production-main pixels on synthetic data.
[Before](before-editor.png) is a local release build of rc.4 source: items live
inside the parent editor. [After](after-inline.png) is the local debug build of
this feature: items live under parents in the list. Both are dark, 1200×850,
normal text, and show the same synthetic six-item parent. After also shows a
library-card item on another parent. The captures come from different points
in the synthetic demo, so their full histories differ. This is a source UI
comparison, not signed-installer acceptance.

The actual [menu](dark-menu.png) shows menu/drag separation and labels;
[empty expansion](dark-empty-focused.png) shows focused bottom Add item;
[completion consent](dark-consent.png) shows no header pending-write indicator.
The supplied [pointer frame](demo-pointer-frame.png) verifies visible inputs in
the 35.8-second desktop video delivered with the review packet. Three recordings
from the same native session were concatenated without changing app pixels.
The video demonstrates menu activation, empty expansion, independent item Save,
checking, child drag reorder, Undo and warning Cancel.

Light GTK captures cover [390px normal](light-narrow-normal.png),
[1200px at 200%](light-desktop-200.png), [390px at 200%](light-narrow-200.png) and
[reachable bottom controls](light-narrow-bottom-200.png). The enlarged captures
use an isolated desktop Settings-portal QA adapter with the unmodified app
binary. Flutter's runtime widget tree reports `SystemTextScaler (2.0x)` in
[native-text-scale.json](native-text-scale.json). Initial GSettings-only attempts
remained at normal scale and are excluded from enlarged evidence. Independent
visual review inspected all eight affected captures: readable titles/notes,
separate controls, wrapping without overlap and reachable bottom Add; no clear
reversible defect found. These are Linux narrow layouts, not Android evidence.

Original fixture files remained byte-identical. The synthetic demonstration
added nine expected canonical records: two captures and their initial rank
moves, one item creation, check/Undo and item move/Undo. No parent completion
record was written. Hashes and source bindings are in verification.json.

## Android follow-up and publication boundary

Use the source-bound `android` artifact from the CI run in a dedicated synthetic
profile/tree; never use live synced data. Verify the artifact before installation.
At normal and enlarged text, check task-menu versus parent-drag separation,
collapsed counts, empty Add-checklist focus/no-write behavior, title/notes
Save/Cancel, checkbox and within-parent movement, confirmed item Delete/Undo,
parent Delete amid multiple selection, completion warning Cancel with no header
progress, actual completion feedback, draft/IME ownership and restart expansion.
Retain an Android Show-taps demo and affected-flow receipts. Existing native
history/recurrence/Undo tests remain applicable; do not add a new broad matrix.

Windows uses Lee's authorized automated RC acceptance exception. Preview delivery
still needs versioned signed candidate/exact-artifact/native acceptance, fresh
quota and separate review of actual notes/media against the final commit range.
Stable feature promotion needs Lee's acceptance. Broader local-storage
consolidation remains queued for the next full release with inventory/migration
review; it is not implemented here.
