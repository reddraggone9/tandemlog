# Inline checklist component

Implementation source `e59782f7260f6364c94807de3ee79662fd41adaf`, based on
`44344407200b61d38d7b33f22c0ace715376fd6f`, on isolated branch
`feature/inline-checklist-panel`.

The reusable panel has bottom Add item, editable titles, a one-line optional
notes preview, native checkboxes, direct Delete icons and explicit drag handles.
Each item control retains a 48px target. The parent host owns its count and
delete confirmation. Child keyboard moves use Alt+Up/Down; accessible Move up
and Move down custom actions preserve edge restrictions.

Required constructor inputs are `parentId`, identity-scoped `origin`, and opaque
value-equal `revision`; `addFocusNode` is an optional host-owned hook. The distinct
`ChecklistItemDrag` payload carries an immutable observed order. Acceptance
checks current parent, origin, revision, order, membership, enabled state and
no-op edges both on pointer entry and immediately before the callback. All row
handles share one immutable snapshot. Native checkbox focus survives busy state;
live guards reject repeated Space and cached control callbacks while semantics
truthfully remove disabled actions. Direct controls and handle taps/drags are
tested under an ancestor parent selection/String-drag detector.

Frozen reds cover obsolete layout/focus, missing drag/keyboard controls, late
busy callbacks and handle-tap parent selection. Final focused validation:
**17 tests passed**, including the preserved item-editor gates; targeted
panel/test analyzer reports no issues. Receipts and source/file hashes are in
`manifest.json` and the adjacent logs.

These inspected dark-theme images are **Flutter widget-renderer captures**:
[900×700, normal text](widget-renders/dark-desktop-inline-panel.png) and
[360×640, 200% text](widget-renders/dark-narrow-enlarged-panel.png). Titles wrap,
notes retain one line with ellipsis, controls remain reachable, and no overflow
was observed. Native GTK host workflow/video, Android/Windows and native
assistive technology acceptance remain on the integrated host. The isolated
branch's untouched main constructor awaits host wiring; whole-app build/analyze
is not claimed. Domain/storage, native text, TaskEditor and release inputs are
unchanged by this component work.
