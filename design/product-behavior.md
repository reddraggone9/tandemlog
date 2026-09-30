# Product behavior and first milestone

## Accepted direction

Offline household task management first. Windows and Android are the first intended user platforms. Future modules include games, food logging, inventory, and assisted input. Time tracking is undecided and excluded.

The first slice is folder/user selection, capture, edit, complete, undo, persistence, and convergence tests. Recurrence, reminders, deletion, advanced dates, floating priorities, manual shared sorting, and other modules are outside this slice.

## Platform verification milestone M0 — remove platform uncertainty

With Flutter and provider-independent folder sync approved, use dedicated disposable test folders and the implemented platform adapter to prove Android tree selection and retained access; two-way file transport with a selected wrapper; replacement/reopen; reboot and process death; and no-internet hotspot behavior on the intended phones. Also launch a minimal Windows build and verify text input, folder selection and packaging prerequisites. Record versions and results. M1 implementation proceeds in parallel, but this remains a release acceptance gate. Failure prompts a product/transport decision, not an automatic broad-storage permission workaround.

## Current milestone M1 — persistent shared tasks

- Choose/create a supported workspace namespace in an authorized folder. Detect existing workspaces and incompatible formats. Do not mutate unrelated files. Distinguish “saved locally” from transport status; never imply other devices received a change without evidence.
- Create/select a stable user ID and display name; allow switching users. This is attribution, not authentication. Default new task assignment to the active user; retain an all-tasks view.
- Capture a title rapidly; edit title and optional description. Completion removes the task from the active list. Offer immediate undo of that completion, targeting the completion operation so it cannot undo someone else's later action blindly.
- Keep initial ordering stable and simple (creation order with ID tie-break). Do not implement date sorting without date semantics. Avoid a generic database editor or future-module navigation placeholders.
- Persist acknowledged changes through restart. Never report a failed write as saved. Recover from a log write followed by cache failure without duplicating the command.
- Import two independent devices' edits, including duplicate and out-of-order delivery, and show the same materialized state after the same event set is available. Document the chosen per-field conflict rule. Rebuilding the cache must produce the same result.

The implemented [protocol](schema.md) specifies only this slice. Do not revive the removed generic field-change draft.

## Acceptance evidence

Core tests cover shuffled delivery, duplicate completion/undo, different-field versus same-field edits, missing dependencies, restart, cache removal, truncated tail, file replacement, write failures and incompatible versions. Target acceptance still requires the two-device offline/edit/reconnect/restart script in [runtime QA](runtime-qa.md); local folder-copy tests are not phone transport verification.

For UI changes run and visually inspect capture/edit/complete/undo plus empty/error states and keyboard/touch layout. Include desktop and Android videos when those runtimes work. Native acceptance remains pending when only browser results exist; see [runtime QA](runtime-qa.md).

## Onboarding and everyday interaction

Follow [decision 0002](decisions/0002-onboarding-and-everyday-interface.md): explicit desktop Start with a default folder, secondary existing-folder choice, unchanged Android SAF selection, inline first user, local System/Light/Dark preference, compact filtered task count and automatic foreground imports. Workspace switching and opening are settings actions. No permanent refresh control or explanatory sync footer. Preserve capture/edit buffers and selection through incoming updates. Desktop Enter submits and Shift+Enter inserts another task line; Android Enter is a newline. IME composition must not submit.
