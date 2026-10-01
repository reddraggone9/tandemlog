# Product behavior and milestones

## Accepted direction

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

Follow [decision 0002](decisions/0002-onboarding-and-everyday-interface.md): explicit desktop Start with a default folder, secondary existing-folder choice, unchanged Android SAF selection, inline first user, local System/Light/Dark preference, compact filtered task count and automatic foreground imports. Workspace switching and opening are settings actions. No permanent refresh control or explanatory sync footer. Preserve capture/edit buffers and selection through incoming updates. Desktop Enter submits and Shift+Enter inserts another task line; Android Enter is a newline. IME composition must not submit.

## Completed tasks and capture grouping

The compact Open/Completed switch defaults to Open. Completed tasks use the same rows with checked checkboxes; unchecking reopens the task. Task title/notes remain editable in either view, and user/Everyone filtering applies to both. Capture appears in Open; switching views preserves its draft. Short-lived Undo remains a convenience, not the only recovery route.

Reopening reverses the completion events this device has observed, using existing targeted undo records. A concurrent unseen completion survives; after sync the task can remain Completed and can be unchecked again. Retrying after partial failure reverses only remaining observed completions.

Keep the stored Inbox state but hide its repeated row badge. Future Inbox grouping should place bulk captures near the top until meaningful details (description, due date/time) move them into the normal sorted list. That future detail-based transition is not implemented: the current historical projection still clears Inbox on any edit. Do not silently change replay meaning before a compatible migration decision.


Description previews use one ellipsized line with embedded whitespace flattened for display; whitespace-only notes reserve no subtitle. Titles wrap fully, and the editor preserves complete multiline notes. Settings exposes Theme/current choice, with System/Light/Dark radio choices and cancel without saving.

## Current milestone M2 — Markdown task parity

Separate start/scheduled/due dates with optional times and a shared Local or explicit IANA zone, spelling-preserving tags, shared relative manual ordering and all 37 observed recurrence forms. Keep date precision rather than fabricate midnight/end-of-day timestamps. Start must not follow due; derive date-only due as the exclusive beginning of the following day. The entire coupled schedule is one validated register, so concurrent field edits cannot produce an invalid hybrid.

Completion writes its successor proposal atomically. Recurrence uses the configured removal of scheduled date and places the successor before completed history. Reopening history preserves the successor; recompleting does not duplicate it. The compact list retains one preview line and full title wrapping; details remain in the editor. Notifications and general planner views remain outside this candidate. Renderer parity now requires the time-dependent visibility and effective-date ordering below.

See [ADR 0003](decisions/0003-task-parity-and-prerelease-boundary.md) for reasons, temporal/recurrence rules, event-clock correction and the explicit prerelease compatibility break. Private one-off migration tooling is outside the app repository and release scope. It validates domain-only round trips against a copied snapshot; Markdown remains authoritative until the coordinated stable cutover.


## Effective date and availability — accepted renderer parity

Open tasks appear when their start date/time has arrived; absent start means available. Completed history remains accessible regardless of start. The effective sorting date uses scheduled first, then due, then Someday. Optional minimum/maximum days-from-today bounds clamp this effective date, not the stored schedule or deadline. Minimum is applied first; maximum second. Contradictory bound pairs and duplicate reserved source tags are rejected. An undated minimum-only task stays Someday; an undated maximum becomes today plus that number of local calendar days.

Sort ascending by effective date/time with stored manual order breaking ties. Group by local calendar date and weekday, with Someday separate. Lee confirmed the precise-time extension: clamp the local civil day while retaining the time within that day; pinned instants are converted to the viewer's local zone. Date-only values retain their civil date and precision. Start boundaries use the shared task zone when explicitly pinned, including midnight for a date-only start; otherwise they use local time. This retains the schedule invariant’s existing zone interpretation. This extension does not move a real deadline when a sorting bound changes.

Recompute while the app remains open at the next availability or date-bound boundary, immediately on resume and time/zone changes, and after task/filter updates. These are derived views: no event writes or storage replay for clock ticks. Drafts and active editors remain intact. See [time-driven view implementation plan](time-driven-task-view.md) for adapter and validation requirements.

Lee approved an off-by-default Show upcoming filter so future-start tasks remain accessible for editing without changing normal visibility. Keep it within existing filtering; no separate Upcoming or manual-sort view. Like the existing user/list filters, this is session state rather than a synced task fact: a new app session starts with upcoming hidden. Turning it on preserves task dates and makes future tasks editable; completion history already stays accessible.

Scheduled dates are intended as overrides for a repeating occurrence. Existing nonrecurring scheduled values remain valid and preserved; the editor shows a concise warning instead of rejecting or silently clearing them. Recurrence continues to anchor due-first, so a scheduled override does not shift the underlying cadence when a due date exists.

Date-sorted drag-and-drop is constrained to an exact effective date/time bucket, matching the accessible move actions. Invalid destinations must be apparent during dragging; no drag may silently change schedule fields or pretend to override automatic ordering. Revalidate source/target after concurrent updates and preserve hidden/filtered tasks in the shared manual sequence.

Ordinary-tag filtering selects one exact spelling-preserving tag at a time and combines with the selected user, completion view and upcoming visibility. The active tag is visible and has a clear/reset action; a fresh session starts unfiltered. Options include ordinary tags across the current space, not scheduling-bound fields. Filtering never changes task data or manual order.

Dragging near the list viewport edge scrolls during the active gesture so off-screen peers are reachable. Eligibility remains restricted to equal effective date/time, including after scrolling, clock changes and incoming updates; invalid targets remain visible during the gesture. Stop scroll work when the drag ends/cancels, the app suspends or the workspace/view changes.

The everyday header uses one Filter control rather than permanent filter rows. Its single scrollable surface contains assignee scope, Open/Completed, upcoming and ordinary tag options. A nondefault-state indicator and Reset make current scope discoverable without repeating infrastructure. Reset restores active-user/Open/upcoming-hidden/all-tags; it never changes the active identity. Current identity belongs in the top bar, with Settings in that menu; onboarding and recovery retain Settings access when no identity is available. This consolidates existing behavior to preserve vertical task space, not to add a general filter framework.

Tag choice must scale beyond a short fixed list: the filter surface shows the selected tag and clear action, with case-insensitive search over a bounded lazy result list. Selection remains one exact stored tag; searching alone does not change the applied filter. Wide task rows place dates/tags adjacent to the title without reserving a large empty column; narrow or enlarged-text layouts use secondary metadata. Titles wrap fully, important deadlines remain readable, and descriptions get a separate one-line preview only when present. These are responsive defaults, not density or sort-mode settings.

Row metadata omits a date only when its rendered day matches the displayed group day. Exact times, relevant pinned-zone context and differing original dates remain visible, including when scheduled overrides or sort bounds change the group. Grouping never changes task facts.
