# rc2 task-based UX audit

Scope: actual native Linux release under Xvfb/Openbox, 1280-pixel desktop and 390-pixel narrow window; light and dark. Narrow Linux is not Android evidence. Android candidate is independently routed to the accelerated device worker.

## Observations and resolutions

- Desktop Start → inline name → tasks is continuous. Empty Continue is disabled; focus starts in the name field; Enter proceeds. Existing-folder choice remains secondary and does not create an unused default folder. Native tests exercised canceled setup and write failures without losing the intended name.
- Real keyboard capture: Enter submitted one task; Shift+Enter inserted a second line; keypad Enter committed the two lines as two tasks. Focus returns to capture. Integration checks also cover pasted blank lines, repeat suppression and active composition. Actual Japanese IME behavior still needs a user/device check.
- Everyday screen now puts capture and tasks near the top. The count shares the heading; user controls wrap at narrow width. Permanent sync explanation and routine refresh controls are gone. Settings keeps the uncommon folder actions and data-location consequences discoverable.
- Incoming changes preserve typed capture and active edit buffers. The native integration flow edits one field while another device updates another field, then verifies both. Resume import and contextual error recovery passed.
- Light/dark screenshots retain clear input/card hierarchy. An independent reviewer inspected onboarding, first user, empty state, settings, dark tasks and narrow layout; no blocking visual defect was observed.

## Optional polish, not release blockers

The independent reviewer noted that an upward submit arrow is less explicit than a plus, and repeated Inbox subtitles add little when all tasks are new. Keep the current controls for this candidate; revisit based on real usage rather than taste alone. Lee reports an already-open user menu needs reopening to display a newly synced user; keep active selection stable and treat this as low-priority polish.

Screenshots establish visual layout, not screen-reader behavior or real phone touch/IME acceptance. Task-based audit and user testing complement correctness tests; neither replaces the other.
