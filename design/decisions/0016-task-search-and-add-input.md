# Task Search and Add input

RC2/build64 milestone: exact hosted/artifact and parent Android native acceptance
complete; publication authorized, final readiness/public verification pending.
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

Explicit mode changes clear the outgoing value. Leaving Search immediately
removes its text query while keeping the chosen assignee/status/upcoming/tag
filters. Switching away from unfinished capture discards that unsubmitted text
without confirmation or hidden storage. Task-editor unsaved-change protection
remains separate. Pending or uncertain submitted writes block the mode switch
until their existing confirmation/retry path resolves; identity and error
ownership stay with that path.

Default Search receives no automatic keyboard focus on startup or section
navigation. Deliberate Add focuses the mounted entry; keyboard Search focuses
Search. Selection overlays may temporarily hide the active input while retaining
that same mode's buffer, focus exclusion and existing editor protection.

## Alternatives and consequences

Keeping two inputs would use more vertical space and obscure the primary action.
Retaining hidden inactive values would leave invisible filtering or capture
drafts; Lee explicitly chose clearing instead. A confirmation on every mode
change would obstruct the requested simple toggle. The accepted tradeoff is that
an unsubmitted capture is discarded when the user deliberately leaves Add.

## Revisit

Revisit after actual desktop/Android use if users lose drafts unexpectedly, cannot
discover Add, or the fixed input/selection slot becomes too dense at enlarged text.
Stable promotion requires Lee's acceptance after normal candidate gates.
