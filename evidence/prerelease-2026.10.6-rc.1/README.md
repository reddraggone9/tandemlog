# Responsive Food editor - 2026.10.6-rc.1/build84 preparation

Approved wide Edit/Add/Add another uses the Tasks 900 px/420 px policy inside the
existing outer cap, retaining one keyed draft through narrow dialogs. Bulk
Brand/Location stays modal. [ADR0025](../../design/decisions/0025-food-responsive-editor-pane.md)
records lifecycle, alternatives, accessibility and compatibility boundaries.

Focused and native-library host tests cover navigation/auxiliary routes, repeated
callbacks, resize/caret/composition/focus, Add another, retry, independent controls
and enlarged short layouts. Full local/hosted, exact-artifact and native release
acceptance remain pending. Private profiles/diagnostics/media stay outside Git/CI.
Stable2026.10.5 remains Latest. No publication/stable promotion claimed.
Base64 and all dependencies remain unchanged.

Build82 passed local formatting of all311 Dart files, analysis, all1121 native-backed unit tests and all85 tooling checks. Independent source/editorial review accepted that implementation and scoped notes. Build83 passes formatting, clean analysis, all27 affected pane/host/autocomplete checks and all85 tooling checks. Independent review accepts the test boundary correction; full hosted and exact-native acceptance remain pending. The complete native aggregate remains pending; full hosted, exact-artifact and native release acceptance remain pending. Initial lab-configuration failures are retained privately and are excluded from acceptance claims.

Build83 replaces the held build82 candidate after a native test assumed mobile selection behavior when a calendar returned focus on desktop. Matched no-resize current/stable controls establish the existing platform default. Exact draft/controller/focus/composition checks across responsive resizing remain; the calendar assertion now distinguishes resize preservation from its later focus-restoration policy. Application source and release notes are unchanged. Full replacement hosted and exact-artifact/native acceptance are pending.

Build84 corrects an embedded-editor inset ownership regression found in the native narrow keyboard matrix: mouse activation of an invalid Save/Add ended field focus and stopped the page reserving the still-open keyboard. A matched current-fails/stable-passes control establishes the regression. An active embedded editor now reserves keyboard space independently of text focus, while auxiliary routes retain their own inset ownership. A dedicated mouse-input regression keeps exact no-write/draft/error/action-bound checks; the original native keyboard matrix remains unchanged. Renewed full local/hosted, native and exact-artifact acceptance are pending. Release notes remain unchanged.

Build84 passes all311 Dart files through formatting, clean analysis, all1122 native-backed unit tests, all85 tooling checks and all40 affected component/host/keyboard checks. Actual native GTK passes all14 pane cases plus the unchanged12-variant narrow keyboard matrix. Independent source/regression/editorial review accepts the one-condition correction. Complete hosted native, original-artifact and manual release acceptance remain pending; partial/cancelled earlier runs are not claimed as complete passes.
