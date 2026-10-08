# Product behavior and milestones

## Accepted direction

Settings shows the release version compiled into the running app, with a copy
action. Display/copy excludes the platform build counter. The row sits near the
bottom of Settings rather than occupying the task list; missing metadata or a
clipboard failure receives a contextual response. This is presentation-only.

Start and Due each pair a wider date control with a smaller always-visible
input labeled **Time**. A blank time retains date-only precision; focusing it
does not invent a value. The existing X clears time and retains its date.
Controls stack when width or larger text requires it. Tags and Assignee follow
all scheduling content, before actions, in single and bulk editors. [Layout rationale](decisions/0009-date-and-optional-time-rows.md).

Offline household task management first. Windows and Android are the first intended user platforms. Future modules include games, food logging, inventory, and assisted input. Time tracking is undecided and excluded.

The first slice is folder/user selection, capture, edit, complete, undo, persistence, and convergence tests. Recurrence, reminders, deletion, advanced dates, floating priorities, manual shared sorting, and other modules are outside this slice.

## Platform verification milestone M0 — remove platform uncertainty

With Flutter and provider-independent folder sync approved, use dedicated disposable test folders and the implemented platform adapter to prove Android tree selection and retained access; two-way file transport with a selected wrapper; replacement/reopen; reboot and process death; and no-internet hotspot behavior on the intended phones. Also launch a minimal Windows build and verify text input, folder selection and packaging prerequisites. Record versions and results. M1 implementation proceeds in parallel, but this remains a release acceptance gate. Failure prompts a product/transport decision, not an automatic broad-storage permission workaround.

## Completed initial milestone M1 — persistent shared tasks

- Choose/create a supported workspace namespace in an authorized folder. Detect existing workspaces and incompatible formats. Do not mutate unrelated files. Distinguish “saved locally” from transport status; never imply other devices received a change without evidence.
- Create/select a stable user ID and display name; allow switching users. This is attribution, not authentication. Default new task assignment to the active user; retain an all-tasks view.
- Capture a title rapidly; edit title and optional description. Completion removes the task from the active list. Offer immediate undo of that completion, targeting the completion operation so it cannot undo someone else's later action blindly.
- Keep initial ordering stable and simple (creation order with ID tie-break). Do not implement date sorting without date semantics. Avoid a generic database editor or future-module navigation placeholders.
- Persist acknowledged changes through restart. Never report a failed write as saved. Recover from a log write followed by cache failure without duplicating the command.
- Import two independent devices' edits, including duplicate and out-of-order delivery, and show the same materialized state after the same event set is available. Document the chosen per-field conflict rule. Rebuilding the cache must produce the same result.

The initial protocol covered this slice; the current [protocol](schema.md) extends it for M2. Do not revive the removed generic field-change draft.

## Acceptance evidence

Core tests cover shuffled delivery, duplicate completion/undo, different-field versus same-field edits, missing dependencies, restart, cache removal, truncated tail, file replacement, write failures and incompatible versions. Target acceptance still requires the two-device offline/edit/reconnect/restart script in [runtime QA](runtime-qa.md); local folder-copy tests are not phone transport verification.

For UI changes run and visually inspect capture/edit/complete/undo plus empty/error states and keyboard/touch layout. Include desktop and Android videos when those runtimes work. Native acceptance remains pending when only browser results exist; see [runtime QA](runtime-qa.md).

## Onboarding and everyday interaction

Follow [decision 0002](decisions/0002-onboarding-and-everyday-interface.md): explicit desktop Start with a default folder, secondary existing-folder choice, unchanged Android SAF selection, inline first user, local System/Light/Dark preference, compact filtered task count and automatic foreground imports. Workspace switching and opening are settings actions. No permanent refresh control or explanatory sync footer. Preserve capture/edit buffers and selection through incoming updates. Desktop Enter submits and Shift+Enter inserts another task line; Android Enter is a newline. Hardware Enter must leave active IME composition to candidate selection. Deliberate Add and supported keyboard submit actions finalize the visible composition and submit once. Failed capture retains unconfirmed content.

New desktop setup names the canonical folder `shared-data` under the existing application-support root (`%APPDATA%\com.reddraggone9\tandemlog\shared-data` on Windows; normally `~/.local/share/com.reddraggone9.tandemlog/shared-data` on Linux). Sync only that chosen canonical folder, never its private parent. Saved selections are retained, with no automatic move or empty replacement. The earlier populated `data` default remains available after a settings reset as described in decision 0002. Android still selects an external sync-compatible SAF folder.

