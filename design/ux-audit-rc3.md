# rc3 task-based UX audit

Candidate acceptance remains pending. Native Linux debug app, 1000×820 and 390×820, Light/Dark, 100%/200% text; sanitized fixtures only. Eight layout combinations produced 56 inspected screenshots through an independent UI worker, with representative final frames also reviewed by the integrating agent. This is not Android or Windows evidence.

## Observed defects and corrections

- Onboarding/settings actions lacked space: responsive wrapping actions now retain horizontal and vertical gaps and comfortable targets.
- Shift+Enter left a blank last-line caret outside the capture viewport: use Flutter’s user-edit path so selection reveal runs after layout. Test before any additional character.
- Open/Completed count lengths moved header controls: viewport/text-scale layout and reserved count dimensions keep controls stable.
- At 200% text, named-zone choice and editor helper text clipped: shorter choices, wrapping helper copy and expansion padding retain readable controls.

- Native demo review found successors returning to a previous position after the parent was manually moved. Ordering replay now interleaves creation, movement and recurrence insertion; regressions assert current-position insertion and later independent moves.

## Task outcomes

The native parity scenario verifies invalid schedule recovery without losing the draft, editing dates/times/tags, manual movement, recurring completion and historical reopening without another successor. Existing native scenarios cover rapid capture, interrupted/error flows, incoming folder changes, user selection, theme persistence and repeated keyboard capture. Full final-suite results are recorded in runtime QA rather than inferred from these screenshots.

The list remains flat and dense, with full title wrapping and one ellipsized metadata line, prioritizing due date/time. Details remain in the editor. Empty descriptions reserve no row. Save/Cancel remain visible outside the editor’s scroll area; all three dates have optional times and one clearly shared Local/UTC/named zone. Zoned previews show device-local equivalents. The recurrence examples menu wraps and scrolls at large text.

## Deliberate limits

The complete three-date editor is long at 200% text, and 37 recurrence examples form a long menu. These are subjective follow-ups rather than observed failures; seek actual use feedback before another redesign. Manual ordering keeps accessible move-up/down actions and adds dragging only within an equal effective date/time bucket. No pure manual-sort mode is approved. Tags can be edited and filtered one exact ordinary tag at a time; a general filter builder is outside this candidate.

Android keyboard, SAF/lifecycle, native text scaling and exact signed-artifact smoke remain separate gates. Linux screenshots cannot replace them. Private source import acceptance is separate from synthetic UI fixtures.

## Constrained drag review

Native Linux pointer tests cover valid peer movement while preserving hidden/filtered global order, rejected same-day/different-time drops with unchanged logs, and cancellation after a changed projection. Actual screenshots at desktop 1000px/100% and narrow 390px/200%, both themes, show an insertion line for valid targets and error-colored boundary/background for invalid targets during dragging. This is desktop native evidence, not Android touch acceptance.

Independent review found and verified the fix for a late-ingestion race between the UI check and storage refresh. The serialized operation compares the task snapshot after ingestion and synchronously rechecks caller eligibility/current time immediately before append. Injected late schedule/order/completion changes and clock-only invalidation append no move. Both drag and menu actions use the guard; 45 storage tests pass. The scheduled-date warning remains informational: saving a nonrecurring scheduled value must preserve it.

Show upcoming is off by default and session-only. Native focused coverage verifies finding/editing a future task, preserving capture text through filtering, and resetting to off on app restart. Final screenshots include the enlarged-text scheduled warning with Save available and responsive upcoming controls in both themes.

Code 12 adds edge auto-scroll only during a drag, retaining the same-bucket restriction. A stationary-pointer regression reaches an initially unmounted destination; release resolves current row geometry rather than Flutter’s cached target. Cancellation appends no move. Only the actively dragged source stays alive offscreen, and per-frame feedback rebuilds mounted rows rather than the whole page. Native screenshots verify the exact-tag filter and reachable clear action at 390px/200% in both themes. Exact Android touch acceptance remains required.
