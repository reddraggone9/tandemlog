# Decision 0005 — session Undo and toolbar fit

Status: accepted RC5 scope, 2026-10-01; Linux acceptance passed, exact Android acceptance pending. Supersedes RC4's transient Undo and permanent-deletion description. [Product behavior](../product-behavior.md), [schema](../schema.md).

Lee wants task changes recoverable after a popup disappears. The toolbar keeps Undo available on desktop and phone, disabled when the session has no saved action. Repeated Undo steps through at most 50 actions; there is no redo. Restart and workspace changes clear this local history, not the canonical task history. Edits, single/bulk relative moves, completion/reopening and deletion participate. Capture creation and identity changes do not. Bulk retries belong to their original action and retain each independently confirmed operation. Save/move actions are quiet. Completion/deletion briefly offer the same Undo action through a snackbar; dismissal/expiry has no effect on availability. Ctrl/Cmd+Z acts on tasks outside editable text, leaving native text Undo in inputs. Resolve the frozen dirty editor through Save/Discard/Cancel first.

## Conflict and durability behavior

Undo appends a named retraction of each original operation, instead of overwriting a task with its old snapshot. Replay omits that operation's contribution and retains independent later writes. A newer title, assignee or whole atomic schedule register survives. Observed tag removals/additions retract only their operation's tokens; an independent same-name addition survives. Another device's completion or deletion can keep the task completed/deleted. Relative moves replay without the named move, retaining subsequent moves and hidden ranks. Undoing recurring completion/reopening always preserves the independent successor and its work. A newer-write notice is conservative, not a claim to recover subjective intent perfectly.

Durable append is still the commit point. Only exact canonical `(ID, raw bytes)` matches admit prepared operations into session history, including writes whose acknowledgement failed. An ID can be reused after a failed pre-append attempt, so ID-only confirmation/deduplication is unsafe. Partial Undo acknowledges only the confirmed prefix, retains the remaining operations and offers Retry. No original event, timestamp or source folder is rewritten. Cache version 8 rebuilds known older disposable materializations with the existing backup/integrity guards. The new closed-schema v2 type requires all peers to update before using Undo; old readers fail explicitly.

## Toolbar

Remove “Tandemlog” from the everyday chrome, retaining the checkmark as the task position; no mode switch is implemented. Show the entire active user name if its measured text, current text scale and neighboring controls fit. Otherwise use an initial circle, with the full name in accessible menu labeling and a minimum 48px target. This replaces arbitrary width caps and truncation; the editor's existing 900px wide-pane breakpoint remains. Identity and assignee filtering stay distinct.

Current events identify a writer device and task assignee, not the acting user for each change. Lee chose device-only event attribution: any advisory device-to-person association/display may come later. Historic people cannot safely be inferred from writer/assignee. Acting-user fields, audit UI, rollback of other people's history, redo and cross-restart Undo are outside this candidate. Device-signed logs remain a future idea requiring a separate key/integrity design.

Rejected: popup-only recovery, inverse snapshot writes that overwrite newer synced work, persistent arbitrary name truncation and a general history framework. Revisit the 50-action/session boundary or conflict wording if hands-on use shows concrete friction.

## Accepted follow-up: completion, selection and batches

Selection count/Clear Selection/Edit remain outside the task scrolling viewport whenever the side pane is unavailable, including narrow desktop windows. The strip participates in layout above the list, respects the existing safe area and wraps at larger text scales. It does not cover final rows or extend the drag viewport into controls. Wide editor headings keep their existing design. This fixes unreachable commands without adding duplicated or permanent chrome.

Lee reported identical scheduled successors on early completion-relative completion, dirty side editors closing/reopening during drag, and a lost Shift anchor after reorder. Compare actual successor dates and explain unavailable completion; retain editor keys/controllers during moves, and preserve anchors by visible task ID. Reopening/Undo and recurrence computation remain unchanged. Move Undo also retains the editor because it does not touch its content; content-changing Undo still resolves the draft first.

Small local batches should feel immediate. Measurements found repeated read/hash/cache/order work dominating flush time, plus progressive capture-field clearing. Shared validated JSONL appends remove repeated scans and acknowledge one coherent input update without weakening flushes, inventing whole-batch crash atomicity or changing the protocol. Incoming deferred references and exact receipt recovery remain admission gates. AOT measurements and fault tests substantiate this choice; Android provider/visual acceptance stays independent. Revisit chunk sizing if real selections substantially exceed the tested 100-task envelope.

The tag dropdown prefers usable space below and uses actual content/keyboard bounds before flipping; footer proximity alone was an incorrect placement heuristic. Its overlay does not resize the dialog and is dismissed before accessing covered footer actions.

## Explicit Add and accessible tag results

Build 27 native Gboard QA found that the composition guard also rejected a deliberate Add-button tap. Keep the hardware-Enter guard for candidate selection, but let Add finish editing through Flutter's standard `EditableTextState.performAction(done)` path. It clears composition, finalizes the input connection and invokes the existing capture callback; the synchronous busy guard prevents duplicate writes. This preserves one capture/receipt/retry path instead of inventing a second save path or modifying the draft before a durable acknowledgement. Simulated input tests complement exact Android Gboard acceptance.

Native Android also showed painted tag-result labels absent from the accessibility hierarchy. The portal attached results beneath the dialog's clipped query scroll viewport. Use an explicitly owned overlay entry instead, retaining theme/text scale, placement, query focus and dismissal, with removal on picker disposal. Result labels, tap actions and selected state stay outside the query's clipping ancestors. Widget semantics and native layout regressions cover this boundary; Android hierarchy/action verification remains a separate gate.
