# Batch selection: Tasks and Food

Status: local development implementation on `vex/next-foodbatch` for the next
release; not native-accepted or released. Behavior is specified in
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
  equivalent need. It now includes shown Deleted rows.

Views that allow selection:
- Tasks: open views, Completed and Search. Food: Stock with Inbox, Retained,
  Search and now Deleted (fixed). Deleted tasks are not viewable, so there is no
  Task equivalent to Deleted.

Selection affordances:
- Both highlight selected rows and swap the selected count, Clear Selection and
  Edit into the shared entry area on narrow layouts.
- Checkbox column: Food shows a tristate checkbox per row while selecting; Tasks
  deliberately has none. Deliberate: a Food row is a group of physical
  containers, and a matching arrival makes it partially selected, which the
  tristate box shows.
- Wide layouts: Tasks opens the bulk editor in the side pane as soon as a
  selection exists; Food kept a modal bulk editor opened from Edit. Resolved
  (Lee, 2026-10-27, on `vex/food-products`): at pane widths a Food selection
  opens the bulk editor in the side pane, changing the selection first resolves
  an unsaved bulk draft, Clear Selection closes the pane, and narrowing a
  selection of two or more rows to one whole row returns to that row's single
  editor, as on Tasks. Narrow widths keep Edit → dialog.

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
- Both exit on Clear Selection, on deselecting the last row and after a bulk
  command; neither uses Escape for selection. Consistent.
- Food clears selection when the view, filter or search changes; Tasks keeps the
  selection while Search and Filter are used and drops rows that become hidden.
  Open question: should Food keep a selection across search/filter changes like
  Tasks? It predates this audit and nothing reported depends on it.

Undo:
- Every bulk command is one Undo action in both sections: Task bulk edit/delete/
  reorder, and Food bulk Save, Remove and Restore. Consistent.
  `food_bulk_edit_fields_test` proves one Undo restores every selected container
  for a five-field edit, and that the edited and undone states replay identically
  in a reopened and a fresh profile. Undo history itself is session-local
  (ADR0018), so it does not survive a restart by design.

## Compatibility and performance

No record, schema or Undo meaning changes: a bulk edit is the existing Food edit
operation with an explicit field list, already able to carry name, brand, size,
location and retention per container. Bulk Remove/Restore reuse the existing
remove and restore-batch commands. The `food.details.3` benchmark now measures
and asserts the full five-field edit the editor can send; its limits are
unchanged, and no new benchmark label is needed.
