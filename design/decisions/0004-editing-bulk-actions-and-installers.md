# Decision 0004 — editing, bulk actions and desktop installers

Status: accepted RC4 scope, 2026-10-01. Acceptance: [status](../status.md), [UX audit](../ux-audit-rc4.md).

Lee requested multi-tag filtering, direct editing without task overflow menus, a wide side editor, bulk actions and desktop installers. These extend the [compact interface](0002-onboarding-and-everyday-interface.md) and retain [date/manual ordering](0003-task-parity-and-prerelease-boundary.md).

## Interaction

Selected tags match **any** selected tag, intersecting with assignee/completion/upcoming filters. Removable chips and the query share one field. Suggestions float in an anchored, bounded, scrollable dropdown: opening, closing, querying and empty results must not resize the Filter dialog. Chip wrapping may naturally change the field height. Keep the dropdown within the viewport/keyboard bounds, with outside-click, Escape and focus behavior. Lee rejected an in-flow result list after the demo because searching moved the dialog. Search pauses/restores filters. No general query framework.

Rows open editors directly; identity/Settings stays in the top bar. Wide layouts keep the list beside the editor; smaller layouts use a modal. Protect dirty drafts on close, task/user/workspace/filter changes and responsive transitions. Drafts are in-session, not termination-durable. Validate changed inputs immediately without pristine errors. Schedule order: Start, Due, Repeat/This occurrence, Time zone, Sort bounds. Hide irrelevant occurrence controls but preserve contextual access to existing/draft nonrecurring overrides.

Lee rejected the explicit selection button and second checkbox column in the first demo. Completion remains its own checkbox; selection uses a distinct row highlight/selected semantics. Ordinary clicks edit one task and switch that single target. Ctrl/Cmd-click or a won body long-press enters explicit selection; plain clicks then toggle membership. An initial explicit one-item selection retains that intent so touch users can add another item. An actual reduction from two items to one returns ordinary single editing; zero closes the pane. Wide selection opens its editor automatically, with count/Clear in the pane and deletion only in the editor. Narrow selection retains minimal contextual access to the modal. Shift ranges follow the current visible order, including different date groups for editing; dragging remains limited to one exact sort bucket. Reset an invalidated range anchor without silently omitting selected tasks. Keep keyboard focus distinct from selection, with keyboard/accessible selection actions and Escape/Clear. Outside clicks do not silently exit bulk intent.

Changing targets/selection must resolve the frozen current draft through Save/Discard/Cancel. Save validates and writes that old selection before transition; a validation, stale-state or storage failure retains the draft and selection. Do not apply a prior bulk draft to the new target set. Completion controls and drag handles never enter row selection. Commit selection only after a gesture wins, not from preliminary pointer callbacks. These choices reduce competing controls while preserving deliberate bulk intent. [Flutter gesture handling](https://api.flutter.dev/flutter/widgets/GestureDetector-class.html), [selection-mode guidance](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/selection-modes) and [focus/selection guidance](https://www.w3.org/WAI/ARIA/apg/patterns/listbox/) inform implementation; interactive completion controls are not treated as bare listbox options.

The bulk header uses “Edit N tasks” and “Clear Selection” on the same line when they fit, with a spaced wrap at narrow widths or enlarged text. A second “N selected” count and the checkbox explanation were removed at Lee's request: the heading already identifies the selection and the form controls express which fields apply. The existing dirty-draft guard still runs before Clear Selection. This follow-up changes layout/copy only. The header-only change did not enable broader Undo; accepted RC5 [decision 0005](0005-session-undo-and-toolbar.md) supersedes that limitation.

Bulk editing excludes titles/descriptions. Preserve mixed values unless explicitly applied; an applied blank clears. Tag deltas preserve unrelated membership and unseen additions. Validate every resulting schedule before the first append. Deletion is confirmed; RC5 session Undo can retract that tombstone; a recurring successor remains independent.

Bulk drag preserves selected tasks' global relative order and hidden ranks within one completion section and exact effective date/time bucket. Show invalid destinations during dragging, retain edge scrolling and revalidate on incoming/time/filter changes. No implicit date changes or unrestricted manual-sort mode.

## Persistence

Bulk writes are independently durable per task, not one transaction. Prevalidate the selection, report partial progress and reconcile uncertain appends before retry. Retain the remaining draft. Expected snapshots prevent silent overwrites of changed state.

Protocol v2/cache 7 remain. Additive `task.deleted` and assignee edits read RC3 input, but RC3 rejects these new records/fields explicitly. Update every writer before using RC4 actions; never remove records for an old reader. Tombstones remain canonical history.

## Distribution and alternatives

Use Linux Flatpak and an unsigned per-user Windows installer instead of loose archives. Retain identity, Android signer, native profile and sync-folder path. Flatpak grants rendering/IPC and specific native profile paths, not home/host/network. Custom folders require scoped access. Windows uninstall removes program files/shortcuts, retaining data.

Hosted gates install/launch/replace/uninstall/reinstall exact candidates with synthetic data. They complement Linux visual QA and exact-APK Android acceptance; manual Windows and provider coverage remain separate. [Packaging commands/limits](../../packaging/README.md) disclose prerequisites. No Store/Flathub publication, paid runner or new credentials.

Rejected for now: universal filtering, unrestricted date drag, replacing untouched mixed fields, deleting a recurrence series through one occurrence, and automatically discarding drafts. Revisit after concrete hands-on friction.

## First stable follow-up — title/notes sizing and due precision

Status: approved by Lee after first stable 2026.10.0; implemented for the next preview.

Timed effective values sort before date-only tasks on their shared calendar day. This matches the useful distinction between a specific appointment/deadline and a task due sometime that day. Keep scheduled-over-due precedence and pinned conversion, bound-day clamping, group keys and shared manual ranks. Derive ordering from explicit precision rather than storing a fake end-of-day timestamp. Exact midnight cannot share a drag/move bucket with date-only intent. A date-only scheduled override stays date-only even if the underlying due schedule has a time; reversing override precedence was not requested.

The editor starts titles at one visual line, grows to two and scrolls beyond that. Input line breaks normalize to spaces with selection preserved; active IME candidates are left alone and changed composing titles cannot be saved. Notes grow from three lines, then scroll within a cap derived from available editor height, including the keyboard. Existing fixed three-line notes wasted room while requiring unnecessary scrolling; unbounded notes could push other fields and actions out of reach.

After an editor geometry change, reveal the focused caret once after layout without changing text, selection or composition. Native inspection found that a runtime text-size increase could otherwise leave it outside the notes viewport. Do not reveal on every rebuild: theme changes or incoming task updates must preserve the user's deliberate scroll position.

These are view/input changes. Decoders and v3 canonical bytes remain unchanged. Historical multiline titles stay readable, opening/focus is clean, and notes-only saves omit title entirely. Deliberately editing a historical title uses the current one-line input rule, without rewriting older records. No source import, live data modification or stable binary replacement is part of this follow-up.
