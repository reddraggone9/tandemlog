# Historical checklist replacement: exact native retest

Status: local source/native GTK checks and independent reviews passed. Android
build and full CI passed; replacement Android runtime acceptance remains pending.
This is an internal test-only APK, not a public preview release.

| Binding | Exact value |
| --- | --- |
| Application/test source | `d73662ab8479aa8076ee04a5ed5badd1542e585d` |
| Branch | `fix/historical-checklist-recompletion` |
| CI / Android job | `37804634954` / `113405587461` |
| Android artifact | `11561899292`, name `android` |
| API-reported ZIP bytes | `80369922` |
| API-reported ZIP SHA256 | `1fbe0347a14e9edd6c7a204732fbd449d6c22fe28c2ba5737f2e324528299878` |
| Hosted APK SHA256 | `5e35400713e614c74730713c060e65bb3edea2d409df1cb57e7f6de94bf87a1c` |
| Hosted debug signer SHA256 | `dca591b067fbbfb1b1b88afbf0dc696e8f23b8bba5951a966309ed3c45d2e6b7` |

[Full CI37804634954](https://github.com/reddraggone9/tandemlog/actions/runs/37804634954)
passed all three jobs. Linux606unit/67actual-native apps and Windows604unit with
two expected Linux-only skips passed; each desktop also passed4Cargo,107native
worker and37tool checks. Release packaging/staticnative/installation smoke gates
passed. The [qualified receipt](../evidence/historical-checklist-recompletion/green/ci-receipt.json)
preserves exact source/job/artifact and decoded-log binding.

The GitHub artifact transfer returned403 here. ZIP/APK bytes, APK size and signer
were not locally verified. The APK digest and signer above come from decoded
completed Android job output; the ZIP digest/size come from GitHub artifact API
metadata. Materialize and hash actual bytes, verify the APK signer and installed
artifact, and record package/version/code before runtime testing. The app's
internal version/configuration is unchanged from frozen QA `2026.10.2-rc.3+45`.
The new hosted debug signer differs from the frozen APK's signer, so do not assume
an in-place update. Preserve the failed synthetic history and recordings; use a
dedicated synthetic installation/profile. All participating preview test peers
must run a build containing the fix before consuming its native retained marker.

The same reviewed application/test/native inputs also pass the focused actual
[Windows debug regression](https://github.com/reddraggone9/tandemlog/actions/runs/37805503087)
at runner source `bcbcece5dc34d44dbb7453fa54c0882a3dbacd10`:1/0, no skips,
first-frame300ms/readiness1021ms. Its independently reviewed
[receipt](https://github.com/reddraggone9/tandemlog/blob/9d308a6235685038583415573d8a0bc7d4937690/evidence/historical-checklist-recompletion/windows-native-receipt.json)
does not claim consumer raw-archive/binary rehash or signed-release acceptance.

## Minimal parent-supplied trigger

Use the exported canonical **checkpoint through A16**, before the leaked A17
proof, or repeat the complete ordered synthetic workflow. The fix prevents new
incorrect inheritance; it does not remove an already appended proof. Never
truncate or rewrite live canonical data to create a retest fixture.

Parent `84b20089-b9e9-4a2d-8d91-c205631e7c09`, successor
`a119a352-62a0-5475-ad33-0f4cd75d636a`, old item
`8dede838-27a9-4ead-8088-5f532a9956f0`, copied item
`57fed6a9-c36b-58e1-b122-bc7a6b356331`. Parent due October1, completions
October8, weekly when done; child due October15. Five items remain unchecked.
Child task title must stay `Pack for a walk ChildA`; copied item must stay
`Native item Saved ChildItemA`. Old item contains `Native item Saved ParentLater`.

1. In Open, complete the reopened old parent. Confirm the unfinished-items warning
   and Complete anyway; require completed old parent, one existing successor,
   unchanged child task and all five item snapshots, no grandchild and the usual
   Next occurrence kept feedback.
2. Global Undo must reopen only the old parent and preserve that child exactly.
3. Rebuild only the disposable synthetic cache through the established safe
   procedure; retain canonical history and writer identity. Reopen and require
   the same child snapshots and no grandchild. Also test cold replay immediately
   after recompletion, before Undo, with a separate disposable profile/cache.
4. Verify intact peer delivery/convergence, ordinary concurrent offline recurrence,
   later old-occurrence edits, successor own text/notes and item edits/Undo,
   completion consent and existing checklist lifecycle. Record genuine event
   IDs/hashes and source binding from actual new native operations; do not reuse
   the generated fallback's fresh writer sequence IDs as original A17/A18.
5. Preserve actual installed hash/signer, device/API/ABI/AVD, approved6GiB/2CPU/
   one-AVD resource setup, startup/native FFI, SAF reopen/refresh, lifecycle and
   actual Android IME observations. Keep frozen failed APK evidence unchanged.

The original Library packet remains unmaterialized in this consumer; parent owns
its actual checkpoint. [Reproduction and preservation evidence](../evidence/historical-checklist-recompletion/README.md)
qualifies the authorized generated-command fallback. No live synced user data,
Kotlin update or shared-tag implementation is part of this replacement APK.
