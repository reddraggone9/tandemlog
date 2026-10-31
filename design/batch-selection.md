# Batch selection: Tasks and Food

Status: shared Tasks/Food rules, with selection-retention follow-ups in local
development on `vex/food-products`; those follow-ups are not released. Behavior is specified in
[product behavior](product-behavior.md#approved-rc3-food-editing-refinements);
this document records the 2026-10-27 consistency audit and its outcomes.

## Why

Lee reported on 2026-10-27 that long press and Ctrl+click on deleted Food rows did
not start batch editing, and that Ctrl+click did nothing on regular Food rows
either. He also asked for a Tasks/Food batch-selection consistency audit and for
bulk Food editing of every field except expiration, so that containers of one
product entered in different ways can be unified. Tasks and Food share
components rather than drifting apart.

## Root causes

- Ctrl/Cmd-click on any Food row: RC.5 (`v2026.10.7-rc.5`) had no modifier
  handling on Food rows at all; a Ctrl+click opened the editor. Commit `1b27183`
  added it after RC.5. A real-gesture test (`food_batch_selection_test`, held
  Control/Meta key plus mouse tap on Linux, macOS and Windows targets) fails on
  RC.5 source and passes now.
- Deleted rows: `food_page.dart` excluded deleted groups from every selection
  route (long press, Ctrl-click, Space, menu, semantics action and visible-ID
  pruning), as the earlier specification required ("Bulk selection remains
  active-only"). `food_selection_deleted_edit_test` passed because it long-presses
  only an active row; its deleted half taps a deleted row to edit it. The
  coverage note "verifies gesture" referred to that active long press.

## Audit outcomes

Each difference found between Tasks and Food is listed as fixed, deliberate (with
the reason) or an open question for Lee.

Entry gestures:
- Long press, Ctrl/Cmd-click, Space and the Select actions on Deleted Food rows:
  fixed. Every Food row is selectable, as every visible Task row is.
- Shift-click range: Tasks only. Fixed; both pages now compute selection with
  the shared `presentation/list_selection.dart` rules, so Shift-click selects the
  visible rows between the anchor and the clicked row in Food as well.
- Ctrl-click while the wide pane edits one item: Tasks selects the edited task
  and the clicked one; Food left the single-group editor open and selected only
  the clicked group. Fixed; Food now starts with the edited group after the usual
  unsaved-draft decision.
- Shift+Arrow range: Tasks only, because Food rows had no arrow-key row
  navigation at all. Resolved (Lee, 2026-10-27, on `vex/food-products`): Up/Down
  move focus between Food rows and Shift+Up/Down extend the selection from its
  anchor (the focused row when there is none), using the shared rules.
- Filter → Select matching containers: Food only. Deliberate: Food's unification
  workflow filters by Brand/Location and selects the result; Tasks has no
  equivalent need. It includes shown Deleted rows and resolves an existing dirty
  editor before changing targets (Keep editing leaves its draft/selection intact;
  Discard opens the matching single/bulk editor at wide widths).

Views that allow selection:
- Tasks: open views, Completed and Search. Food: Stock with Inbox, Retained,
  Search and now Deleted (fixed). Deleted tasks are not viewable, so there is no
  Task equivalent to Deleted.

Selection affordances:
- Both highlight selected rows and swap the selected count, Clear Selection and
  Edit into the shared entry area on narrow layouts.
- Checkbox column: removed (Lee, 2026-10-29). Food used a tristate checkbox per
  row because selection held exact container IDs, so an arrival left a row
  partially selected. Food selection is now row-level like Tasks (see
  [Row-level Food selection](#row-level-food-selection-lee-2026-10-29)), so no
  partial state exists and neither section has a checkbox column.
- Wide layouts: Tasks opens the bulk editor in the side pane as soon as a
  selection exists; Food kept a modal bulk editor opened from Edit. Resolved
  (Lee, 2026-10-27, on `vex/food-products`): at pane widths a Food selection
  opens the editor immediately in the side pane (one whole row uses its single
  editor; multiple rows use the bulk editor). Changing selection first resolves
  an unsaved draft. Search remains visible, with no redundant count/Clear/Edit
  bar; the shared `TaskEntryArea` owns this window-width/editor condition for
  both sections. Narrow widths keep the shared count/Clear/Edit bar in place of
  Search and wait for Edit → dialog. Widening an existing selection reveals the
  pane; an open dialog becomes a pane and an open pane becomes a dialog when
  the window crosses 900 logical pixels. Narrowing a selection of two or more
  rows to one whole row returns to that row's ordinary single editor.

Bulk actions:
- Delete/Remove: Tasks offers Delete in the bulk editor opposite Cancel/Save;
  Food had no bulk Remove. Fixed: the Food bulk editor offers Remove (confirmed)
  for selected active containers and Restore for selected deleted ones, each one
  host command.
- Field pattern: Tasks uses an inline Apply checkbox per field, applies a field
  when edited, clears it when applied blank and marks disagreeing fields Mixed;
  Food used separate Apply rows plus Clear buttons. Fixed with the shared
  `presentation/bulk_apply.dart` control and Mixed hint.
- Fields offered: Tasks excludes title and notes (per-item collaborative text);
  Food now offers every descriptive field except Expiration. Deliberate: each
  follows its own goal (Food unifies one product's entries; expiration stays per
  container, as Lee specified).
- Reorder: Tasks only. Deliberate: Food is ordered by expiration, not by hand.

Exit:
- Both exit on Clear Selection, deselecting the last row, closing an editor
  (after resolving any dirty draft), and after a bulk command. Escape clears a
  selection in both (Tasks' existing shortcut; Food since 2026-10-29), resolving
  an open editor's draft first; without a selection it dismisses an open editor,
  following its normal draft guard.
- Item (l) shares `retainVisibleListSelection` for **view recomputation**:
  retain visible rows (task IDs; Food row identities), drop hidden ones, always
  forget hidden range anchors, and preserve the captured selection while an
  editor is open. Pruning to zero visible IDs
  does not exit explicit selecting mode; expanding the view does not resurrect
  IDs already pruned. This did not change Tasks' input/filter handlers.
- Native audit of `5721659` (2026-10-28): Tasks' search-input and Clear search
  handlers close the guarded editor and clear selection, even when all selected
  rows still match. Food now follows that behavior; Cancel on the dirty-draft
  prompt restores the previous query and keeps the selection/draft. Tasks'
  behavior is unchanged; only its entry-area condition moved into the shared
  component. At 5721659 Food already auto-opened the wide bulk pane, but still
  covered Search with the compact bar and kept selection on editor Cancel.
- **Question for Lee:** item (l)'s retention intent and Tasks' explicit search /
  filter handlers disagree. Should both retain visible selected IDs through
  those input changes? Recommendation: a separately approved follow-up making
  both retain visible IDs after resolving any dirty draft. This change keeps
  Tasks as the reference, including search clearing selection. Food view-menu /
  More-filters retain the already-approved shared recomputation policy; Tasks'
  own filter controls still explicitly clear. No silent Tasks behavior change.

Undo:
- Every bulk command is one Undo action in both sections: Task bulk edit/delete/
  reorder, and Food bulk Save, Remove and Restore. Consistent.
  `food_bulk_edit_fields_test` proves one Undo restores every selected container
  for a five-field edit, and that the edited and undone states replay identically
  in a reopened and a fresh profile. Undo history itself is session-local
  (ADR0018), so it does not survive a restart by design.

## Row-level Food selection (Lee, 2026-10-29)

Lee: "Food selection = row-level, like Tasks: remove selection checkboxes (no
column shift); a selected row means all containers currently in it, so a
container that joins a selected group is included and no partial state/'3 of 4'
display exists; the bulk editor shows the live container count. Add 'Move some…'
to the Food row ⋮ menu."

- Goal: selecting a Food row means "this food", not a snapshot of container IDs,
  and splitting a row takes one action.
- Method: the page's selection holds row identities (`FoodGroup.rowKey`:
  product, description, expiration, retention, location and deletion status,
  the same identity rows are grouped by). `FoodState.rows` resolves each to its
  current containers whenever they are used: the compact count, the editor
  title, Save, Remove and Restore. The shared `nextListSelection` rules run with
  one member per row, so gestures, ranges and two-to-one behavior are unchanged.
  One selected row opens its single editor, which also follows the row; a
  plain-click edit keeps its observed containers, as before. A pending-save
  retry reuses the containers its first attempt sent (exact host retry).
- A row whose containers all left contributes nothing; a selected row that is
  still populated but newly hidden is refused, as hidden IDs were.
- Rejected: keeping exact IDs and auto-adding arrivals (still needs a partial
  state when containers leave), and keeping the checkbox without tristate (still
  shifts the row when selection starts).
- Move some… (row ⋮ and secondary click, active rows with two or more
  containers): how many, 1 to the current count, and a new Location. It is the
  existing Location `changeDetails` over that many current containers, so the
  canonical format, storage semantics and Undo (one action) are unchanged.
  Allowing the full count avoids an error for "move all of them", which is the
  same as editing the row.

## Responsive regression coverage

`test/selection_layout_parity_test.dart` runs both sections at 390, 899, 900 and
1400 logical pixels, including single/multi selection, last-row deselection,
Search/Clear draft guards, narrow Edit/Cancel, resizing and guarded Select
matching. `integration_test/selection_layout_parity_workflow_test.dart` repeats
these workflows on native Linux and is registered in the main native CI suite.

## Compatibility and performance

No record, schema or Undo meaning changes: row-level selection only changes
which containers the page sends, and Move some is an ordinary Location edit,
registered as `food.moveSome`/`.undo` (see
[performance gate](performance-gate.md#food-move-some-prospective-coverage-2026-10-29)).
A bulk edit is the existing Food edit
operation with an explicit field list, already able to carry name, brand, size,
location and retention per container. Bulk Remove/Restore reuse the existing
remove and restore-batch commands. The `food.details.3` benchmark now measures
and asserts the full five-field edit the editor can send; its limits are
unchanged, and no new benchmark label is needed.

### Completion and stale selection (Lee 2026-10-30)

A successfully completed Task leaves the selection, like a deleted Task; other selected rows remain. The last completion ends selection mode. An undisplayed selection editor is released first, so its completed-task snapshot cannot become a modal when selection ends. A subsequent selection gesture drops any hidden IDs before applying the gesture, even if an editor retained a snapshot. Existing post-editor visibility guards still refuse changed or invisible bulk targets. Food already intersects new gestures with its current visible row keys.

Keyboard Up/Down reveal the complete target row, including at 320dp and 200%
text. Full-width pinned heading paint must not distort row reveal coordinates;
Tasks and the matching Deleted section in Food Search share this requirement.
