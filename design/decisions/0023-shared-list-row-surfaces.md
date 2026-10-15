# Shared Tasks and Food row surfaces

Status: accepted by Lee for the following experimental RC on 2026-10-15; native acceptance pending.

## Context and decision

Tasks already used compact rows while Food added rounded cards and vertical gaps. Lee approved a shared flat surface with subtle dividers, consistent hover/press/focus feedback, and edge-to-edge row backgrounds below600px. Existing internal spacing and each module's controls remain responsible for content and interaction. Standalone content stays centered with a maximum width of1450px; search retains its existing16px horizontal inset. Matched native captures found identical search bounds at the same actual viewport, so no search alignment change is warranted.

A presentation-only ListRowSurface owns paint and hover observation. Existing action widgets own gestures, keyboard actions and focus. Scope row ink styling to body InkWells so popup routes and child controls keep the app theme. Tasks retain selection, separate completion/menu/reorder controls and inline checklists; Food retains its own metadata, count, single-container actions and whole-group editor/menu.

The reported double insertion line was reproduced on native Linux: opposite approaches painted boundaries3px apart but saved the same global task order. A single foreground indicator now derives its destination from the same global-before anchor as the drop command. It prefers a visible legal next anchor and otherwise uses the target edge. Hidden filtered tasks remain part of global order: two visually adjacent approaches can have different actual anchors and must not be collapsed. Group headings, foreign ordering buckets, canceled drags and stale sessions do not advertise a valid insertion.

## Alternatives and consequences

Keeping Food cards would leave the approved density mismatch. Sharing a row gesture/focus controller would couple unrelated domain actions and risk checkbox/menu ownership; share paint only. Inferring destinations from visible adjacency would silently change hidden-task order; use the existing command anchor instead. Retain internal padding rather than narrowing content/control targets to achieve edge-to-edge backgrounds.

No dependency, persistence, canonical event, grouping or ordering semantics change is approved. Revisit if another module needs the surface or native acceptance identifies an interaction/accessibility defect. Exact build/platform tests and visual qualifications belong in runtime evidence.
