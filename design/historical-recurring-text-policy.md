# Historical recurring text: accepted preservation policy

Status: Lee approved completing the historical parent while retaining the existing
independently initialized successor unchanged. Implemented on the recovery branch;
independent review and candidate platform acceptance remain pending.

`task.completedKeepingSuccessor` is a required additive v3 record with
`completedAt` and `retainedSuccessor: {id, completion, hash}`. It binds the earlier
completion that selected this deterministic child, but contains no child
snapshot or text inheritance. It completes only the parent and leaves the child's
context, text, notes, schedule, tags, completion/deletion status and manual position
unchanged. Concurrent historical recompletions are independent parent completions
that retain the same child; later parent edits have no path into that child.

The unreleased shared-history implementation also recognizes an earlier native
initializer when durable successor task or checklist activity established its
independent work. That activity remains protective after Undo or deletion. An
untouched native successor continues to use ordinary forward/concurrent inheritance.
The original scalar eligibility rules remain unchanged. See the
[native checklist regression](../evidence/historical-checklist-recompletion/README.md)
for the Android finding, production-command reproduction and acceptance status.

Ordinary forward native recurrence retains its observed-text union behavior.
Explicit attempts to initialize the historical child through that inheritance
path still reject before receipt preparation. Existing scalar/native records and
hashes keep their original meanings; no identity rebase or history rewrite occurs.

Undo/reopen retracts or cancels the new parent completion, with the historical
child retained. Its independent draft and scoped Undo survive. Completed or deleted
children remain completed/deleted. The UI uses its existing completion/Undo feedback
and reports that the next occurrence was kept. No extra confirmation was part of
Lee's accepted behavior; the earlier proposal below is historical rationale.

Known source ID/hash/type/entity/child/clock mismatches fail validation. Missing
source records are retained as transport dependencies and revalidated on arrival;
local commands require the source before preparing a receipt. A self/forward
same-writer reference fails wire admission even if its source has not arrived.

See [implementation evidence](../evidence/production-text/historical-recompletion/README.md).

## Earlier proposal, superseded by Lee's approval

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
