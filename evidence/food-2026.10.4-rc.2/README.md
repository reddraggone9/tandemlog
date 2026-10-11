# Food RC2 — candidate preparation

Approved scope: use the existing toolbar section identity for a responsive
Tasks/Food dropdown, remove Food expiration-certainty UI/display distinctions,
and fix short Inbox task bodies whose blank middle did not open the editor.
RC1 executable source is3d671c20c6a1f6bdc2a2082f9a00e820c34b8050; this work starts
from the final RC1 publication checkpoint12242ea7a36a4b6cab7db50fd2af5be444535f7d.
Version2026.10.4-rc.2/build61 exceeds published/successful-candidate floor60.

## Implementation and independent review

The section menu occupies the existing identity slot, uses check-circle/fridge
icons, retains48px targets and full accessible labels, and names/marks both menu
choices. The separate segmented row is gone. Host editor guards, counts/actions,
Settings and the unavailable Food escape remain. A measured Search-account shape
regression found during independent review was corrected and independently
tested with production Roboto through Search open/close at eight widths and
100–250% text.

Food's published `estimated` bool/null field, validation, constructor default,
canonical command keys, hashes and exact prepared records remain unchanged.
Display keys alone omit it; edits explicitly exclude the field and retain each
container's legacy value. New UI additions use null. Independent compatibility/
security review accepts the implementation, including mixed-group Inspect state,
late-arrival observed targets, frozen wire/hash, import vector and prepared-save
recovery checks. [Compatibility rationale](../../design/decisions/0014-food-inventory.md#accepted-simplification-expiration-date-only).

Four native Linux regressions established the short-title Inbox failure:
glyph taps opened the editor, while row-middle taps fell outside a27.932px body
at100% text (54.364px at200%). A fifth established the same long-press defect.
Stretching the title column expands only the body target. All five then passed;
independent production review and the existing compact-disclosure native flow
confirm separate checkbox/menu/drag/disclosure targets and keyboard behavior.
The regression author and production-fix reviewer are the same person; root
applied the production fix and independently ran the five GREEN cases.

## Evidence and remaining gates

All runtime work uses disposable synthetic profiles and canonical folders.
Actual Linux GTK/Flutter checks and screenshots cover both themes,1200/390/320px,
enlarged text, selected menu entries, dirty editor cancellation/discard, date-only
group editing and unchanged canonical bytes for navigation. Desktop demonstration
inputs use a visible X pointer and scripted Flutter taps. These are native Linux
checks; Android and Windows acceptance are not inferred from them.

The first full-unit run exposed twelve obsolete keyboard tests attempting the
removed certainty dropdown. Only that obsolete interaction was replaced with an
absence assertion; all remaining IME/error/draft checks remain and the twelve
focused cases pass. The final full unit/analysis and changed native runs are
recorded separately.

Exact candidate installer hashes and full hosted gates must be recorded after
the frozen build. Parent's actual Android build61 acceptance must cover section
navigation, large text/keyboard/editor protection, short Inbox body taps and
date-only Food behavior. Published RC1 and stable2026.10.3 remain unchanged.
No publication, stable promotion, import or user/trial data migration is part of
this candidate preparation. Original recovery is closed; no files/tasks deleted.
