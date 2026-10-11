# Food RC2 — build64 replacement candidate;62/63 held

Build62 is held after actual Android calendar clipping at320dp/200%. Build63 was
cancelled before signing after a pending-date resize reset. Reviewed replacement64
uses unchanged app/test bytes from11dd0f6 and passes26 focused/14 Linux native
checks, preserving date selection across responsive layouts and controller-owner
lifetimes. [Build64 evidence](calendar-build64/README.md) retains exact source,
reviews, logs and captures. Initial preparation38133720009 was cancelled before signing to correct archive
file extensions; full repository analysis passes after the evidence-only rename.
Replacement full candidate and new exact Android gates remain pending. The build62 evidence below keeps its original source attribution.

Approved scope: use the existing toolbar section identity for a responsive
Tasks/Food dropdown, remove Food expiration-certainty UI/display distinctions,
and fix short Inbox task bodies whose blank middle did not open the editor.
RC1 executable source is3d671c20c6a1f6bdc2a2082f9a00e820c34b8050; this work starts
from the final RC1 publication checkpoint12242ea7a36a4b6cab7db50fd2af5be444535f7d.
The initial three-change build61 candidate was cancelled after expanded scope
approval. It is retained as an intermediate checkpoint and is ineligible for
handoff or publication. The complete batch targets2026.10.4-rc.2/build62:
default full-width Tasks Search/explicit Add with outgoing-value clearing and
submitted-write protection; combined Food Stock/Inbox; local-calendar expiration
text colors; Food Filter/account-menu parity and required manual expiration through the shared
Tasks date control; a50-action selective Food Undo stack; stable expanded-group
control geometry; and the Flatpak name/catalog and sandbox-private-profile fixes.
ADR0016/0017/0018 and ADR0013 record the approved
behavior. Implementation and independent source reviews are complete; final local checks
pass956 unit tests and13 changed native flows. All final hosted gates and exact
original-artifact verification now pass; parent later reported several affected Android passes but the calendar finding
holds this artifact. [Historical build62 handoff](candidate/build62/README.md) records source7ae,
run38121211371, the three original archives and owner-signed APK identity. [Expanded source-qualified closure](expanded-build62/README.md) records
the full approved scope and disclosed Undo compatibility boundary.

## Initial three-change checkpoint — source00594c1

The following implementation/review paragraphs and existing early captures
apply to the initial checkpoint. They do not attest the expanded build62 tree.

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

Exact candidate installer hashes and all full hosted gates are recorded in the
[final manifest](candidate/build62/artifacts/manifest.json). Parent's actual build62 Android run passed several affected workflows; its
calendar defect requires exact build64 picker acceptance. Remaining SAF child
switch/return, workspace-cleared Undo and cold new-v2 fixture replay are recorded
in the [native contract](../../design/food-native-acceptance.md). Published RC1 and stable2026.10.3 remain unchanged.
No publication, stable promotion, import or user/trial data migration is part of
this candidate preparation. Original recovery is closed; no files/tasks deleted.

The [exact handoff](candidate/build62/README.md) qualifies supplemental Android RELRO
static guidance: affected libraries are byte-identical in stable56, RC1/60 and62;
no runtime failure is established. Parent accepted the pre-existing limitation,
not a new RC2 gate or full-APK 16 KB compliance claim. Exact Android UI QA and
publication clearance remain pending; no toolchain upgrade was added.