The explicit capture control uses a plus icon: **+ Add** when the entry has room at the current text scale, and plus-only on narrow layouts. Its accessible name is **Add tasks**. Keyboard submission, multiline splitting, composing-input handling and failure/retry behavior are unchanged.

## Completed tasks and capture grouping

The Open/Completed choice in Filter defaults to Open. Completed tasks use the same rows with checked checkboxes; unchecking reopens the task. Task title/notes remain editable in either view, and assignee filtering applies to both. Capture appears in Open; switching views preserves its draft. Toolbar Undo persists through snackbar expiry within the session; completed history remains independently accessible.

Reopening reverses the completion events this device has observed, using existing targeted undo records. A concurrent unseen completion survives; after sync the task can remain Completed and can be unchecked again. Retrying after partial failure reverses only remaining observed completions.

Inbox groups raw captures at the top, in shared manual order, until their first saved edit. New captures receive the first shared manual position, preserving multiline entry order; their initial rank survives leaving Inbox. A raw capture has no notes, tags or scheduling fields. Populated creations and generated recurring successors begin organized. Opening/canceling an editor, moving or completing a task does not count as an edit; Undo of its surviving edits restores Inbox. Completed browsing uses ordinary date/Someday groups, and reopening an unedited raw task restores its Inbox presentation. There is no separate never-edited flag. Inbox is a derived projection from existing events; cache replay updates earlier projections without rewriting canonical history. Manual reorder cannot cross Inbox and other groups.


Description previews use one ellipsized line with embedded whitespace flattened for display; whitespace-only notes reserve no subtitle. Titles wrap fully in the list. New title input stays one logical line, initially one visual line and growing to two with internal scrolling beyond that; pasted line breaks become spaces after IME composition commits. Historical multiline titles remain readable and are preserved on unrelated edits. Notes grow with content beyond three lines up to a viewport/keyboard-aware cap, then scroll internally; editor actions remain reachable. Settings exposes Theme/current choice, with System/Light/Dark radio choices and cancel without saving.

Title and quieter metadata are content-sized blocks in a wrapping layout: share a row when both fit, otherwise use subsequent lines. This is Lee's approved comparison option B. It removes the fixed-width metadata allocation and forced narrow stacking without mixing title and metadata into one paragraph. There is no density setting; complete title wrapping, description preview and comfortable hit targets remain.

Settings **Check data integrity** is an explicit full audit of the current canonical chains and any retained previous-history baseline. Show a scrollable/selectable report with affected log, record and byte offset where known, and Copy report. It writes no canonical events or repairs, preserves drafts/edits/selection/Undo, and may import valid arriving records normally. Ordinary startup remains incremental. The report distinguishes consistency from authentication and remote sync; [ADR 0007](decisions/0007-canonical-history-integrity.md) specifies the limits.

## Current milestone M2 — Markdown task parity

Separate start/scheduled/due dates with optional times and a shared Local or explicit IANA zone, spelling-preserving tags, shared relative manual ordering and all 37 observed recurrence forms. Keep date precision rather than fabricate midnight/end-of-day timestamps. Start must not follow due; derive date-only due as the exclusive beginning of the following day. The entire coupled schedule is one validated register, so concurrent field edits cannot produce an invalid hybrid.

Completion writes its successor proposal atomically. Recurrence uses the configured removal of scheduled date and places the successor before completed history. Reopening history preserves the successor; recompleting does not duplicate it. The compact list retains one preview line and full title wrapping; details remain in the editor. Notifications and general planner views remain outside this candidate. Renderer parity now requires the time-dependent visibility and effective-date ordering below.

See [ADR 0003](decisions/0003-task-parity-and-prerelease-boundary.md) for reasons, temporal/recurrence rules, event-clock correction and the explicit prerelease compatibility break. Private one-off migration tooling is outside the app repository and release scope. It validates domain-only round trips against a copied snapshot; Markdown remains authoritative until the coordinated stable cutover.


## Effective date and availability — accepted renderer parity

Open tasks appear when their start date/time has arrived; absent start means available. Completed history remains accessible regardless of start. The effective sorting date uses scheduled first, then due, then Someday. Optional minimum/maximum days-from-today bounds clamp this effective date, not the stored schedule or deadline. Minimum is applied first; maximum second. Contradictory bound pairs and duplicate reserved source tags are rejected. An undated minimum-only task stays Someday; an undated maximum becomes today plus that number of local calendar days.

