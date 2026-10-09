# Disclosure layout — compact RC7 candidate preparation

Lee approved the disclosure-specific compact target on2026-10-09: approximately
28 logical pixels at normal text, growing with text (48px at200%), with minimum
width48. The task body and other controls retain48px targets. The count now has
6px bottom clearance, matching ordinary secondary text, and starts13px from the
title column instead of26px. The glyph edge and2px line gap remain unchanged.

The final actual Linux focused flow passes1/0 in30s across1200/390px,100/200%
text, with/without secondary text and expanded/collapsed. It checks lower-corner
activation, disjoint targets, paint-host containment, button/expanded semantics,
and Space/Enter. The retained resize/safe-inset workflow passes1/0 in12s; global
analysis is clean. The new flow is registered in the full native aggregate.
[Final log](compact-ripple-final-native.log), [retained resize log](compact-existing-responsive-native.log),
[analysis](compact-final-analyze.log), and [actual captures](compact-native/) preserve the evidence.

The first compact implementation clipped the left ink margin and then painted it
more faintly. [Initial independent review](independent-compact-implementation-review-initial.json)
identified the defect. A wider transparent Material paint host and standard
InkResponse circle paint clipped to the rounded border resolve both layers,
without extending the opaque clickable rectangle. Actual held pixels are uniform
across both margins. [Final independent implementation review](independent-compact-implementation-review-final.json)
accepts the correction with no must-fix findings.

The inspected [25.8-second native desktop demo](native-linux-pointer-demo.mp4)
shows centered pressed feedback, scripted expand/collapse, desktop/narrow
resizing and enlarged text, with visible pointer/input. The [demo receipt](desktop-demo-verification.json)
labels the actual Linux debug build and synthetic scripted flow; a private
standalone display enabled successful recording after three debug-launch failures
before assertions, whose logs remain preserved privately.

This source is versioned2026.10.2-rc.7/build51. [Independent editorial review](../rc7-editorial/independent-editorial-review.json)
accepts the concise notes and two source-bound images. Full signed-candidate
gates, exact Android acceptance and fresh publication quota are pending. Native Linux inspection is not Android acceptance. No canonical history,
cache schema, dependency or live synced user data change is included.

## Preserved earlier partial checkpoint (superseded)

Branch `fix/checklist-disclosure-spacing` starts from documentation checkpoint
`409c2b9a020f065c686cbddab395601e776106bd`. Published RC6/build50 and stable
v2026.10.1 remain unchanged. This modified debug source still displays RC6/build50;
it is not the published candidate or a new releasable build.

The arrow retains its visible title-column edge and vertical position. Its
reserved width and spacer are reduced, placing the count13px from that column
instead of26px. The partial source intended a short rounded rectangular ink surface centered
around both visible elements; the later neutral capture revealed clipping, as
recorded by the initial compact review above. Its paint margins leave the actual opaque button hit rectangle
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
