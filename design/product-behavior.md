# Product Behavior

This document is for user-facing behavior and workflows.

## How the App Works

- The initial version is usable task management for multiple users.
- Next version adds time tracking and time correction/editing, but tasks remain the center of the app.
- Offline operation is the default assumption: local actions must always work, and sync catches up later.

## Version Scope

### Initial version

- Create, edit, complete, and organize tasks
- Show a Today-oriented workflow rather than a generic database-first UI
- Support recurring tasks
- Support assignment as a suggestion and for filtering

### Next version

Everything in the initial version, plus:

- Start/stop time tracking for tasks and activities
- Addition and correction of recorded time after the fact
- Auto-switch behavior when starting a different timer while one is already running

## Primary User Experience

### Main screen

The default home screen is a Today view. The Today view should include these user-facing sections:

- an active timer / current task area at the top
- an inbox area near the top for fresh captures that still need sorting
- all other tasks that are currently workable

The tasks list should sort by due time and break ties using manual ordering. That manual ordering is a single shared ordering across all tasks. The due date displayed on a task in the list should distinguish whether it is a deadline, target, or floating target.

### Who sees what?

Every task must have at least one assignee, and a task may have multiple assignees. Default to showing all tasks where the current user is in the task's assignees list. It should be possible to change that to show tasks assigned to another user or all tasks. Any user can edit any task regardless of assignees.

### User identity

On startup, the app should require user creation or user selection before entering normal use. A device is not permanently bound to one user; it should be possible to switch the active user later. If a user is renamed, that rename should be reflected everywhere the app displays that user, including assignment displays throughout existing tasks.

## Task Behavior

### Creation

Task capture needs to support two distinct behaviors:

1. Fast capture for getting tasks out of the user's head quickly
2. Full-detail entry for creating a single task with details immediately

Fast capture should support a quick-add list, entering one task per line into a text field at the top of the inbox and submitting to create several tasks at once. These tasks will remain in the inbox until they have been edited (any edit by any user) so that it is easy to return later and add details such as dates, assignment, or descriptions. A captured task should leave the inbox on its first edit of any kind.

Newly captured tasks should default to the current user as assignee.

### Dates

| Field           | Presence | Component           |
| --------------- | -------- | ------------------- |
| Start           | Optional | Date OR Date + Time |
| Due             | Optional | Date OR Date + Time |
| Priority buffer | Optional | Duration            |

The due date field should distinguish between hard deadlines and softer target dates. The UI can model this as one chosen date/time plus a toggle indicating whether that date is a hard deadline or a softer target.

Additionally, floating target dates (via priority buffer) should be supported for sorting purposes. These shift over time by design. A duration and toggle combo will allow users to move the target date to a minimum or maximum distance from today. With a minimum distance, this can be used to prevent a task from becoming overdue or to sort it below higher-priority tasks that should be done today. A maximum distance can be used push a task near the top of your list even if it's actually due later so that it's not forgotten until the last minute. If no due date is set, then the floating target date is simply today plus the duration.

#### Constraints

- start must not be after due
- a priority buffer can be set when the task has a target due date or no explicit due date
- a priority buffer must be a maximum distance if no target date is set

### Hiding tasks

If a task has a future start, it should stay hidden until that start. A toggle similar to the user toggle should allow display of tasks with future starts.

### Completion

One-off tasks should be completable from the main workflow with minimal friction. Recurring tasks should continue to behave like one actionable task at a time rather than creating clutter from many future copies. If a user completes or deletes a task by mistake, the UI should offer an option to undo that action. Completed tasks should leave the main day-to-day view immediately rather than lingering in a visible completed section.

### Recurring tasks

