# Task Search and Add input

RC2/build64 milestone: published as prerelease/not-Latest after exact hosted,
artifact, parent Android native and independent readiness acceptance. Actual public
installer identities/source/notes/signature and prior-release preservation verified.
[Current accepted evidence](../../evidence/food-2026.10.4-rc.2/candidate/build64/README.md).

Historical preparation status (superseded by the build64 milestone above): accepted by Lee on2026-10-11 and implemented for RC2/build62 with
independent source review and native Linux checks. The full frozen candidate and
exact Android acceptance remain pending.

## Context

Tasks currently gives permanent prominence to capture while search opens inside
the action bar. Lee wants search to be the main everyday input without adding
another persistent row or changing the hierarchy between desktop and phone.

## Decision

Default to one full-width **Search tasks** input in the existing input slot.
The toolbar's plus action switches that slot to **What needs doing?**; its action
then becomes a magnifier that switches back to Search. Wide actions may include
**Add**/**Search** labels like Filter; narrow actions retain the icon, full
accessible description and a48px target. Entry retains its own submit control,
Enter/Shift+Enter behavior and active mode after successful capture.

Explicit mode changes carry the current typed value into the other input, including
its selection, after the existing editor-close/readiness guards pass. Lee revised
the original clearing choice on 2026-10-26 after repeatedly typing in the wrong
mode. This is one carried input, not two independent hidden drafts. Search is
active only in Search mode; Add restores the chosen filters without a hidden text
query. Successful capture still clears its submitted text. Pending or uncertain
submitted writes block switching until confirmation/retry resolves. The switch
itself never submits a task. Task-editor dirty-draft protection stays separate.

Default Search receives no automatic keyboard focus on startup or section
navigation. Deliberate Add focuses the mounted entry; keyboard Search focuses
Search. Selection overlays may temporarily hide the active input while retaining
that same mode's buffer, focus exclusion and existing editor protection.

## Alternatives and consequences

Keeping two inputs would use more vertical space and obscure the primary action.
Carrying the active value addresses wrong-mode typing without another row or
confirmation. Inactive controller values never authorize invisible filtering;
each real toggle replaces the destination value with the current outgoing text.

## Revisit

Revisit after actual desktop/Android use if users lose drafts unexpectedly, cannot
discover Add, or the fixed input/selection slot becomes too dense at enlarged text.
Stable promotion requires Lee's acceptance after normal candidate gates.
