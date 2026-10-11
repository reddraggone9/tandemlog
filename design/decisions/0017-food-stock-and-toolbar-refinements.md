# Food Stock and toolbar refinements

Status: accepted by Lee on2026-10-11 and implemented for RC2/build62 with
independent source review and native Linux checks. The full frozen candidate and
exact Android acceptance remain pending.

The expanded batch also includes[Food session Undo](0018-food-session-undo.md).
Expanded group actions retain the same two header control slots and title/date
width as the collapsed group. Overflow appears at the trailing edge of the
existing container-count/location details row, preserving48px targets without
adding an empty vertical row.

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

## Manual expiration correction

Lee additionally requires an expiration date for manual Add and manual detail
editing. Undated historical/imported records remain readable for the Inbox and
future receipt automation; this does not introduce that automation or make the
published canonical date field required. Saving an existing undated record
manually requires a date, while Cancel preserves it. A valid date cannot be
cleared by manual editing. Bulk fieldwise edits preserve untouched dates and
must not silently convert mixed or late-arriving date values.

Reuse the underlying Tasks calendar input/picker, including its focused blank
format hint, locale and keyboard behavior. Required validation belongs to the
Food form, without changing optional Task dates. Remove optional suffixes from
Food labels while keeping Brand, Container size, Location and Retention reason
optional. The earlier manual-editor invitation to leave expiration blank is
superseded; existing undated reading and projection remain supported.

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
