# 0025 - Responsive Food editor pane

Status: approved by Lee on 2026-10-15 and published as
[stable2026.10.6/build85](../../evidence/stable-2026.10.6/publication/README.md), Latest, after qualified exact native acceptance, authorized stable promotion and independent public-byte verification. [Experimental RC.1/build84](../../evidence/prerelease-2026.10.6-rc.1/publication/README.md) remains available.

## Context and decision

Ordinary Food Edit, Add and Add another use the existing Tasks geometry: a 420 px
pane plus 1 px divider at available section widths of at least 900 px, and a
guarded dialog below that breakpoint. Retain the 1450 px outer cap and full-width
toolbar; the left inventory receives the actual remaining width. Bulk Brand/
Location editing retains its existing modal presentation.

One keyed Food session and keyed form subtree retain controllers, caret,
composition, focus and captured commands across resizing. EditorSurface shares
only presentation geometry with Tasks. The host retains durability/navigation
ownership. Finishing removes the owning session instead of popping the page;
editorDone completes after input disposal, including whole-page disposal.

Dirty row/Add/section/workspace transitions join one existing close decision.
Keep editing cancels them. Newer requests and host navigation retain revision
guards; targets/workspace are checked again after waits. Save is admitted once
while the editor owns the current route. An accepted held save finishes after
any auxiliary overlay closes. Calendar/other auxiliary routes defer navigation
and wake it on return; the owned discard dialog remains joinable.

Wide keyboard traversal can return to list/toolbar. Narrow dialogs exclude
background focus/semantics and contain traversal. Escape dismisses field
suggestions/transient controls first, then guards the editor. Actions remain
reachable while title, fields and errors scroll at enlarged text.

Add another copies name/brand/size/location, starts count at 1, and leaves
expiration blank and focused and retention blank. Edit preserves retention and
legacy certainty values. Row Remove/Restore retains its independent command and
does not commit/discard the draft. A save whose targets became unavailable asks
for fresh selection.

## Alternatives and consequences

Rejected: replacing dialog routes on resize, separate wide/narrow drafts, and a
generic framework combining validation or persistence. Keeping every Food editor
modal would not meet the approved workflow. Expanding bulk editing or adding
auto-save semantics is outside this change.

No schema, canonical event/Undo meaning, dependency, synced preference or new
permanent file changes. Preserve historical v3 logs and exact prepared-save retry.
Synthetic profiles, media and raw diagnostics stay private.

## Acceptance and revisit trigger

Require resize/focus/dropdown/calendar, duplicate callback, dirty navigation and
durable-retry regressions; full hosted gates; exact artifacts; native desktop/
Android demonstrations; both themes/enlarged text; canonical-byte/Undo/replay
checks; and independent source/UX/editorial review. Record source-qualified
results in candidate evidence. Revisit if a concrete third editor needs this
policy or native accessibility/short-window evidence finds a limitation.
