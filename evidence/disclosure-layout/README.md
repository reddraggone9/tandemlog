# Disclosure layout — isolated partial checkpoint

Branch `fix/checklist-disclosure-spacing` starts from documentation checkpoint
`409c2b9a020f065c686cbddab395601e776106bd`. Published RC6/build50 and stable
v2026.10.1 remain unchanged. This modified debug source still displays RC6/build50;
it is not the published candidate or a new releasable build.

The arrow retains its visible title-column edge and vertical position. Its
reserved width and spacer are reduced, placing the count13px from that column
instead of26px. A short rounded rectangular ink surface is centered around both
visible elements. Its paint margins leave the actual opaque button hit rectangle
at least48×48px, disjoint from the unchanged48px task body. Row edges and internal
padding are unchanged.

[Native measurements](native-partial-verification.json) cover1200/390px actual
Linux windows,100/200% text, with/without secondary text and expanded/collapsed
states. Ink centering, line gap, edges, target separation and lower-corner
activation assertions were reached. The [baseline](baseline-red.log) and [final native log](native-partial-red.log)
retain the red. The **final density assertion still fails**:
normal count-to-row-bottom clearance is26px versus6px for ordinary secondary
text. At200% text it is already6px. This is a partial result, not a passing suite.
The [held ink](held-rounded-ink.png), [narrow expanded](narrow-expanded.png) and
[enlarged desktop expanded](desktop-enlarged-expanded.png) are actual synthetic
native captures; the orange cross in the held capture is the test pointer.
No Android runtime result or completed new demo is claimed. The intentionally
red focused test is not registered in the native aggregate; it must be registered
and pass before any future candidate gate.

[Independent partial review](independent-horizontal-ink-review.json) accepts the
horizontal/ink changes only. [Independent feasibility review](independent-feasibility-review.json)
confirms the remaining conflict with [ADR0011](../../design/decisions/0011-one-level-checklists.md):
“Separate48px targets bound further vertical compression.” The requested
2px top gap +20px count +6px bottom gap requires28px height at normal text.
A disclosure-specific compact exception must be decided explicitly; its minimum
width can remain48px and its height grows with text. Borrowing a transparent
48px hit area from body text or the next row is not safe. A [concrete compact patch](compact-footer-proposed.patch) is
prepared for review, without adoption while that choice is pending.

The parent inspected the actual user screenshot. Its cloud materialization was
blocked, so the owner inspected the native reproduction rather than claiming
local access to those reference pixels. Original logs, probes and all recovery
files remain preserved. No main adoption, release, dependency, domain/storage,
canonical history or live synced data change accompanies this checkpoint.
