# Composed preview: 2026.10.2-rc.4+46

Historical preparation snapshot below. Main integration and isolated Android
regression acceptance subsequently completed; see the [current signed-candidate
handoff](rc4-signed-candidate-acceptance.md) for authoritative source/run bindings
and remaining exact signed-package gates.

Status: preparation authorized by parent on 2026-10-08 while the exact isolated
historical-leak retest proceeds. Composition is separate from all frozen candidates.
No main merge, owner signing or publication has occurred. Stable feature promotion
still lacks Lee's approval. The earlier integration plan's wait-before-preparation
sequence is superseded for this authorized branch preparation; acceptance gates
remain required.

## Exact composition

Branch `preview/shared-history-checklists-final`, based on freshly verified main
`0a16a88355823d74c98246ed55f1ce85e45428ab`. Three explicit clean merges:

| Reviewed input | Exact source | Included change |
| --- | --- | --- |
| Shared B | `e816f433a7616782a69b227a2bd27fbac53f57a6` | Reviewed common chips/query tag input and corrected interaction fixtures; includes the reviewed shared-history/checklist/queued-fix ancestry |
| Historical fix/evidence | `19377652d65567ddb5c725e4462fc28ef8820e95` | Compiled fix `d73662ab8479aa8076ee04a5ed5badd1542e585d`, source-bound native historical retention, regression and qualified CI/native handoffs |
| Narrow Kotlin remediation | `1b8f0cc5c6eeb302519231d7269ee37a529e36d0` | KGP2.4.0→2.4.20; reviewed provenance, graph and cold/warm evidence |

The merge-only composition is `d99d03d3be03601d109a748b083e3fa2bdd0b578`.
There were no conflicts. Automatic `task_flow_test.dart` merging adds only the
historical import/registration to the final tag registry, preserving its corrected
fixtures. Four tag production files equal the reviewed tag source; the two domain/
storage fix files equal the reviewed fix; Android settings equal reviewed Kotlin.
AGP9.1.0, Gradle9.3.1, pub/Cargo locks, other platform and native inputs stay exact.
No save-delta/cache-only/trial/idle instrumentation branch is stacked. Kotlin's
existing observer remains conditional on its remediation branch and does not run
on this branch/main. The actual integrated build/native gates still must pass.

Version becomes `2026.10.2-rc.4+46`, expected tag `v2026.10.2-rc.4`.
Fresh published and successful main signed-candidate floors are 45; rc.4 is absent.
Recheck these floors immediately before main/signing because another candidate
could consume 46. This changes metadata only and never repurposes a handed-out APK.

Independent correctness, architecture and security composition review found no source
must-fix. Current gates and exact executable/test source will be recorded in
`evidence/final-preview/`; source SHAs identify compiled inputs, while later
evidence-only commits are qualified separately. Existing isolated receipts remain
historical component evidence, not combined-artifact acceptance.

## QA delta and acceptance sequence

1. Parent's isolated fix retest continues against artifact 11561899292/source
   d73662a and [handoff19377652](https://github.com/reddraggone9/tandemlog/blob/19377652d65567ddb5c725e4462fc28ef8820e95/design/historical-checklist-native-acceptance.md).
   Verify actual ZIP/APK bytes and signer first. Start from genuine exported
   checkpoint through A16, before the leaked A17 proof. Recompletion, global Undo,
   cold replay before/after Undo and peer convergence must preserve child task and
   all five item snapshots. The fix prevents new incorrect proofs; it does not
   repair an already leaked canonical history. All participating preview peers
   must run the updated reader. Preserve the failed original and its evidence.
2. Run full integrated CI once against the exact rc.4/build46 composition:
   formatting/analysis, unit/integrity/compatibility/delivery/recovery invariants,
   native worker/Undo/resource contracts, full Linux app suite and all platform
   build/native/packaging/installation gates. Inspect native integrated tag and
   historical workflows and actual pixels; preserve failures and resulting changes.
3. Relative to isolated d736 APK, the combined artifact changes tag editor/bulk/
   filter UI, Kotlin plugin and version. Verify the new artifact's own checksum,
   signer/package/version/build and runtime FFI; earlier hashes do not transfer.
   Keep approved 6GiB/2CPU/one-AVD synthetic test isolation and parent storage-path
   constraints. Test real Android IME/composition, chips/keyboard/suggestions,
   opaque existing/new tags, pending-query Save/Cancel/Discard, bulk Add versus
   existing-only Remove and filter-only selection. Exercise Kotlin-backed SAF
   picker/grant/reopen/refresh callbacks and lifecycle, existing recurrence/
   checklist/text/integrity/Undo flows and stable-v3 readability. Never touch live
   synced user data or copy private writer identities between peers.
4. On exact integrated Windows payload, complete affected native application,
   installed-release/manual visual/keyboard/assistive-technology checks. Prior
   debug 22 tag flows and 1 historical flow support the components but do not accept
   this integrated release payload. Linux at phone width is not Android; hosted
   Windows debug execution is not signed-release or physical display acceptance.
5. Obtain fresh parent quota before publication and confirm the reviewed scope/
   floors. Prepare the reviewed main integration, then use existing main-only
   Build signed candidate. Do not relax workflow/source, owner-pin, monotonically
   increasing version/build, full matrix or native payload gates. Consume the
   exact non-debuggable owner-signed Android and exact installed Windows release
   artifacts for final acceptance; verify source/version/signers/notices/hashes.
6. Review concise user-facing release notes and one real dark Before/After image
   per useful visible change against the exact prior-preview→final-source range.
   Required distinct UX audit covers five rapid captures, interrupted edits,
   incoming updates, user switching/error recovery, desktop/narrow layouts,
   both themes/larger text and genuine Android IME/provider behavior. Reuse prior
   unchanged-input evidence only with explicit source/coverage qualification.
7. Only after every required gate passes, publish the authorized preview using
   those accepted artifacts without a rebuild, prerelease=true/latest=false.
   No stable promotion without Lee's explicit feature acceptance. No more idle
   exploration or speculative redraw/polling fix is part of this scope.

Owner-signed workflow artifact expiry is five days; an expired artifact requires
a fresh build and exact native reacceptance. Current latest published preview is
v2026.10.2-rc.3 and stable is v2026.10.1; source/version floors and final acceptance
receipts are authoritative at execution, not this planning timestamp.
