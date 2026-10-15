# Visible task drop gaps

Status: accepted by Lee on 2026-10-15; implemented for RC.4/build80, release acceptance pending.

## Context and decision

Tasks hidden by completion, assignee or tags can lie between adjacent visible rows in the shared manual sequence. The previous upper-row/lower-row approach could choose different global anchors for one apparent gap and paint boundaries a few pixels apart. Lee approved resolving drops by the visible eligible neighbors while retaining relative insertion and existing durable event meaning.

Exclude every moving row before finding the neighbors in the same effective date/time, precision, Inbox and completion bucket. Between visible rows, insert immediately before the later row. At the beginning, insert immediately before the first eligible visible row. At the end, insert immediately after the last eligible visible row: the canonical anchor is its first non-moving global successor, which can be hidden or in another bucket. Only true global end uses a null anchor. Preserve the moving block's global relative order and every unaffected row's relative order. If the resulting visible order is unchanged, perform no write and retain existing Undo history.

One pure ID-based plan supplies both the canonical destination and visible paint edge. Both approaches to the same gap resolve identically. The marker prefers the later visible row's top, falling back to the earlier visible row's bottom when the later edge is offscreen; hidden successors never become paint anchors. Geometry remains guarded during autoscroll and sticky heading transitions.

Revalidate workspace, snapshot, selection, filters, source/target buckets and the inferred gap at the serialized write boundary using the fresh wall clock. A changed inferred neighbor cancels the move instead of silently retargeting it. Search retains its existing filter bypass and separate completion sections.

## Alternatives and consequences

Keeping pointer-half-dependent global anchors would preserve the reported ambiguity. A visible-slot permutation would move unaffected hidden rows and is rejected. The chosen relative insertion may change the moving rows' position relative to hidden neighbors; it never authors moves for those hidden rows. No-op drops avoid invisible-only history.

The existing v3 task.moved before payload, replay, hashes and Undo retain their meaning. Only new UI commands choose anchors differently; historical events and frozen fixtures are not rewritten. No storage migration or dependency change is needed. The paint-only hidden-gap prototype is superseded. Revisit if grouping policy changes or native acceptance exposes a destination/feedback mismatch.
