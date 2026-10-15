# Shared Tasks and Food row surfaces

Status: accepted by Lee on 2026-10-15 and published experimentally as [2026.10.5-rc.3/build79](../../evidence/prerelease-2026.10.5-rc.3/publication/README.md) after native acceptance; stable Latest is unchanged.

## Context and decision

Tasks already used compact rows while Food added rounded cards and vertical gaps. Lee approved a shared flat surface with subtle dividers, consistent hover/press/focus feedback, and edge-to-edge row backgrounds below600px. Existing internal spacing and each module's controls remain responsible for content and interaction. Standalone content stays centered with a maximum width of1450px; search retains its existing16px horizontal inset. Matched native captures found identical search bounds at the same actual viewport, so no search alignment change is warranted.

A presentation-only ListRowSurface owns paint and hover observation. Existing action widgets own gestures, keyboard actions and focus. The Tasks body InkWell explicitly forwards secondary-pointer invocation to the existing guarded task context menu; the ancestor handler covers other row areas. Scope row ink styling to body InkWells so popup routes and child controls keep the app theme. Tasks retain selection, separate completion/menu/reorder controls and inline checklists; Food retains its own metadata, count, single-container actions and whole-group editor/menu.

The RC.3 insertion-line policy was reproduced on native Linux: opposite approaches painted boundaries3px apart but saved the same global task order. A single foreground indicator now derives its destination from the same global-before anchor as the drop command. It prefers a visible legal next anchor and otherwise uses the target edge. RC.3 retained distinct hidden global anchors. That policy is superseded for new UI drops by [visible task drop gaps](0024-visible-task-drop-gaps.md); historical events retain their meaning. Group headings, foreign ordering buckets, canceled drags and stale sessions do not advertise a valid insertion. Autoscroll can deactivate keyed rows before frame finalization. Geometry reads use the public element render-object getter with mounted, attached and laid-out checks; missing geometry produces no feedback and never bypasses command validation.

## Alternatives and consequences

Keeping Food cards would leave the approved density mismatch. Sharing a row gesture/focus controller would couple unrelated domain actions and risk checkbox/menu ownership; share paint only. RC.3 kept the existing global command anchor; the separately approved RC.4 visible-gap rule is documented in [ADR0024](0024-visible-task-drop-gaps.md). Retain internal padding rather than narrowing content/control targets to achieve edge-to-edge backgrounds.

The shared-surface decision changes no dependency, persistence or canonical event meaning. The subsequent approved UI ordering policy is in ADR0024. Revisit if another module needs the surface or native acceptance identifies an interaction/accessibility defect. Exact build/platform tests and visual qualifications belong in runtime evidence.

## Task body ink refinement — approved2026-10-15, build80 candidate

The Task body retains its existing hit area, tap/long-press/secondary callbacks and focus policy. Its InkWell overrides Flutter's public paint-rectangle hook to cover the nearest main ListRowSurface, including leading and trailing regions. A private layout-neutral RenderProxyBox marks those bounds and paints the existing foreground hover tint/focus border. It excludes dividers and expanded checklist panels. Child checkboxes, disclosure, menus and drag handles retain their own actions and local feedback. No ancestor tap recognizer or additional Material controller is introduced.

The rectangle callback re-finds the current marker and transform for each paint, with attachment/layout, finite and singular-transform checks. This follows Flutter's TableRowInkWell extension pattern. Painting the existing foreground tint in the proxy also avoids ListTile's debug heuristic incorrectly classifying a translucent foreground DecoratedBox as an opaque background. Native tests require an active press before comparing row-edge pixels; independent control ownership and stationary drag-handle click/long-press remain covered.

The renewed short-window drag report led to the separately approved [visible-gap rule](0024-visible-task-drop-gaps.md), implemented alongside this ink correction. Continuous native tests cover both halves through real autoscroll and a pinned heading, compare marker pixels with adjacent-row geometry, and verify identical saved global results and Undo with hidden completed, assignee and tag-filtered rows. Exact-source results and remaining platform gates are recorded in [candidate evidence](../../evidence/prerelease-2026.10.5-rc.4/README.md).
