# Shared tag input

Status: Lee approved shared B-style implementation on 2026-10-08 at13:01:08UTC.
Implementation, independent review and native acceptance are in progress on
`feature/shared-tag-input`, isolated from the frozen checklist acceptance source.

## Context and choice

The task editor and bulk fields used space-separated text, while Filter already
provided selected chips and an accessible, keyboard-bounded suggestion overlay.
Two lightweight native Linux trials were shown before adoption. Lee preferred B
and requested a common implementation and interaction with Filter.

One shared component places removable selected chips above a full-width query.
Reuse Filter's established overlay, keyboard/inset positioning, focus, clear,
expand and accessible result behavior. Keep its public dropdown/query dismissal
API through a thin context wrapper. Do not keep a second autocomplete overlay
from the trial alongside the production implementation.

## Context policies and draft safety

All contexts suggest ordinary tags from the current space, preserving exact
spelling and sorting/searching without case sensitivity. Editing still supports
multiple tags. Task editing and bulk Add can stage new names, validated by the
existing domain rules before Save/Apply. Bulk Remove and Filter select existing
tags only; an unmatched removal query remains editable with a visible error.
Selected tags and query text are separate controlled values.

Editor chips and pending query are draft changes. Save includes unfinished valid
entry without replacing selected tags. Cancel from the unsaved-change guard
retains the draft; Discard writes nothing. Do not commit unfinished IME
composition. Bulk Add/Remove remain separate tag deltas, retaining the existing
field-specific schedule/assignee Apply controls. Filter retains immediate
match-any selection, writes no history, and never creates tags.

## Alternatives, consequences and revisit

Trial A kept chips inline with the query; B gives the query predictable width
at narrow sizes and makes selected tags easier to distinguish from typed text.
Separate editor/filter widgets would duplicate overlay/accessibility fixes and
invite drift. A shared visual control with explicit creation policy preserves
the different save boundaries without requiring different interactions.

The extra chip row consumes space only when tags are selected. Inspect desktop,
narrow, enlarged text and IME workflows, including long names and validation.
Independent correctness/accessibility review and actual native Linux visual
evidence are required; Android affected-flow acceptance remains a separate gate.
No persisted tag meanings, canonical v3 bytes, native text implementation or
dependency versions change. Owner: Tandemlog implementation coordinated with
Lee. Revisit after actual native use or before expanding tag semantics.