Sort ascending by effective calendar day, then exact time; date-only tasks follow all timed tasks within that day. Stored manual order breaks ties, including between date-only tasks. Scheduled overrides supply both the effective day and its precision; an underlying due time does not turn a date-only scheduled override into a timed value. Group by local calendar date and weekday, with Someday separate. Lee confirmed the precise-time extension: clamp the local civil day while retaining the time within that day; pinned instants are converted to the viewer's local zone. Date-only values retain their civil date and precision, without fabricated end-of-day timestamps. Start boundaries use the shared task zone when explicitly pinned, including midnight for a date-only start; otherwise they use local time. This retains the schedule invariant’s existing zone interpretation. This extension does not move a real deadline when a sorting bound changes.

Recompute while the app remains open at the next availability or date-bound boundary, immediately on resume and time/zone changes, and after task/filter updates. These are derived views: no event writes or storage replay for clock ticks. Drafts and active editors remain intact. See [time-driven view implementation plan](time-driven-task-view.md) for adapter and validation requirements.

Lee approved an off-by-default Show upcoming filter so future-start tasks remain accessible for editing without changing normal visibility. Keep it within existing filtering; no separate Upcoming or manual-sort view. Like the existing user/list filters, this is session state rather than a synced task fact: a new app session starts with upcoming hidden. Turning it on preserves task dates and makes future tasks editable; completion history already stays accessible.

Scheduled dates are intended as overrides for a repeating occurrence. Existing nonrecurring scheduled values remain valid and preserved; the editor shows a concise warning instead of rejecting or silently clearing them. Recurrence continues to anchor due-first, so a scheduled override does not shift the underlying cadence when a due date exists.

Date-sorted drag-and-drop is constrained to an exact effective date/time and precision bucket, matching the accessible move actions. Explicit midnight and date-only on the same day are different buckets. Invalid destinations must be apparent during dragging; no drag may silently change schedule fields or pretend to override automatic ordering. Revalidate source/target after concurrent updates and preserve the relative order of unaffected hidden/filtered tasks in the shared manual sequence. Moving A after B in `A, hidden, B` produces `hidden, B, A`: no hidden task is moved or edited, but its absolute index naturally changes. This is a relative insertion contract, not a fixed-slot permutation of the visible tasks.

Ordinary-tag filtering selects multiple exact spelling-preserving tags, matching any selected tag and intersecting with assignee, completion and upcoming filters. Removable chips expose the active set; a fresh session starts unfiltered. The query and chips share one field; suggestions use an anchored dropdown outside the dialog layout, so query/result-count changes do not resize Filter. The dropdown is bounded and scrollable within the viewport/keyboard bounds. Options include ordinary tags across the current space, not scheduling-bound fields. Filtering never changes task data or manual order.

Dragging near the list viewport edge scrolls during the active gesture so off-screen peers are reachable. Eligibility remains restricted to equal effective date/time, including after scrolling, clock changes and incoming updates; invalid targets remain visible during the gesture. Stop scroll work when the drag ends/cancels, the app suspends or the workspace/view changes.

The everyday header uses one Filter control rather than permanent filter rows. Its single scrollable surface contains assignee scope, Open/Completed, upcoming and ordinary tag options. A nondefault-state indicator and Reset make current scope discoverable without repeating infrastructure. Reset restores active-user/Open/upcoming-hidden/all-tags; it never changes the active identity. The task icon/title/count and Undo/Search/Filter/identity share a row when space permits. Narrow layouts omit the title, use icon Filter and an account avatar, and show the count only when it fits; enlarged text can use two rows. Counts reserve both Open/Completed measurements, so switching status does not move controls. Current identity belongs in the top bar, with Settings in that menu; onboarding and recovery retain Settings access when no identity is available. This consolidates existing behavior to preserve vertical task space, not to add a general filter framework.

Date and Someday group headings remain visible while scrolling through their tasks. Each heading pins below the fixed toolbar and any compact selection controls; the next group pushes it away. Search retains its Open/Completed section labels and existing date groups. A heading is one opaque, accessible header rather than a duplicated overlay. Drag edge scrolling remains available, but a pointer over a pinned heading cannot target a task obscured beneath it. This keeps date context visible without changing grouping, filters, ordering or stored task data.

Tag choice must scale beyond a short fixed list: selected chips and case-insensitive search over bounded lazy results support a larger inventory. Searching options alone does not change the applied set. Wide task rows place dates/tags adjacent to the title without reserving an empty column; narrow or enlarged-text layouts use secondary metadata. Titles wrap fully, important deadlines remain readable, and descriptions get one preview line only when present. These are responsive defaults, not density or sort-mode settings.

Within a day group, due/occurrence metadata shows local times and role labels without calendar dates or timezone labels. Pinned times are converted using the device zone observed for the displayed task view; floating times remain local. The editor retains original pinned zones and schedule values. Full start/scheduled/due dates remain in the editor, including dates different from the effective group because of overrides or bounds. This is display simplification, not deadline mutation.

