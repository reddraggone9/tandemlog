# Food Stock and toolbar refinements

Status: accepted by Lee on2026-10-11; implementation and native acceptance pending.

## Context

Food's separate Inbox and view tabs consume persistent space. Lee wants missing
dates highlighted within Stock and action-bar parity with Tasks. The old Obsidian
date colors are an established urgency cue whose calendar thresholds were verified.

## Decision

Place unretained undated active food in an Inbox group at the top of Stock.
Omit the group and its guidance when empty. Dated unretained stock remains
globally sorted by expiration. Retention takes priority: undated retained food
appears only in Retained and keeps its missing-date cue. Keep all group headers,
guidance and rows in the scroller at narrow/enlarged-text layouts.

Replace persistent Stock/Retained/Deleted tabs with a toolbar Filter control
matching Tasks. Retain selected-view indication, a meaningful filter badge,
accessible responsive labels and touch targets. Retention-reason assignment and
filter autocomplete remain available. Normal search covers all active food and
ignores ordinary view/reason filters; Deleted is an explicit separate search
scope and never leaks into normal search. Settings sits in the existing account
menu as in Tasks. Food retains app-wide user switching without adding Food user
attribution or user-specific inventory filters.

Color expiration date text by the current local calendar day: overdue red,
today through two days ahead orange, three through six days ahead yellow,
and seven or more days ahead normal. Retention does not change the color.
Use theme-readable tones, retain the actual readable date, and refresh at local
midnight/resume without changing durable records. Calendar boundaries must be
safe across daylight-saving transitions; do not derive calendar days from
elapsed24-hour durations.

## Alternatives and consequences

Keeping the separate Inbox tab hides everyday attention items behind navigation.
Duplicating retained undated entries in Stock would contradict retention's
established exclusion and show the same physical container twice. A sidebar or
extra persistent input/control bar would exceed this bounded refinement.
Copying raw named CSS colors could make date text unreadable in a theme.

This changes presentation and view partitions only. Existing container IDs,
contents, dates, legacy certainty, operation bytes and history are retained.

## Revisit

Revisit after actual desktop/Android use if missing-date retained food is hard
to find, view state/search scope is unclear, or enlarged-text controls obstruct
rows. Stable promotion still needs Lee's acceptance.
