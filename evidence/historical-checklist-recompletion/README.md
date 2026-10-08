# Historical checklist recompletion: replacement candidate

Status: reproduced and fixed locally; independent correctness, architecture and
security source review passed. Exact replacement Android artifact acceptance is
pending. The original frozen candidate remains failed and unchanged.

## Native finding and reproduction

Parent reported the defect on Android app source
`17ae5e5619bbd890a9778ffe39b1c94156086bb3`, frozen evidence head
`a960c882c06c018a1e721e7459f08dbe4d17bed3`. A weekly when-done parent was due
October 1, completed October 8, with successor due October 15. After the successor
title and copied item were edited, an intact offline completion arrived; neither
child edit changed. Editing the completed parent's item, reopening both known
completions and recompleting then leaked `ParentLater` into the child item. Undo
and cache rebuild retained that leaked contribution; no grandchild appeared.

The original packet was Library `libfile_e6105dbf742c8191bacdab08d8e64782`,
`tandemlog-successor-text-leak-17ae5e5.zip`, parent-reported 352997 bytes and SHA256
`0e8728088ed099bdd45b4b814ff41ec637ee282c31166cb19d6707cb2c8729f9`.
Supported resolved-reference preparation succeeded; consumer download returned
403. These packet bytes and their hash were **not** verified here. Parent explicitly
authorized reproduction through production commands using the supplied ordered
actions. It uses the same parent/child/item IDs, dates and five unfinished items,
with fresh writers, clocks and the other four item IDs. It does not claim original
canonical bytes or original A11–A18 writer sequence identity. Fresh native actors
can order the two unwanted suffixes differently; both violate child preservation.

Tests-first source checkpoints `90b4def6ad20d867546cc523edade34bc4f16700`
and `f00ed0040272b9f81a678b1d504d1beb5e8330f9` preserve the original production
implementation and respectively three/four failing native-command phases. Frozen
[red manifests](red/) describe their status at those checkpoints; their historical
review-pending wording does not describe the completed reviews below.

## Fix and preservation boundary

The old historical-source selector and source validator excluded native successor
initializers. Recompletion therefore appended another inheritance proof. Native
replay correctly kept that immutable proof through Undo, preserving the leak.

The narrow fix allows the existing parent-only `task.completedKeepingSuccessor`
record to bind an earlier native initializer when durable successor task, checklist
or ordering-anchor activity exists. It adds no child snapshot or inheritance.
Undo/deleted child work remains protective. An untouched native successor retains
ordinary forward/concurrent inheritance. Released scalar eligibility, hashes,
clocks, UUIDs, wire validation, immutable contribution union, Undo, native code and
dependencies are unchanged. The native marker extension belongs to the unreleased
prototype. [Accepted policy](../../design/historical-recurring-text-policy.md).

This prevents new incorrect proofs; it does not rewrite or remove the leaked
proof already appended to the failed synthetic history. Native retesting must
start with the parent's supplied **checkpoint through A16**, before A17/A18, or
repeat the ordered workflow with fresh synthetic data. Do not use live synced data.

## Local checks and actual pixels

- Native command regression: 4/0, including cold rebuild before and after Undo,
  exact child task row and all five item snapshots.
- Boundary/delivery checks: 8/0. Exact source/hash binding and parent completion;
  native edited child versus untouched child; scalar/native marker and source in
  both arrival orders, cross-writer Undo, duplicate refresh and wrong-source-hash
  transactional rollback.
- Affected historical/recurrence/checklist/Undo suites: 106/0.
- Full Flutter suite: 606/0; final analysis: no issues.
- Actual GTK dark desktop 1200×850: new app regression passes 1/0 with completion
  warning, child task/item saves, intact offline completion, old-item save,
  reopen/recomplete and global Undo. Frozen source fails at the child snapshot.

The native library in both actual GTK bundles and command tests has SHA256
`a9b0c51f4f6cf347e321d9f47a0dec6161be161adfca44eb5be60c7db7a37e56`.
Root inspected [Before](native/before-native-recompletion.png),
[After](native/after-native-recompletion.png) and
[After Undo](native/after-native-undo.png) actual pixels. The child title remains
`Pack for a walk ChildA`; After/Undo show exactly `Native item Saved ChildItemA`
and five unchecked items. These are Linux evidence, not Android acceptance.

One expanded screenshot run attempted an item control before asynchronous editor
readiness; its [failed harness log](harness/editor-readiness-failure.txt) is retained.
Explicit waits now observe the actual editor/item controls. An initial startup
frame was excluded from accepted media. No production UI changes were needed.

Independent source/tests review: correctness_review accepted the expanded gates;
security_review accepted native source eligibility with unchanged strict binding;
architecture_review accepted preservation and required the corrected schema status
and this evidence link. No reviewer claims to have rerun the local checks.

## Remaining gates

Run full CI against the exact replacement source and preserve its artifact identity.
Parent must verify installed APK bytes/signing and repeat the actual Android
checkpoint-through-A16 trigger, Undo and disposable cache rebuild, plus affected
native recurrence/checklist flows. The failed original APK, tag component and Kotlin
component remain separate. No release or overall native acceptance is claimed.