A visible unavailable task shows a future start hint: “Starts 17:00” later today, or “Starts Oct 5” with its local time when explicitly set for a later date. Include the year across years; preserve date-only precision rather than inventing an explicit time. Passed starts and completed history have no start hint. This applies both to Show upcoming and to search results, replacing search's separate Upcoming line. Use the same resolved availability instant and time observation as visibility; update at the start boundary, viewer midnight, resume and clock/zone changes without task writes. Date context is intentionally shown only for future starts, superseding the earlier times-only preference for that case.

Task search is separate from filters. A trimmed, case-insensitive query matches titles or descriptions across the current workspace, including other assignees, future-start tasks and completed history. While searching, filter choices are paused and retained; clearing search restores them. Open matches retain date/manual ordering, with completed matches in their own bottom section. No query changes task facts, identity or workspace boundaries. Future matches remain identifiable, and constrained reordering cannot cross completion sections or effective sorting values.

List schedule metadata shows this occurrence's override when present, otherwise the base due value; it never repeats both. The editor calls the override “This occurrence” and explains that recurrence clears it without changing the underlying due cadence. Stored scheduled fields remain unchanged.

## Direct and bulk editing — RC4

Follow [decision 0004](decisions/0004-editing-bulk-actions-and-installers.md). Task rows open editing directly, without task overflow menus. Wide layouts show a side editor; smaller ones use a modal. Protect unsaved drafts across navigation and resizing; validate changes immediately. Delete is opposite Cancel/Save and requires confirmation. Occurrence controls appear for repeating tasks or retained override data.

Rows use selection highlights, with a separate completion checkbox and drag handle. Ordinary clicks edit one task; Ctrl/Cmd-click or long-press enters explicit selection and subsequent plain clicks toggle membership. Initial explicit one-item selection retains bulk intent; a later two-to-one reduction returns single editing in the wide pane, while compact selection stays active until Edit or clear; zero closes/exits. Shift ranges use current visible order, including different date groups for editing. Wide selection automatically opens a pane with count/Clear; layouts without the side pane swap selected count, Clear Selection and Edit into the fixed task-entry area above the scroll viewport. Keep the capture buffer mounted, preserve its multiline draft and reserve the same area before/during selection at the current text scale. Completed reserves the compact action area without an invisible multiline draft. Selection entry/exit does not insert/remove a row, move the pressed task or cover rows/drag targets. Search and Filter remain available while selected. No permanent selection button or second checkbox column. Dirty selection/target changes require Save/Discard/Cancel, retaining the old frozen draft and selection if validation or saving fails. Completion and drag gestures never change selection.

Bulk edits exclude title/notes, retain untouched mixed values and apply only explicit schedule/assignee/tag deltas. Validate the selection before writing and disclose any partial durable progress; preserve/reconcile remaining drafts for retry. Bulk drag retains selected tasks' global relative order and unaffected tasks' relative order within an exact date/time and completion bucket, even though edit selections may span groups. Absolute indexes can shift; filters never cause hidden-task move records. Confirmed deletion is a canonical tombstone, recoverable through session Undo while preserving history and independent recurrence successors; deletion belongs in the editor rather than a duplicate selection toolbar.

## Session Undo and toolbar fit

Follow [decision 0005](decisions/0005-session-undo-and-toolbar.md): at most 50 confirmed session actions, repeated toolbar Undo, native text Undo in inputs, quiet editing/reorder and brief completion/deletion notices sharing the same action. Retract only the named operation, preserving independent later contributions. Checkbox Reopen retains recurring successors; true Undo of recurring completion retracts an untouched successor proposal while preserving independently changed or referenced successor work. Late-arriving work restores its protected successor deterministically. Restart/workspace change clears local action history. The checkmark remains in the task toolbar; the active name fits in full or uses an accessible initial avatar. No per-event actor attribution or audit UI is implemented.


## Approved one-level checklists — isolated implementation

Lee approved a title, optional notes, completion and order for each checklist
item, one level deep. Recurrence copies fresh unchecked items; existing successor
edits remain independent. Domain/storage and editor/warning UI are implemented
separately from shared-history candidatec182385. Items appear within the single
task editor with checkboxes, editable title/notes, relative movement and deletion.
Item Save is separate from parent Save/Cancel. Unfinished items trigger a
warn-but-allow dialog; incoming changes renew consent before bytes are prepared.
Linux desktop/narrow/enlarged/theme workflows are verified; exact checklist
Android/Windows acceptance remains pending. Explicit item Save/Cancel,
parent-draft boundary, renewed warning confirmation and recurrence/Undo meanings
are specified in [ADR0011](decisions/0011-one-level-checklists.md).

