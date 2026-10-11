# Food session Undo

RC2/build64 milestone: exact hosted/artifact and parent Android native acceptance
complete; publication authorized, final readiness/public verification pending.
[Current accepted evidence](../../evidence/food-2026.10.4-rc.2/candidate/build64/README.md).

Historical preparation status (superseded by the build64 milestone above): Lee approved the full session stack and additive Food v2 operation on
2026-10-11. Core implementation and independent review are complete; host/native
and exact candidate acceptance remain in progress for2026.10.4-rc.2/build62.

## Context and decision

Removal-only Undo loses earlier actions as soon as another Food command succeeds.
Food now retains at most50 confirmed session actions, matching Tasks. Add,
details/date/brand/retention edits, contents changes, Remove and Restore each
retain their exact original receipts. A bulk command occupies one action.
Successive Undo traverses the stack; there is no Redo. Search, Filter, section
navigation and app-wide user changes preserve it. A successful workspace change
or restart clears the local stack. Food and Task actions have separate histories
and callbacks; a Task completion notice cannot remain actionable in Food.

Undo withdraws original contributions rather than appending old snapshots.
Independent and newer peer contributions survive, including changes to the same
field. The action label identifies the kind of change and physical target count.
An unfinished save or inverse blocks another action. A failed or partial original
batch is recorded only after every exact receipt is admitted; a failed or partial
inverse leaves its action on the stack until its entire protected batch is
confirmed. Retry uses the original prepared bytes and reserved identities.

## Durable contract and replay

Food's existing v1 operations, writer derivation, creation bases, genesis hash,
clocks, IDs, canonical serialization and hash preimages remain unchanged. The
shared workspace manifest and released task v3 records do not change. Only
`undo` uses envelope version2 and hash domain`tandemlog:food-record:v2\n`.

The closed Undo operation contains `action`, physical `targets` and one
`retracts` reference to a strictly earlier operation from the same Food writer.
It carries each target's observed creation basis in the existing envelope.
The referenced operation must be admitted, reversible and have the same exact
targets. Commands validate the original ID/hash receipt against admitted history;
replay validates references and creation bases before filtering contributions.
Undo cannot target Undo. Missing dependencies wait; known invalid dependencies
fail even when a related operation has already been retracted.

Retracting a details edit reveals the remaining field contributions. Retracting
a contents edit also withdraws its own observed-edit domination edges; surviving
later resolutions retain their edges. Retracting Remove withdraws only its
deletion token. Retracting Restore withdraws only its observed-token restoration
effect. Other removals/restorations remain effective.

Undo Add suppresses untouched physical identities from both active and Deleted
views without removing their canonical births or indexes. A surviving direct
edit, Remove or Restore protects and resurfaces the original seed, including an
independent contribution arriving after Undo. It does not invent replacement IDs
or pretend Add was a deletion.

## Compatibility and recovery

Frozen source files from the actual released build60 reader verify literal v1
roundtrip, explicit v2 rejection and module isolation. An older peer encountering
canonical v2 stops Food without advancing its Food head; Tasks remain usable.
A downgrade of the same private profile while it contains unresolved protected
v2 receipts can stop shared workspace admission because that older reader cannot
validate the recovery authority. Preserve the exact profile and canonical files,
then reopen with the current compatible reader to recover the same bytes. Do not
discard receipts, choose a new writer or rewrite history to bypass admission.

## Alternatives and consequences

Restoring whole snapshots would overwrite independent work. Converting Undo Add
to Remove would manufacture a deletion and expose untouched additions in Deleted.
Clearing history on ordinary navigation would make the stack unreliable. All
three alternatives are rejected. The additive envelope intentionally makes
older Food readers stop explicitly rather than reinterpret new semantics.

## Revisit trigger

Revisit before introducing Redo, persistent action history, cross-module actions
or another Food wire version. Preserve released meanings and frozen fixtures.
