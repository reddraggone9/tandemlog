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

The complete three-date editor is long at 200% text, and 37 recurrence examples form a long menu. These are subjective follow-ups rather than observed failures; seek actual use feedback before another redesign. Manual ordering currently uses accessible move-up/down actions, not drag-and-drop. Tags can be edited; a general filter builder is outside this candidate.

Android keyboard, SAF/lifecycle, native text scaling and exact signed-artifact smoke remain separate gates. Linux screenshots cannot replace them. Private source import acceptance is separate from synthetic UI fixtures.