## Completion eligibility and reorder continuity — RC5 follow-up

An open repeating task cannot be completed when its computed successor preserves all three stored dates (start, due and this-occurrence override). A cleared override counts as a change. Sorting bounds/group labels are not inputs to this rule, and recurrence calculation itself is unchanged. The unavailable checkbox explains on tap, hover and keyboard focus. This prevents another identical scheduled occurrence; recording repeated same-period work is not a current requirement. Advancing, overdue and nonrepeating tasks remain completable. History reopening and Undo remain available. The store checks after ingestion and before append; accepted older history is never retroactively rejected.

Eligibility follows the completion day in the task's explicit zone or current local zone and refreshes at that zone's civil midnight, including DST, and on existing resume/clock/zone invalidation. A clock-only view change writes no event. Recurrence beyond the supported calendar range explains the need to edit the schedule instead of crashing the list.

Valid reorders retain the mounted single/bulk editor session, selection, draft controllers, focus and scroll. They do not ask to save/discard unrelated content. Bulk order tokens advance only across exact confirmed local moves that reproduce the observed snapshot; other changes retain the conflict guard. Undo of a move also keeps the editor, while Undo of content-changing operations retains the existing dirty-draft guard. Selection anchors are task identities: a subsequent Shift selection uses the anchor's current visible position after own or external order changes. Only an anchor that becomes unavailable/hidden/removed is invalidated.

The tag popup prefers below when enough usable rows fit, including one-row/empty results. It flips above only when needed by the actual safe viewport/keyboard bounds, not because the dialog footer happens to be close or the space above is larger. Visible suggestions expose their label, selected state and selection action outside the query scroll viewport in the accessibility tree. The bounded overlay may temporarily cover a footer; selection, Escape/Tab, outside dismissal or collapse exposes it without resizing the dialog.

Multiline capture presents one acknowledged update, not progressive line clearing. On failure it retains unconfirmed lines, using the original task identities for safe retry. Bulk creation, edits/tags, moves, deletion and operation Undo share validated multi-record appends; their crash semantics remain per-record rather than whole-batch atomic.


Task completion controls for repeating tasks use Lee's approved repeat-checkbox v6 outline: an 18px square perimeter with a 2px stroke, rounded tails and filled tips. The vector occupies 18×26px so its intentional tip bleed is not squeezed into an 18px-height slot. The larger tips and clear gaps distinguish the arrows at normal size. It is centered over the native padded checkbox; focus, hover/touch reaction, checked state and assistive semantics remain native. Completed tasks use the same ordinary checked checkbox whether or not they repeat; reopening restores the open repeating outline. Unavailable completion uses the dimmed outline while tap/hover/focus still explains the guard. The separate repeating marker is removed to avoid duplicate information and an otherwise-empty metadata line. Full recurrence wording remains in accessible semantics and the editor. Completion never selects or starts dragging a row. This replaces v4 after hands-on feedback and Lee's explicit v6 approval on 2026-10-02; no persistence or recurrence semantics change.


Keyboard metrics and the dialog's later viewport animation must not collapse an intentionally opened tag dropdown. Reveal the focused query against changed viewport extents, retain its text/selection and keep suggestions actionable. Deliberately scrolling the query out of view still dismisses the popup. Enlarged-text users can scroll partially visible options fully into view and select them; clipping alone is not reported as a crash.

Folder failures explain recovery in ordinary language. A missing file names the canonical file and suggests restoring it or waiting for folder sync; only actually denied access suggests selecting the folder again. Generic read/write failures report availability rather than assuming a revoked grant. Preserve independently confirmed partial progress, unconfirmed drafts and normal retry/integrity checks; human error formatting does not repair or discard canonical data. Framework/provider exception wrappers remain diagnostic causes, not task UI copy.


Keyboard completion retains native checkbox focus when the same task remains in the current view, including status regrouping in Search. A short pending write rejects additional completion commands without disabling the control and releasing its focus. Deliberate traversal elsewhere stays elsewhere; when the task leaves the filtered view, normal focus fallback applies. No async focus restoration steals focus from another control.

## Accepted historical recompletion

When a reopened old occurrence has an existing, independently initialized next
occurrence, completing the old task retains that next occurrence exactly. Its
edits, notes, schedule, tags, manual order, draft and scoped Undo survive; completed
or deleted children keep that status. Undo/reopen affects the old parent's
completion and keeps the existing child. Forward native recurrence retains its
approved completion-observed union. See the [policy and compatibility boundary](historical-recurring-text-policy.md).