Recurrence requires at least one date field: start, due, or both. Recurring tasks should repeat from either a date field or the completion time based on a toggle. If the toggle selects date-field recurrence, the next occurrence should be from the current due date, or from the current start date if due is unset, and written back to that same field. If the toggle selects completion-time recurrence, the next occurrence should be calculated from the time of completion and written to due, or to start if due is unset. When a recurring task also has a start/due relationship, the offset between start and due should remain stable across recurrences. Recurrence should be specified via text such as "every day", "every week on Tuesday, Thursday", or "every month on the last" (specifically matching rrule.js's `rule.toText()` format, though that particular library need not necessarily be used).

## Time Tracking Behavior

Time tracking is introduced in the next version

### Core behavior

- Manual time entry matters, not just live timers
- Starting a different task while a timer is already running should auto-switch to the new task
- Generic activities are also first-class; time is not limited to tasks only
- Only one thing should be actively timed at once across both tasks and activities

If sync produces overlapping time intervals for the same user because different devices were used offline, the most-recent change will stick for the overlapping span and the other interval will be adjusted to fit it.

### Current task prominence

When a timer is running, the active task / active timer should be the most prominent item in the Today view. When a timer is not running, the task at the top of the list should take its place.

### Non-task activity tracking

- These activities should be treated as first-class tracked items rather than as a hidden fallback mode
- Activities should be easy to start from a quick activity picker rather than being forced through the full task flow

### Editing recorded time

- adjust a block's start or end
- split a block into multiple blocks
- reassign a block to a different task or activity
- add a manual block after the fact
- delete a mistaken block

## Offline and Sync-Visible Behavior

- The app must never block local task or time actions just because another device is offline or unsynced
- Offline use is normal behavior, not an error state.
- When another device's changes arrive, the app should update quietly.
- If one device deletes a task while another device edits it offline, the deletion wins over the edits for that task when sync catches up.

### First run / adding a device

The app should present a folder picker on first launch. Any folder that already exists on disk is valid. After choosing the folder, the app should move straight into user creation/selection and then normal use without further onboarding.

## Notifications and Reminders

Notifications will be implemented in a later version. Android is the required platform for notification behavior. Windows and Linux should support equivalent notification behavior where practical.

### Task reminders

- Tasks should support an explicit reminder timestamp
- Reminder time should default to absent
- In the task edit flow, if the user focuses the reminder field or opens its picker while the reminder is still absent, it should autofill from due, or from start if due is unset
- If that autofilled value is then saved, it should be treated the same as a user-entered reminder time

Task reminders should notify all assignees.

### Recurring task reminders

A recurring task's reminder should recur with the task when the task advances to its next occurrence. The reminder notification should open the its task.

### Reminder delivery and dismissal

- Reminder state should be tracked per user rather than per device
- Dismissing a reminder on any device should dismiss that same reminder instance on all of that user's devices once sync catches up
- If a device receives both a task with reminders and the dismissal for that reminder before the reminder fires locally, the reminder should not fire
- If a device receives a task with reminders whose reminder time has already passed and no dismissal has been seen, the reminder should fire
- If a task's reminder is moved later before it fires, it should not fire until the new reminder time
- If a task is completed before its reminder fires, that reminder should not fire
- Duplicate alerts on multiple devices for the same user are acceptable if dismissal has not synced yet

### Timer notifications

When a timer is running, the app should show a persistent notification reflecting the current task or activity and its elapsed time.

- Timer notification behavior should continue to work while the app is backgrounded or otherwise not in the foreground.
- The timer notification should offer an action to end the current timed item.
  - If the timed item is a task, that action should complete the task.
  - If the timed item is a generic activity, that action should stop that activity.
  - After that action, the app should recompute the canonical Today task list (i.e. what Today shows before any sort/filter modifications) and automatically start timing the top eligible task from that list.
  - If recomputing the canonical Today task list yields no eligible task, the timer notification should disappear.
- If sync changes which item is currently being timed on another device, timer notifications on that user's devices should update, clear, or be replaced to reflect the synced state once sync catches up.

## Open Areas

- Longer-term user-readable history views beyond immediate undo and creator display
- Semantics for date-only fields across time zones
- Which task times are absolute instants versus current-time-zone-local times
- How recurrences should preserve durations and offsets when time zones or DST boundaries change
- Overlapping time tracking. Examples:
  - I did the dishes for 25 minutes, but my wife was texting me while I did them, so about 10 minutes of that time was texting instead of dishes. However, I probably swapped back and forth 6 or more times and the overhead of tracking that wouldn't be worth it.
  - I played WoW for 3 hours, but I got up to eat somewhere in the middle of it. That break took about 20 contiguous minutes, but I didn't record exactly when it happened.
  - I folded clothes for an hour and a half while watching TV. If I hadn't had the TV going, it might have taken me seventy minutes instead.
- Task tags (hierarchical)
- Subtasks
  - Have a little % indicator with changing colors when all of the subtasks are done
- Done list
- Accomplishment tag that can be used to filter Done list (and also can filter by tags like work, personal, etc.)
- One-off modifications to repeating tasks (e.g. hide this task until my wife will be available because I can't progress on it without her)
- Max repetitions (mostly for game stuff)
  - For five weeks after an expansion launch, WoW will release a new campaign quest line each week
  - I need to collect 10 of a certain item, but I can only get one per day
  - World bosses are available on a rotation. To get all 4 of them, I need to do one each week
- Marking a repeated task done; some goals (e.g. maxing out a faction's reputation or reaching a gear level) can't be programmed in. I'd still like to be able to mark a task done (as opposed to continuing to repeat it) when the underlying goal is met.
