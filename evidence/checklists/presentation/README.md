# Checklist presentation component gates

Scope: reusable panel, item dialog and public title input formatter on isolated
`feature/checklist-presentation`, based on core `f579c4f`. Host integration,
completion warnings, task editor composition, storage and domain are outside this
component change.

`21d056d` freezes nine behavior/formatter gates and one actual-native editor gate
against empty component API stubs. Both original red logs remain unchanged.
`54b56a6` freezes the independently found private-preparation close regression:
two actual stores exchange a parent deletion after capture; native Save prepares
the private item draft and rejects before receipt; the old guard then prevents
the Discard dialog. The regression is red before the narrow guard fix. Synthetic
store fixtures are retained; these tests never open live profiles.

Final focused run: **14 pass**, including reopened/repeated/dismissed draft guards,
route back/Cancel, command-in-flight freezing, exact pending-receipt retry,
multiline notes and IME/length validation, actual native remote merge/renewal,
caret-only clean state, remote deletion rejection/Discard and canonical byte
preservation. `test-green.txt` and scoped `analyze.txt` contain final results.
Fixture corrections retain the original reds: use `event.id` for native receipts,
physical pixels for simulated keyboard insets, and dispose semantics handles
before the widget test's verification phase.

## Public API and ownership

- `ChecklistPanel`: ordered `items`; `onAdd`, `onEdit(item)`,
  `onToggle(item, completed)`, `onMove(item, beforeId)` and `onDelete(item)`;
  `enabled` defaults true. Up/down use the ordered snapshot's relative anchor;
  edge moves are disabled. Notes remain fully readable. Item actions explicitly
  save separately from task edits.
- `ChecklistItemEditor`: optional initial `item`, optional host-owned
  `TaskTextSession`, required `save(title, notes)`, optional callback
  `hasPendingReceipt`, optional `onClose`. Its public state `canClose()` resolves
  a private draft and never pops the host. Internal Cancel/back closes only after
  the guard accepts. Dirty Discard does not mutate or cancel the native session.
- Fields freeze for busy/native preparation/receipt. Close/Discard blocks only
  busy or pending durable receipt. The host must await dialog route completion
  before cancelling/releasing the session. Save errors preserve private text;
  retry keeps prepared intent; successful native Save refreshes merged draft text
  before close and renews the clean baseline.
- `TitleLineFormatter` preserves the existing task formatter's exact behavior:
  no historical normalization on selection-only changes, no IME interference,
  replacement of CRLF/newline/Unicode line breaks with spaces, mapped selection.
  Root integration owns replacing the old private task formatter.

## Rendered inspection and limits

Actual widget-renderer PNGs in `images/` were inspected at dark desktop 900×700
and narrow 360×640 with 200% text, including a simulated 220 logical-pixel
keyboard. Readable Roboto/MaterialIcons came from the already installed Flutter
SDK. The first Ahem-font layout captures were insufficient for copy review; the
retained images use readable fonts. Inspection shortened visible field labels
to Title / Notes (optional), while preserving full field-specific accessibility
labels, and reduced the bounded notes viewport so narrow enlarged actions fit.
Long notes scroll inside the field; the dialog body scrolls when needed. Panel
checkbox/menu targets are 48×48 and checkbox semantics expose a toggle action.

Reproduce with the environment sourced, offline locked pub get, then:

```sh
TANDEMLOG_TEXT_LIBRARY=/workspace/toolchains/shared-history-native/libtandemlog_text.so \
  flutter test --no-pub test/checklist_presentation_test.dart \
  test/checklist_item_native_editor_test.dart
```

Optional rendering uses `CHECKLIST_VISUAL_DIR` and `CHECKLIST_FONT_DIR` (the
installed SDK `bin/cache/artifacts/material_fonts` directory). Without them,
tests still execute; no fonts, packages or native binaries are added to the app.

These are component widget images and Linux native text-library tests, **not**
native desktop/Android app acceptance or demo videos. Independent component/host
review, integrated persistence/Undo/completion flows, actual Linux and Android
keyboard/pointer workflows, both themes and demonstrations remain parent gates.
No release or stable promotion is claimed.
