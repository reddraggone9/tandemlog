# 0002 — Progressive setup and a task-focused everyday interface

Status: accepted direction from Lee, 2026-09-30; implemented for the next experimental candidate. Extends [0001](0001-client-and-storage.md) without changing the canonical protocol.

## Goals and choices

Reduce setup decisions and daily visual clutter while preserving offline durability, provider-independent sync and clear recovery. Reliability and maintainability take precedence over making every platform look identical.

- Desktop **Start** creates `data/` within the platform application-support directory. It contains only canonical shared files; sibling private settings, writer identity and SQLite caches must not be synced. Start is explicit: opening the app, changing theme or canceling a chooser creates no default workspace. Choosing an existing folder remains secondary. Existing selections are retained; a missing/invalid saved folder produces recovery UI, never a silent replacement.
- Android retains **Start → system SAF folder picker**. Android app-private files are normally inaccessible to other apps and removed on uninstall; using them for canonical history would conflict with the foundational sync goal. No automatic inaccessible Android workspace or broad-storage permission is introduced. See [Android app-specific storage](https://developer.android.com/training/data-storage/app-specific) and [SAF](https://developer.android.com/training/data-storage/shared/documents-files).
- First-user creation is inline with autofocus, Enter submission and a disabled empty/whitespace action. This keeps setup continuous. An uncertain creation retains its identity and intended name through retry; selecting the user is persisted before the UI transitions. Later user management may still use a dialog.
- Settings contains System/Light/Dark (System by default) and infrequent workspace actions. Appearance is a local device preference, not shared domain history. Old folder/user-only preferences default to System. System follows Flutter's platform-brightness notifications; explicit themes override them.
- Desktop has one **Open data folder** affordance, with unavailable/failure handling. A duplicate Copy path button adds little value. Android tree URIs are not ordinary filesystem paths; manage them through Android Files or the sync app. Switching a workspace does not migrate or delete history.
- Everyday UI shows a compact task heading and the filtered open count; Everyone changes its label to All tasks. Remove decorative hero copy, encouragement subtitle, duplicate task headings and the permanent local-save/sync explanation. Brief onboarding/settings explanations supply context without occupying the task list.
- There is no permanent refresh/rescan control. Desktop file notifications are debounced (250 ms); all platforms have a 15-second foreground fallback and resume reconciliation. Watchers and timers stop when hidden/paused/disposed and are replaced when the workspace changes. Notifications are hints; ingestion still validates history. Contextual Retry appears for actual import errors. The app imports arriving files; it does not operate or verify the external sync transport.
- Desktop Enter/keypad Enter submits; Shift+Enter inserts another task line. Android regular Enter stays a newline; a supported IME submit action and the visible arrow submit. Ignore submission during active IME composition and repeated keydown. Empty lines are ignored. Uncertain captures retain identities and cannot be edited until canonical history is checked, preventing duplicate creation after a durable append/cache failure.

## Alternatives rejected and revisit triggers

Automatic workspace creation before Start makes the secondary chooser create unnecessary data. A common app-private Android default sacrifices interoperability and uninstall safety. Keeping both open/copy actions, a permanent refresh knob, static transport notices and marketing headers burdens routine capture with infrastructure and decoration. A background polling service adds battery/permission complexity without evidence it is necessary.

Revisit polling cadence with measured device/provider costs, not speculative framework changes. Add migration/export UI only with a concrete workflow and recovery tests. Review onboarding and everyday screens together as features grow: settings should reveal infrequent decisions; actionable errors must remain visible; task capture and accessibility must not be displaced by explanatory clutter.

## Accepted follow-up: completed browsing and theme feedback

Lee found transient Undo insufficient. Add a compact Open/Completed switch; use the same task rows with checked boxes and uncheck to reopen, rather than a separate Reopen action. Keep capture in Open and preserve its draft across the switch. Existing per-completion undo records support this without changing canonical format, and unseen concurrent completions remain intact.

Hide repeated Inbox subtitles while retaining the stored state. A future grouped Inbox for bulk captures/details is useful but not part of this candidate. Explicit snackbar surface/text/action theme colors replace the pale dark-mode popup observed in the demo.


## Accepted settings correction and description previews

Lee found the narrow vertical segmented theme control awkward. Replace it with a conventional Theme row showing the current local choice, opening System/Light/Dark radio choices. Cancel returns to Settings unchanged; choosing persists through the existing settings path. A section divider and consistent spacing separate appearance from folder management. This avoids a large pill-shaped control at narrow widths without adding density or appearance options.

Task titles continue wrapping in full. Description previews are lower emphasis and use a single ellipsized line, with embedded whitespace normalized only for display. Whitespace-only descriptions reserve no line; the editor preserves the complete original text. This improves scanning without truncating stored content or sacrificing accessible title scaling.
