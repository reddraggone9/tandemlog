# Historical recurring text: decision required

Status: proposal. The current implementation rejects mixed initialization before
receipt preparation. Logs, child work and original meanings are preserved.

## Concrete case

Before shared text, a weekly task **Review plan** was completed. Its deterministic
child already exists and was edited to **Review next plan**. Shared-text setup
then seeds that child as its own legacy context. Lee reopens the old parent from
Completed, edits it and completes it again.

The approved new-text path targets the same child UUID but derives its context
from the parent's original native identities. The existing child's legacy seed
has different identities. Equal rendered words would not make those histories
interchangeable. Rebasing would invalidate child packets, retained deletions or
Undo ownership; appending a second child would violate the one-successor rule.
The current error is therefore a compatibility guard, not a corrupt-cache case.

## Options

| Policy | Behavior | Cost and consequence |
| --- | --- | --- |
| Keep the explicit block | Existing child remains usable; reopened old parent cannot be completed through the new inheritance path. | Smallest preview limitation, but leaves a real Completed/reopen workflow blocked. |
| Explicit historical recompletion | Complete the parent while retaining the already-initialized child's context, text and schedule. | Needs a new required canonical record and clear confirmation; no parent text inheritance for this historical edge. Forward new children retain the approved union behavior. |
| Explicit new series | User starts a new recurring task identity and keeps the old parent/child as history. | Avoids identity mixing but changes the series relationship and creates an extra user step. |

Recommendation: an explicit historical recompletion that retains the existing
child, with a confirmation such as **The next occurrence already exists. Keep
it and complete this historical task?** Do not silently reset its text/schedule,
alter any old completion record or turn off recurrence. A child already completed
or deleted also needs a clear policy; this proposal does not invent a replacement.
Lee must accept this behavior before implementation. Keep the present guard until
then; any preview retaining it must disclose the limitation.

Required verification for the chosen policy: child edits/drafts and scoped Undo,
concurrent historical recompletions, duplicate/reordered delivery, completed or
deleted child, completion retraction/protection, zero-log warm reopen and exact
cold replay. Frozen scalar completion, context, hash, clock and UUID meanings
remain unchanged. No coordinated history rewrite is proposed.
