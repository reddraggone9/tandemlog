# Food Stock and toolbar refinements

RC2/build64 milestone: published as prerelease/not-Latest after exact hosted,
artifact, parent Android native and independent readiness acceptance. Actual public
installer identities/source/notes/signature and prior-release preservation verified.
[Current accepted evidence](../../evidence/food-2026.10.4-rc.2/candidate/build64/README.md).

Historical preparation status (superseded by the build64 milestone above): accepted by Lee on2026-10-11 and implemented for RC2/build62 with
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
matching Tasks. The approved toolbar parity follow-up shares action sizing,
vertical centers, header insets and progress placement between sections. Wide
Add/Filter use the existing Tasks outlined treatment; active filters use its
small dot rather than Food numeric counts, without moving controls. Retain
selected-view indication, accessible active-filter labels, responsive text and
full targets. Pure presentation helpers own the common control policy while
Stock/Retained/Deleted and Task filter contents remain distinct. Retention-reason
assignment and filter autocomplete remain available. Lee's subsequent explicit
search correction supersedes the separate Deleted search scope: **Search food**
always searches all matching active, retained, undated and deleted food, pausing
every saved view/reason filter and its active dot. Active results preserve their
usual order. Deleted matches follow in a separate sticky **Deleted** section,
using the existing Tasks native heading behavior and deletion-recency ordering.
They have muted, struck-through titles and explicit Restore actions; searching
never restores them. Active/deleted containers with identical descriptions are
grouped separately and keep distinct expansion state. Clearing search returns
to the saved view/reasons; changing Filter during search changes that saved view
without narrowing the current matches. Settings sits in the existing account
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

Keeping Deleted as a separate search scope concealed matching food and diverged
from Tasks' inclusive search. Mixing active/deleted containers by description
would give a group the wrong commands; status partitioning precedes descriptive
grouping. Reusing the native pinned heading avoids a separate overlay and keeps
accessibility text measurement and push-off behavior consistent with Tasks.
This is a projection/presentation change; canonical operations, clocks, IDs and
historical meanings remain unchanged.

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


## Subsequent approved RC3 refinements

Wide Undo also carries its label when other toolbar labels fit. Shared date
fields use the same internal label/value inset as ordinary inputs; the Tasks
responsive date-row measurement includes that inset. Suggestions, Brand/Location
filters, exact-container bulk editing and conservative expansion cleanup are
recorded in [ADR0019](0019-food-field-editing-and-contents-defaults.md).
Lee's explicit RC-only contents removal supersedes the earlier unspecified
state; numeric partials and measured amounts remain supported.
