# Date/time stacking investigation — 2026-10-04

Status: isolated, tested presentation candidate on `experiment/date-time-layout`;
parent review and Lee's visual acceptance remain separate. Frozen base:
`e2df9f1de036077d4db7b91fb359f42d204e3d83`. No main push or release.

Lee authorized investigating whether narrower date/time controls can postpone
stacking. Native Linux measurements support reducing enlarged-text stacking,
but do not support materially reducing the normal-text limit while preserving
populated values, the 5:3 date/time proportion and 48px buttons. The previous
breakpoint multiplied fixed icon/padding space along with text size.

The candidate measures the supported ISO date value and YYYY-MM-DD hint, plus
populated 24-hour time and its blank HH:mm hint. A blank Time has no clear icon;
its hint does not reserve one. Padding narrows to 8px at the leading edge.
Calendar and clear buttons explicitly retain 48px targets. Bulk independently
reserves each 48px apply checkbox. The 12px gap and 5:3 split remain.

| Available row width | Previous limit | Measured candidate limit |
| --- | ---: | ---: |
| Single, 100% text | 300px | 304px |
| Bulk, 100% text | 400px | 432px |
| Single, 200% text | 600px | 443px |
| Bulk, 200% text | 800px | 541px |

These are observed Linux font/theme limits, not universal fixed constants.
The slightly larger normal-text budgets include full populated controls and
explicit 48px targets. At 200%, single editing at 520px viewport and bulk at
640px viewport now keep the two controls together, with both values visible.
Before/after native screenshots show the saved vertical space. Narrow rows
still stack. The date hint, rather than the populated date, determines the
single enlarged-text boundary; omitting it would have understated the limit.
There are no supported localized date/time formats or translated field labels
in this editor, so no invented locale test is claimed.

Evidence: [native screenshots and receipt](../evidence/date-time-layout/receipt.json).
All 16 selected native GTK screenshots were visually inspected: paired
360/520px single and 500/640px bulk viewports at 100/200%, plus exactly 1px
above/below each candidate limit. The focused test's actual logical viewport
is 1000px high. Synthetic tasks and the standard Material theme isolate the
changed editor controls. Existing full-app native tests additionally cover
light/dark app themes and 1200/390/320px geometries. Black frames from an early
comparison harness were rejected; only the repaired, inspected captures are
included. Original Library reference pixels remain unavailable, so no original
image comparison is claimed.

Validation: 32 editor/focused widget tests and analysis pass. The native boundary
flow passes for single/bulk at 100/200%, verifies full populated RenderEditable
text space, 48px clear targets, blank-time availability, independent clearing,
focus and composing drafts through resize, invalid/valid time entry and draft
retention. Composing text is injected into Flutter's controller to check resize
preservation; this is not a real Android IME claim. The existing native app flow
passes keyboard focus, simulated keyboard insets, timezone/date-only/midnight
precision, clean Cancel, canonical history preservation and Save.

A pointer-visible native Linux recording accompanies the receipt. Exact Android
workflow inspection and its demo remain pending; Linux evidence does not establish
Android or Windows acceptance. No persistence, validation, protocol, or release
behavior changes.

Recommendation: review this content-based enlarged-text behavior in the next
isolated preview. Do not lower normal-text constants simply to force a narrower
row: the measured values and accessible controls need that space. Revisit after
real device use, a supported locale/font change, or changes to input decoration.
