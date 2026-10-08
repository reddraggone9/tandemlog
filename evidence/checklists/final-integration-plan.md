# Final integration plan — 2026-10-08

## Current coordination checkpoint, 17:16 UTC

Parent authorized separate combined preparation while its isolated A16 retest
continues, superseding this older plan's wait-before-preparation sequence. The
original failed source and isolated replacement remain frozen. The current
[reviewed composition/QA contract](https://github.com/reddraggone9/tandemlog/blob/e205e650b5614935a73cf5acb96ca9b36fda8e4e/design/final-preview-acceptance.md)
is authoritative for preparation and remaining acceptance gates.

`preview/shared-history-checklists-final` is pushed clean at
`e205e650b5614935a73cf5acb96ca9b36fda8e4e`, version `2026.10.2-rc.4+46`.
It cleanly merges reviewed shared-B `e816f433`, historical fix/evidence
`19377652` (compiled fix `d73662a`) and narrow Kotlin `1b8f0cc5`. Independent
source, documentation and local receipt/pixel reviews accepted. Local gates pass
628 Flutter tests, clean format/analysis, historical GTK 1 and separate tag GTK 3;
the earlier multi-entrypoint debugger attachment failure is retained. Exact
[composed CI 37810677866](https://github.com/reddraggone9/tandemlog/actions/runs/37810677866)
completed successfully on Linux, Windows and Android against exact e205e65.
Linux 628 unit/70 actual native, Windows 626 unit/two expected Linux-only skips,
and each desktop 4 Cargo/107 worker/37 tool checks pass. Independent receipt/source/
artifact/log review accepted; artifact bytes remain consumer-unverified here.
Supporting actual [Windows 3+1](https://github.com/reddraggone9/tandemlog/actions/runs/37813474065)
also passed on runner a249af5 with all application inputs exact e205.

[Exact debug artifacts and signing/QA contract](https://github.com/reddraggone9/tandemlog/blob/43472b13ecdbb5aa634e359d44a76a4411657df8/design/final-preview-debug-native-qa.md)
is pushed on `docs/final-preview-ci-qa`.
[Concise notes and matched dark media](https://github.com/reddraggone9/tandemlog/blob/f6ef0e965f826fa56e44cb9268e09816d278a19f/design/prerelease-notes.md)
on `docs/rc4-release-notes` passed independent content/provenance/pixel/immutable-link
review. Clean main-ready integration `preview/rc4-main-ready` is separately frozen
at `56213cc5d781bc2e7ee96b6ba7d4f37f232d3b1b`: only docs/evidence/scoped evidence
attributes differ from e205; application/test/native/platform/locks/version and
workflow inputs remain exact. Independent final planned-main range review accepted
published 5ac35da→56213cc, with the same accepted notes/media bytes. This new source
has not run a new full matrix; its actual signed-candidate workflow will do so
after parent gates. Main remains 0a16a88; no main push/signing/publication.

Isolated fix CI 37804634954 passed all three platforms, and hosted Windows
historical workflow 37805503087 passed 1/0. Security/correctness accepted its
source-bound decoded-log/API artifact evidence; consumer byte verification and
parent native A16 retest remain pending. No main merge, signing or publication;
fresh quota, exact combined signed/native/manual/UX acceptance and independent
release-note/media range confirmation for any later executable change remain required.
Current planned range editorial gate is complete. Stable feature approval absent.
The older sequence below is retained as historical coordination context.

Status: **BLOCKED by a parent-reported reproducible native historical-recompletion
defect in exact source17ae5e5.** Recompletion of an old checklist parent leaks
later text into an independently edited successor; Undo and cache rebuild retain
the leak. This violates the approved policy. Release/native acceptance is not
complete. Shared tags inherit the same recurrence/checklist core byte-for-byte.
The exact ordered native sequence was received. The packet's supported Library
consumer transfer returned403, so parent-authorized production-command fallback
reproduced the leak before source changes. Narrow reviewed fix
`d73662ab8479aa8076ee04a5ed5badd1542e585d` on
`fix/historical-checklist-recompletion`, based on frozen a960c88, passes606Flutter,
8boundary/delivery and1actualGTK checks; the same GTK regression fails on frozen
source. [Replacement evidence](https://github.com/reddraggone9/tandemlog/blob/d73662ab8479aa8076ee04a5ed5badd1542e585d/evidence/historical-checklist-recompletion/README.md)
preserves qualification and actual Before/After/Undo pixels. Exact replacement
[CI37804634954](https://github.com/reddraggone9/tandemlog/actions/runs/37804634954)
completed successfully on all three platforms. Preserve the
failed artifact/evidence; any fix requires a new exact candidate and affected
native retest starting from checkpoint throughA16, before the leaked A17 proof.
The fix does not rewrite an already leaked history. Other passing local flows
and twelve validated recordings remain supporting evidence, not overall acceptance.

Preparation only. The current combined candidate stays frozen throughout
local Android acceptance. No merge, build or publication is performed by this
plan. Shared tag input was subsequently approved and implemented on a separate
branch; it does not change this frozen artifact. Lee approved a persistent 6 GiB emulator cap with
2 CPU, no host swap and one AVD; the local task owns headroom checks and the
narrow configuration change.

## Frozen acceptance target

| Binding | Exact value |
| --- | --- |
| Candidate branch | `preview/checklists-queued-fixes` |
| Frozen head | `a960c882c06c018a1e721e7459f08dbe4d17bed3` |
| Compiled application/test source | `17ae5e5619bbd890a9778ffe39b1c94156086bb3` |
| Successful full CI | [37747198468](https://github.com/reddraggone9/tandemlog/actions/runs/37747198468) |
| Android artifact ID | `11536038281` (`android`) |
| Android archive bytes | `80369328` |
| Android archive SHA256 | `be3e8c5faeb72dd5a290f7519ed398d6f7cccaa1003ace84bb5b561cd655cf4f` |
| Actual APK bytes / SHA256 | `164893808` / `ac31725fd24dae37798091b00a192d5f0d5e3ea1c991d503ddc8aa2d9b87be91` |
| Debug signer SHA256 | `ce6957a5935f04f30e1d6273e9aad82d87f58000333423c4a6bd6555e8c65677` |
| Package / version / code | `com.reddraggone9.tandemlog` / `2026.10.2-rc.3` / `45` |
| Windows artifact ID / archive SHA256 | `11536113401` / `e4aad43623e899d944c93d365d501815e5697eef7693699b9c04792d3c32926c` |
| Linux artifact ID / archive SHA256 | `11537062777` / `08ed6bbbb6d767453d448c9cc8882855de550817cec9ef77203a8359e1eb19c9` |

Fresh remote and local reads confirm the frozen head. Its delta from compiled
source 17ae5e5 is evidence-only; application, tests, native code, dependency and
platform/build inputs are unchanged. The archive digest above identifies the
ZIP, not its APK member. Both archive and APK bytes were materialized and verified;
the APK matches its hosted checksum/signature report and passes static packaged
native and signature checks. The local task must match its own installed APK to
that exact hash before recording runtime acceptance. See the
[final-source receipt](queued-fixes-final-ci-receipt.json) and
[affected-flow handoff](queued-fixes-native-acceptance.md). The frozen candidate's
own README contains historical pending statuses; the separately updated receipts
record terminal CI and hosted Windows results without changing the candidate.

## Integration sequence after the blocking fix and native acceptance

1. Preserve the exact 17ae5e5 APK's failure and the minimal native sequence.
   Freeze the corresponding regression, fix narrowly, independently review,
   rebuild a separately identified candidate and rerun the affected acceptance.
   Retain its checksum,
   signer, device/API/AVD, resource settings, startup/runtime ABI, workflow and
   SAF/lifecycle/IME observations. Keep every profile and canonical folder
   synthetic. Record failures before changing source; any necessary fix belongs
   on a new isolated branch and invalidates acceptance for the changed artifact.
2. Keep the original candidate and its verified failed artifact/evidence immutable. Prepare a
   separate integration branch after acceptance. Reviewed Kotlin head
   `1b8f0cc5c6eeb302519231d7269ee37a529e36d0` already descends directly from
   a960c88; its merge base with that candidate is exactly a960c88. Preserve this
   reviewed ancestry and evidence. The separately approved shared-tag branch
   also descends from a960c88; include its reviewed production implementation
   only after its remaining gates pass. Do not stack the old save-delta,
   cache-only or autocomplete trial branches. Compare the then-current main before
   proposing a merge, and review any intervening source or resolved conflicts.
3. Include the narrow Kotlin update: main Android KGP 2.4.0 to 2.4.20, retaining
   AGP 9.1.0, Gradle 9.3.1, Flutter/pub/Cargo/native inputs and durable v3 meanings.
   Its [reviewed report](https://github.com/reddraggone9/tandemlog/blob/1b8f0cc5c6eeb302519231d7269ee37a529e36d0/design/kotlin-2.4.20-remediation.md)
   binds full CI 37753131078 to ac20d4e and cold/warm full CI 37755702541 to
   45eb9e8. Both passed every platform; independent actual graph/artifact review
   has no must-fix. Eleven observed 2.4.20 binaries fit the 23-entry reviewed
   inventory; 259 selected tasks span 64 implementation classes, all observed
   classes Android/JVM. Flutter's separate
   included-build Kotlin remains 2.2.21. The evaluation observer is branch-scoped;
   moving source to a new branch does not automatically rerun its cold/warm step.
4. Resolve Android runtime acceptance for the integrated Kotlin and tag changes.
   Existing verified
   45eb9e8 debug APK SHA256
   `d8a1dd334bec9ce21139c4ddd25b114e723f463ae3ca7904e58c8d15d723182c`
   supplies supporting evidence for the isolated Kotlin change. Shared tags
   change application inputs, so that older APK cannot establish acceptance of
   the combined integration. Verify each artifact's separate signer and fixture
   isolation first; do not assume an in-place update from the 17ae5e5 debug APK.
   Exercise startup/native FFI, SAF grant/reopen/refresh, Kotlin-backed picker
   callbacks, tag suggestion/selection/creation/removal/filtering, actual IME,
   accessibility and the affected task/text/checklist flows. Passing the original
   Kotlin-2.4.0 APK does not accept this changed Kotlin-2.4.20 artifact.
5. Once integration scope is fixed, obtain the parent's fresh quota read before
   a publication or major new start. Choose a valid new preview version and
   monotonic build using fresh published-tag and successful-candidate floors;
   the internal `2026.10.2-rc.3+45` QA APK is not a new public release. Prepare
   the exact merge/version change for independent code, compatibility/security
   and UX review. Use existing all-platform signed-candidate gates for the actual
   changed source; do not repeat completed suites merely to refresh status.
6. Build the owner-signed candidate through the established main-only workflow
   after integration is authorized and reviewed. Verify source/version/signers,
   native libraries/notices and every artifact checksum. Complete native
   acceptance on that exact non-debuggable Android APK and the exact installed
   Windows release payload. Earlier debug tests and source equality supply
   supporting evidence; they do not substitute for final-artifact acceptance.
7. Independently review concise release notes and real dark-theme Before/After
   media against the actual release commit range. Publish the authorized preview
   only after all gates pass, consuming those accepted artifacts without a
   rebuild. Stable feature promotion still requires Lee's explicit acceptance.

## Approved shared-tag work and remaining gates

Lee explicitly approved shared B-style tag input at 2026-10-08 13:01:08 UTC;
the parent's supported quota read was 77% at 13:01:14 UTC. This supersedes the
earlier unchosen A/B stage. Production is `041c06488cb2d937d38519dec8e3e3ebd69abbf3`,
test revision `ec2309dbbdde09d5fce0a07610bc253258dd508b`, and the current QA/evidence
head is `e816f433a7616782a69b227a2bd27fbac53f57a6` on
`feature/shared-tag-input`. Later changes are test fixtures, synthetic QA tooling, docs and evidence; application,
platform, native and dependency inputs remain unchanged.
[The accepted design and receipts](https://github.com/reddraggone9/tandemlog/blob/e816f433a7616782a69b227a2bd27fbac53f57a6/evidence/shared-tags/README.md)
cover opaque tag identity, separate Add/Remove policies, pending query safety,
keyboard/composition behavior, controlled chips and query-row anchoring.

Local 621 Flutter tests, 37 tooling tests, three actual GTK workflows and the
17 screenshots/desktop recording pass independent review. The first full CI
found two legacy native interactions; the second found one guarded bulk Save
tap intercepted by an open popup (68 passed, one failed). Test-only `ec2309db`
explicitly dismisses suggestions, verifies query retention and Save hit-testing,
and strengthens rejected-Save coverage to exact prior tags. Its actual focused
GTK case and independent review pass. The hosted red and local original pass
are distinguished rather than claiming a local reproduction.
[Final full CI 37796892998](https://github.com/reddraggone9/tandemlog/actions/runs/37796892998)
passed every platform at exact ec2309: Linux621unit/69native, Windows619unit
plus2expectedLinux-onlyskips, desktop4Cargo/107native-worker/37tool tests,
and Androidstaticnative/debugbuild plusdesktoppackaginggates. This success
does not cover or resolve the separately reported blocking historical bug. Separately,
[22 hosted Windows native debug flows](https://github.com/reddraggone9/tandemlog/actions/runs/37790261412)
pass on `ff1d1f82`. The later ec2309 aggregate file differs only in three excluded
legacy fixture blocks; selected Windows test bodies and production inputs are
unchanged. Consumer ZIP/binary rehash and loaded-module enumeration are not
claimed. The [Android handoff and eight-record synthetic fixture](https://github.com/reddraggone9/tandemlog/blob/e816f433a7616782a69b227a2bd27fbac53f57a6/design/shared-tag-native-acceptance.md)
pass independent static/hash/history-chain review. These debug observations
and QA inputs do not replace exact integrated release acceptance.

Bounded actual GTK external-write and clock-boundary investigations did not
reproduce Lee's overnight Windows staleness. Their temporary observers remain
in [evidence only](https://github.com/reddraggone9/tandemlog/tree/866c11ff9eea1c17e4b808fb8b005097517f0a77/evidence/windows-idle-refresh);
no speculative redraw, polling, dependency or idle fix belongs in integration.
Windows, overnight and physical display behavior remain unverified.

The historical-recompletion fix/regression/native retest is the blocking gate.
Remaining external gates then include corrected local Android acceptance, the focused
Kotlin/tag Android runtime follow-up, installed Windows/manual visual/assistive
technology acceptance, and final signed-artifact/release-note/media review. The
parent owns those decisions and device/resource configuration. Live synced user
data remains outside this plan.

## Main integration checkpoint: 2026-10-08 17:50 UTC

The preceding pending isolated-regression status is superseded by the parent's
17:30 acceptance of the exact installed d736 debug APK (SHA256 `5e35400713e614c74730713c060e65bb3edea2d409df1cb57e7f6de94bf87a1c`) from
CI37804634954/artifact11561899292. Original pre-leak A16 recompletion, Undo,
cold replay before Undo, duplicate delivery, legacy scalar history, retained
grandchild, offline recurrence and later-parent/successor edits passed. The
reported packet SHA256 is `49ce66ebb848508cae7f96e07a938c3bd1cfb82533977f0c153bcb5ddc01fefc`; this consumer did not materialize packet
bytes. The lab stopped cleanly without new OOM/swap. This accepts the isolated
debug regression, not the composed signed package.

Parent expressly authorized main integration and main-only signing preparation.
Fresh published/successful-signed floors remained 45, rc4 absent, and build46
preflight/history checks passed. Main accepted normal non-force linear commit
`77a5f2dfde4ea914e7f2cf09dcbf77ee738056cc`, one parent `0a16a88` and entire tree
`94426a94d81559b2409a3efe108618174ae45f23` identical reviewed `56213cc`. GitHub's
linear-history rule rejected the earlier merge-based push; protections were
unchanged and the merge branch preserved. Independent final tree/range review
accepted executable equality to frozen e205 and unchanged notes/media coverage
of published `5ac35da` → `77a5f2d`.

[Main CI37819186249](https://github.com/reddraggone9/tandemlog/actions/runs/37819186249)
and [signed candidate37819214432](https://github.com/reddraggone9/tandemlog/actions/runs/37819214432)
both use exact `77a5f2d`. The successful push and remote SHA were verified before
the valid signing dispatch. An unintended earlier old-main dispatch 37818335528
failed preflight and skipped checks/signing; it is not an RC4 artifact.
The [reviewed current handoff](https://github.com/reddraggone9/tandemlog/blob/d1b3967/design/rc4-signed-candidate-acceptance.md)
records these bindings and final native/Windows/manual/UX/consumer-byte gates.
Those runs were still in progress at this checkpoint, with no signed artifact
acceptance or publication claimed. Latest supported quota was 67% at 17:30:04 UTC,
reset Oct14 10:33:41 UTC; publication still requires a fresh read. Stable feature
promotion remains unauthorized. Continue to use isolated synthetic profiles;
live synced user data and already-appended canonical proofs remain untouched.
