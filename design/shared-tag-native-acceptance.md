# Shared tag input native acceptance

**Blocked by the parent-reported native historical-recompletion defect.**
Shared tags inherit the affected core from `17ae5e5`. Await the exact native
sequence, failing regression, narrow correction and newly identified candidate;
this handoff describes supporting tag checks, not overall release acceptance.

Use the isolated `feature/shared-tag-input` candidate. Production is
`041c06488cb2d937d38519dec8e3e3ebd69abbf3`; final interaction-test source is
`ec2309dbbdde09d5fce0a07610bc253258dd508b`. Full CI
[37796892998](https://github.com/reddraggone9/tandemlog/actions/runs/37796892998)
passed all platforms. Its [receipt](../evidence/shared-tags/green/ci-receipt.json)
binds the source and reported artifact IDs/digests. Before device testing, bind
downloaded archive/APK hashes, signer and native payload. Consumer byte verification
and runtime acceptance remain pending, alongside the blocking core fix. The displayed
`2026.10.2-rc.3+45` version alone does not identify this unreleased candidate.
This branch does not include the separate Kotlin 2.4.20 remediation.

The frozen checklist candidate `a960c882` and APK `ac31725f…` retain their
separate acceptance run. Do not replace that installation or its synthetic
profile to test tags. Use a separately isolated installation/profile and a new
synthetic shared folder. Keep the parent's approved resource limits. Final
combined, owner-signed release acceptance remains a later gate.

## Known starting inputs

Copy only [qa-fixture/shared](../evidence/shared-tags/native/qa-fixture/shared/)
into the new shared folder, preserving its two files. Verify each SHA256 from
[manifest.json](../evidence/shared-tags/native/qa-fixture/manifest.json). The
[generation receipt](../evidence/shared-tags/native/qa-fixture-receipt.json)
records eight v3 records emitted by production commands and verified through
`TaskStore.verifyHistory`. Each peer gets a fresh private profile; never copy a
seed writer identity or cache. Android must grant this folder using actual
DocumentsUI/SAF and select **Alex Example**.

The two open tasks are **Plan weekend**, tagged with exact values `Home Office`
and `#Legacy`, and **Review supplies**, tagged `Planning`. The completed
**Finished reference** task supplies `ArchivedOnly`. These deliberately cover
a multiword original value, an original leading marker and completed inventory.
Never hand-edit the canonical files to manufacture a state or repair a test.

## Focused affected flows

1. Open Plan weekend. Its existing values appear as separate selected chips.
   Type `Archived` and select `ArchivedOnly`: the completed task's tag is
   suggested. Removing a chip preserves the current query/caret; Escape or
   collapse dismisses suggestions without clearing the query. Select Planning
   using desktop arrows/Enter where available. Keep the opaque original values
   unchanged, including spaces and the leading marker.
2. Type `#Fresh` without submitting the entry, dismiss suggestions if they cover
   Save, then Save. Reopen and inspect canonical tag changes: Fresh is added
   once and existing selected tags remain. Cancel a different pending query;
   keep editing must retain it, while Discard leaves canonical bytes unchanged.
   Reopen/repeat and force-stop/relaunch after a successful save.
3. Select both open tasks and open bulk editing (the compact Edit selected
   action on phones). Stage Add Shared; in Remove, type `Home` and select exact
   Home Office. Save removes that value from Plan weekend and adds Shared to
   both tasks. An unmatched removal query must block the entire Save, remain
   editable and retain the Add draft. Verify the exact prior tags after refusal.
4. With a bulk draft open, change a selected task from a fresh synthetic peer.
   Attempt Save and repeat it after the changed warning. The warning and draft
   remain; no draft tags leak into history. Cancel/Discard, reopen and perform
   a successful bulk edit. Record actual SAF/peer transport separately from the
   automated Linux synthetic-provider cases.
5. Filter by Fresh and Shared together: matching either is sufficient. Selected
   chips and full-width Find tags query use the same interaction as the editor.
   Remove one filter chip, clear the query and reset filters. Unknown queries
   cannot create tags. All filter-only operations leave canonical bytes unchanged.
6. Inspect dark/light themes, normal/enlarged text, narrow/landscape layout,
   long names, touch targets and popup/keyboard insets. On Android exercise the
   actual IME, active composition, system Back and keyboard appearance/dismissal.
   Saving/closing cannot commit unfinished composition. Test accessibility
   labels, selected state, chip removal and separate bulk Apply controls with
   native assistive technology; record unavailable checks as pending.
7. Reopen through the persisted SAF grant, observe a peer update, and verify
   subsequent local Save and cold reopening. Record device/API/provider, theme,
   scale, exact installed bytes/signer, expected/observed results and gaps.
   Capture an actual Android video with Show taps and inspect the indicators.

Actual GTK tag flows and the separately qualified 22 hosted Windows debug flows
provide supporting evidence. They do not establish Android IME/provider/visual
acceptance or acceptance of a later combined signed artifact. See
[runtime QA](runtime-qa.md) and the [tag receipts](../evidence/shared-tags/README.md).
