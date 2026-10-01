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

## Consolidated filter header (code 13)

Lee identified excessive vertical space from permanent user/upcoming/status/tag controls. The revision puts active identity and Settings in the top-bar user menu and all existing filter choices in one scrollable dialog with direct choices and fixed Reset/Done actions. A visible dot and accessible tooltip announce nondefault filters. Identity stays distinct from assignee scope; Reset keeps identity and restores default scope. Settings remains reachable before identity setup and during recovery.

Same-fixture native Linux comparisons use twelve sanitized tasks, a long username and an 820px-high viewport, both themes. At 1000px/100%, capture top moves 216→112px and fully visible rows 7→9; at 390px/100%, 253→112px and 5→7; at 390px/200%, 548→186px and 0→2. Final screenshots confirm top-right identity, bounded ellipsis/full tooltip, wrapping names/tags in the dialog, scrolling options and reachable footer actions. These are Linux density proxies, not Android screenshots.

Affected native checks cover composition, reopen/reset, identity/settings access, draft selection, real Tab/arrow navigation and Escape. Header geometry is stable across both status labels at six viewport/text-scale combinations. Existing stationary edge drag and stale/cross-bucket guards pass. Final aggregate and exact Android candidate gates are recorded separately.

## Searchable tags and adjacent metadata (code 14)

Lee requested bounded tag selection and less wasted desktop row space. The same filter dialog now has case-insensitive search over exact-case tag choices, a selected-tag summary and clear action. Search text alone does not alter the filter. Results use a bounded lazy list, including when hundreds of labels exist; Reset also clears the search. Dialog dismissal retains the applied filter but discards the transient query.

Wide rows place naturally sized titles beside quieter dates/tags; long titles and metadata wrap, and narrow or enlarged-text layouts put metadata below the title. A one-line description is separate only when present. In the reviewed 820px-high sanitized fixture, ordinary dated/tagged desktop rows shrink 64→48px and fully visible tasks rise 9→11. At 390px/100%, ordinary rows shrink 64→56px but the long-tag fixture still shows eight tasks. At 390px/200%, untruncated stress-case metadata takes more space than the previous ellipsized preview: one versus four complete rows. This is an explicit readability tradeoff, not a claim of universal density improvement. Both themes, long pinned deadlines, bare tasks and multiline descriptions were inspected natively on Linux; Android remains an independent gate.

The handle's touch long-press tooltip recognizer is disabled while its mouse-hover help and accessibility label remain. The held-touch regression verifies drag initiation after 700ms, stationary edge movement, cancellation and hidden ranks. A proper Android drag moves beyond touch slop before holding at the edge; exact replacement-APK verification is pending.

## Group-date repetition (code 15)

Lee requested times-only metadata inside a day group, including when original dates differ because of overrides or bounds. The pure presenter hides all calendar-date text in those rows; role/time/zone distinctions remain. Full dates stay in the editor and no deadline or sort fact changes. Date-only fields contribute no metadata, preventing empty labels or separators. Someday has no displayed day, so the presenter can retain date details there. Light/dark wide/narrow screenshots and focused native workflows verify the resulting layout. The earlier differing-date exception was superseded before final candidate publication.

## Localized list times (code 16)

Lee requested local clock times without timezone labels in the list. Pinned values resolve through the same gap/fold policy as the task view, then convert to its observed device zone. Floating times stay floating; date-only values keep their precision. The successful projection's cached zone keeps rows and headings consistent during resume/reload, with no live per-row time reads. All original dates/zones remain in the editor and canonical events. Reviewed wide/narrow Light/Dark screenshots show compact Due/Scheduled clock values without calendar/zone clutter. Eight presenter regressions include midnight rollover, zone changes, DST gaps/folds and bounded-group consistency; two affected native workflows pass.
