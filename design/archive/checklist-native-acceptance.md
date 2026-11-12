# Checklist candidate native acceptance

Use `feature/one-level-checklists`, based on shared-history candidate c182385.
The candidate receipt must name an exact source commit, CI run/artifact IDs,
whole-payload hashes and native library hashes. The package still displays
2026.10.2-rc.3; its display version does not identify this unreleased candidate.
Build/test success and earlier c182385 platform results do not establish checklist
native acceptance. No publication or stable feature promotion is implied.

Use only dedicated synthetic profiles. Android must use the real SAF picker and
an isolated test installation. Windows must use an isolated account/profile and
the exact portable manifest or installer from the trusted CI run. Keep existing
resource caps; a different cap needs Lee's approval through the coordinator.

## Starting fixture

Copy every file in [qa-fixture/shared](../evidence/checklists/ui/qa-fixture/shared/)
unchanged to a new synthetic shared folder. Verify each SHA256 from
[manifest.json](../evidence/checklists/ui/qa-fixture/manifest.json). Give every peer
a fresh private profile; never copy seed-private writer identities or caches.
The fixture was produced and history-verified by production commands in
`tool/checklist_qa_fixture.dart`, without hand-authoring canonical bytes.

Select **Alex Example** on Android. Windows/Linux settings can be initialized as
`{"folder":"ABSOLUTE_SYNTHETIC_FOLDER","user":"USER_FROM_MANIFEST","appearance":"dark"}`
in the new profile. The open **Pack for a walk** task repeats every week when
done and starts with **Water bottle** and **Map**, with a note on Map.

## Required affected flows

1. Open the task. Add an item with a title and multiline optional notes; Save.
   Reopen/edit/Save, reopen/private-edit/Cancel/keep-editing, then Discard. Repeat
   this cycle. Title/notes must remain item-scoped and separately durable from
   the parent task. Hold a private parent title while saving an item; discard the
   parent and verify the saved item remains.
2. Check/uncheck items, move up/down through the item menu, delete with Cancel
   and confirmed Delete, and use session Undo. Edge moves are unavailable;
   controls have item-specific accessibility labels. Restart the same profile
   and reopen the folder cold after cache loss. Existing canonical records stay
   byte-exact; intentional commands may append new records. Never delete logs
   to simulate cache loss.
3. Complete using the task checkbox and desktop Space. Unfinished items warn;
   Cancel or dismiss writes no record. Complete anyway produces one successor
   containing fresh unchecked copies in the observed order. Edit that child,
   then change the old parent's items; later parent changes do not flow forward.
4. Hold the warning on peer A while peer B adds/edits/checks/moves an item. A's
   Complete anyway must renew confirmation for the changed snapshot before a
   receipt is prepared. Preserve existing successor edits when peer completions
   arrive, following the recurrence/Undo rules in ADR0011.
5. Hold an item draft while a peer edits that item. Save preserves both native
   contributions; scoped Undo retracts only local work. Navigate/change user or
   folder with private item edits: Save/Discard/Cancel must resolve the draft
   before native ownership or the containing store is released.
6. Test delayed/lost append acknowledgement and exact Retry Save. Fields and
   closing stay frozen for a prepared receipt even if background reconciliation
   later confirms it. Retry must finish the original bytes/identity once.
   Force-stop/relaunch around Save must recover the durable outbox without
   inventing a second item or text edit. Controlled Linux provider faults are
   automated in `checklist_lifecycle_test.dart`; distinguish those from actual
   Android SAF/Windows transport evidence.
7. Inspect both themes, desktop/narrow layout, enlarged text and long item
   title/notes. On Android use the actual IME, composition, keyboard appearance,
   multiline caret/scroll, system Back, SAF persisted permission and restart.
   On Windows verify keyboard traversal, Space, Escape, Undo and Unicode paths.
8. Record the actual OS/device/API/provider, text scale/theme, exact candidate
   hashes, observed results and remaining gaps. Provide desktop and Android
   videos with visible pointer/Show taps and inspect representative frames.
   Linux GTK at phone width is Linux evidence; it does not substitute for Android
   or Windows GUI acceptance, actual IME or assistive-technology checks.

The existing shared-history performance/native gates still apply. This feature
does not claim linear historical replay, bounded total heap/RSS or resolved
long-history mobile startup. Refer to the separately measured CPU debt and the
coordinator's current platform/resource results before candidate publication.
