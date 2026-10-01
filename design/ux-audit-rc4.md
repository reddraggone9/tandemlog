# RC4 task-based UX audit

Scope and rationale: [decision 0004](decisions/0004-editing-bulk-actions-and-installers.md).

Pre-native review fixed missing live title/notes limits (500/10,000), hidden draft occurrence overrides after Repeat removal, and narrow enlarged-text action overflows. Bulk partial writes require reconciliation before retry. Cloud Flatpak execution is blocked by read-only user-namespace mappings; hosted installation is a required gate.

Host integration review found reused editor keys could retain another task's frozen draft if close/open happened before the next frame. Each opening now has a fresh key, stable during that session's resize. Single writes/deletion compare a frozen semantic target baseline, allowing unrelated task updates while preserving a changed target draft for explicit review. Stale bulk selections cannot silently advance their retry snapshot; only reconciled own partial writes may resume.

The cloud worker's authorized pixel download failed. The coordinating parent inspected the actual reference and supplied its wrapping inline-chip/query structure, clear/expand controls and directly adjacent suggestions. Native output follows that guidance; no cloud inspection of the reference pixels is claimed.

Required workflows: five-task capture; multi-tag selection/chip removal/reset/search restoration; wide/narrow dirty editing/resize/failure; identity/filter changes; explicit mixed-field bulk patches; confirmed/canceled deletion; equal-key bulk edge dragging with hidden ranks; rejected cross-key/cross-completion/stale drops without events. Inspect Light/Dark, long labels, narrow/enlarged text, keyboard focus, scroll bounds and touch targets using synthetic fixtures. New exact-APK Android acceptance is required; RC3 evidence is separate.

## Native integration observations

The initial Light/Dark Linux flow passed in 43 seconds with a 1200px desktop and 390px resized modal: inline any-tag selection, retained draft across resize, fresh task A-to-B save, bulk tag application and canceled/confirmed deletion. Eight synthetic screenshots were independently inspected. Chip insertion initially replaced the query's unkeyed input slot and broke subsequent typing; a stable slot key/owned focus fixes it. The query now shares the field background; full-chip width is bounded for long labels. Incoming-conflict/bulk-drag/enlarged-text and full hosted acceptance remain in progress.

Editors managed by the host route now delegate Back handling to the host's single guard. Standalone editors retain their own PopScope. The revised regression verifies one Save/Discard/Cancel prompt; invalid or failed Save retains the current frozen draft and selection.

The complete native Linux suite passed 17 workflows in 274 seconds, including selected-block stationary edge scrolling, hidden ranks, cancellation and mixed-key rejection. Final review found a clipped first floating label (6px scroll-content padding fixes it) and a prior drag-cancel snackbar intercepting Save. Opening an editor dismisses stale transients; the affected save flow passed again in 21 seconds. Twelve Light/Dark screenshots cover desktop, 390px modal and 200% text scale. The reviewed 45-second native Linux demo has visible pointer input. Final analysis and 137 application unit tests passed. Exact Android and hosted installer acceptance remain pending.

The compact header keeps title/count inline, identity/Settings in the top bar and all filter choices in one scrollable surface. Native tests cover composition, reopening, reset without identity change, keyboard navigation and unchanged header geometry between status choices at 320–1000px and up to 250% text. Partial-write error text distinguishes confirmed refreshed deletion from uncertain move acknowledgements so users can review the current list before another action.

Owner review of the first demo identified a missed interaction requirement: tag suggestions were in the dialog layout and searching resized it. Chip/multiselect behavior was accepted, but this demo is not final acceptance. Replace results with a true anchored overlay and verify unchanged dialog geometry across open/closed, several/one/empty results, with bounded scrolling, focus/dismissal and viewport/keyboard positioning. No reserved in-flow result spacer.

Lee subsequently requested row-based selection instead of the selection button/second checkbox column, automatic wide editor transitions, and contextual count/Clear. Explicit one-item intent differs from ordinary single editing; two-to-one and zero transitions must be tested. Verify modifier/long-press/range/keyboard selection, cross-group edit selection with constrained drag, separate completion/handle gestures, invalidated anchors and dirty Save/Discard/Cancel failures. The first demo is superseded; refreshed native desktop and exact Android acceptance are required for this revised interaction.
