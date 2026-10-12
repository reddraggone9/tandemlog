# Build 69 review closure

The handoff fix keeps Tasks editor content and actions reachable at 320dp and 200% text when a folder chooser launch fails. The follow-up uses one width-aware modal predicate for the host diagnostic and editor, including promotion of a selected wide editor. This prevents a duplicated diagnostic in the first narrow frame without losing the draft, composition, text session or guarded Save.

The new resize regression failed in both themes before the production closure (two diagnostic scrollables instead of one). All six native GTK cases and 44 focused editor unit cases pass afterward; analysis is clean. The regression measures the live nested EditableText after responsive reparenting. It preserves the TaskEditor state and controller while checking the end caret and each action above the simulated IME. Existing error cases explicitly scroll the inner diagnostic and check every box of the final `Try again.` text is visible.

Visual review of actual GTK captures confirms the enlarged title caret, wrapped actions and fully readable error. These captures use Android Material overrides and a simulated IME; actual signed Android acceptance remains a separate gate. The change does not alter storage, importer code, dependencies, folder-picker behavior or release signing. The prior review's two remaining findings are closed by focused assertions; broader unchanged build 68 results retain their original attribution.

The release-note addition describes only the visible fixes. No publication or live Food cutover is authorized here. Private native evidence and logs are retained outside the source tree.
