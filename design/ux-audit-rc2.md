# rc2 task-based UX audit

Scope: actual native Linux release under Xvfb/Openbox, 1280-pixel desktop and 390-pixel narrow window; light and dark. Narrow Linux is not Android evidence. Android candidate is independently routed to the accelerated device worker.

## Observations and resolutions

- Desktop Start → inline name → tasks is continuous. Empty Continue is disabled; focus starts in the name field; Enter proceeds. Existing-folder choice remains secondary and does not create an unused default folder. Native tests exercised canceled setup and write failures without losing the intended name.
- Real keyboard capture: Enter submitted one task; Shift+Enter inserted a second line; keypad Enter committed the two lines as two tasks. Focus returns to capture. Integration checks also cover pasted blank lines, repeat suppression and active composition. Actual Japanese IME behavior still needs a user/device check.
- Everyday screen now puts capture and tasks near the top. The count shares the heading; user controls wrap at narrow width. Permanent sync explanation and routine refresh controls are gone. Settings keeps the uncommon folder actions and data-location consequences discoverable.
- Incoming changes preserve typed capture and active edit buffers. The native integration flow edits one field while another device updates another field, then verifies both. Resume import and contextual error recovery passed.
- Hosted 200% text-scale/narrow testing exposed a 28-pixel brand-row overflow not reproduced with local font metrics. The brand now flexes with an ellipsis and appearance choices stack on narrow/large-text layouts; the same regression remains in the native gate.
- Light/dark screenshots retain clear input/card hierarchy. An independent reviewer inspected onboarding, first user, empty state, settings, dark tasks and narrow layout; no blocking visual defect was observed.

## Optional polish, not release blockers

The independent reviewer noted that an upward submit arrow is less explicit than a plus, and repeated Inbox subtitles add little when all tasks are new. Keep the current controls for this candidate; revisit based on real usage rather than taste alone. Lee reports an already-open user menu needs reopening to display a newly synced user; keep active selection stable and treat this as low-priority polish.

Screenshots establish visual layout, not screen-reader behavior or real phone touch/IME acceptance. Task-based audit and user testing complement correctness tests; neither replaces the other.

## Build 3: completed browsing and mobile density

Lee requested ordinary checked rows in Completed, unchecking to reopen, and less padding/card decoration. The unpublished rc2 now includes these changes. Task rows use a flat divided list, normal-weight wrapping titles, optional notes, and explicit 48-pixel checkbox targets on desktop as well as Android. Repeated Inbox badges are hidden without rewriting stored state. Header/body spacing is reduced; there is no density preference.

The dark-mode Undo background was visibly too pale in the prior walkthrough. Explicit theme surface, foreground and action colors address it. A sanitized twelve-task fixture (mixed title lengths and two notes) is used for comparison; no user screenshot/text is copied into the repository. Actual same-size phone comparison remains pending worker dispatch.

### Measured native Linux comparison

Same 390×820 client area, default text scale, identical twelve sanitized tasks (two with notes): rc1 shows **four fully visible rows and part of a fifth**, while build 3 shows **ten fully visible rows and part of an eleventh**. Captures are `evidence/density-rc1-linux-390x820.png` and `evidence/density-rc2-linux-390x820.png`. This is Linux with desktop font/theme metrics, not an Android result or a claim about the private reference screenshots.

The final native build additionally showed a long title wrapping fully across three lines, a checked Completed row reopening when unchecked, and the corrected dark Undo surface/text/action contrast. Screenshots are `evidence/linux-rc2-build3-*`. Checkbox dimensions are asserted at least 48×48 by the native integration test. Actual same-size phone screenshots remain blocked by worker dispatch.

The build 3 walkthrough exposed a stale completion snackbar after reopening from Completed. Successful reopening now clears it; the native regression verifies that Undo is no longer shown for the reopened task.


## Build 4: settings and notes preview

User feedback identified the vertical appearance pill as awkward. The replacement Theme row/current choice opens ordinary radio choices. Content aligns to one inset, a divider separates appearance from folder actions, and cancel preserves the preference. Full multiline descriptions remain in the editor; the list shows only one ellipsized preview line, never an empty reserved line.

Actual native Linux release inspection at 390×820 and 1000×820 confirmed the revised dialog and realistic sanitized multiline notes in light/dark. At 200% text, a temporary native debug entrypoint wrapped the unmodified application widgets in a MediaQuery with `TextScaler.linear(2)`; this wrapper was removed and is not shipped. The settings body scrolls, Done remains reachable, and all theme options/Cancel fit. Screenshots: `evidence/linux-rc2-build4-*`; names containing `200` identify that injected-scale harness. Other screenshots and the 20-second walkthrough use the actual release binary. The recorder captured 20.36 seconds for a 20-second video with visible pointer; it is not a startup benchmark.

Independent code and screenshot review found no concrete regression. Native integration tests cover radio cancel, persisted choice/system changes, full multiline-note preservation, one-line preview and 390-pixel/200% layout bounds. Initial test-harness screen captures did not reliably reflect active dialogs and were excluded; final screenshots were captured from visibly inspected native windows. Android-specific behavior remains with the device worker, not inferred from these Linux results.
