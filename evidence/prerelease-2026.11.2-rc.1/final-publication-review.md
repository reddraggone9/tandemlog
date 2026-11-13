# RC117 independent final publication review

2026-11-13. **Verdict: PUBLISH-READY for signed `v2026.11.2-rc.1` / build117, prerelease and not Latest. No candidate/source/native blocker found.** This is not publication, a full original-preparation-matrix PASS, a completed handoff, or stable acceptance.

## Independence and authority

Read Lee’s standing rules in `projects/tandemlog.md` and the actual release checkout’s `design/releases.md`. Lee authorized an RC; the standing procedure authorizes maintainer publication after review. Stable remains forbidden until Lee tries the RC and reports no problems. The explicit current restriction on physical devices/live data was honored. This reviewer made no checkout edits, CI dispatches, publication, installations, device calls, or live-data actions; only this report was authored. GitHub calls were read-only.

Quota checked with `python scripts/worker-quota-policy.py --chatgpt-only`: ChatGPT week91%, above30% floor; route ChatGPT. Independent ChatGPT review substitutes for unavailable Fable; no claim of a Fable review.

## Exact identity and independent checks

- Checkout HEAD and both fresh GitHub run observations: `518be438f18246c232c02149897a9e0801069604`.
- Main CI43482632158: completed/success, push, CI. Signed candidate43482661551: completed/success, workflow_dispatch, Build signed candidate. Saved job lists have every job successful, including all four Linux workflow shards, union, reference verifier, Linux/Windows/Android correctness and signed Android.
- Recomputed all four installer/archive SHA-256 values from the actual downloaded dist, matching native acceptance, candidate verification, waiter download inventory and final verification:
  - APK: `5cc396e3ceddd825b025de2e6be5ba8fe179a9b14b4680d75b1a0db88aa5b2a2`
  - Flatpak: `b2792af31d0deb642f772efabe8e18a0eac1a9140e5896afded283627e8090ed`
  - Windows setup: `4a170171b13f8fb0a43decba695e9ee19f7465c42c2d3f12b9408c78949fb98c`
  - Windows portable: `63b6b37f51c3b8fa768cb0997a79b2617a2ea743ff305732337d1aa9d3762345`
- Android metadata binds source, version2026.11.2-rc.1, code117 and signer pin `0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d`. Existing verification records non-debuggable, universal required ABIs and APK v2 signature. No APK rebuild is being accepted as the published asset.
- Waiter `candidate43482661551/wait-status.json` is terminal success with exact run/source/repository; complete download receipt is present. Recorded service result: ActiveState=active, **SubState=exited**, Result=success, ExecMainStatus=0. Active here is the retained successful oneshot, not a still-running wait. This review inspected the recorded terminal service evidence, not a new service activation.
- Independently reran both committed source-bound verifiers as the engineering checkout owner: `reference_receipt.py verify --repo …` PASS; `native_cold_start.py verify --repo …` PASS. Initial invocation as Lee failed Git’s ownership check; rerunning read-only as nibbler resolved that local invocation problem without modifying global Git configuration.
- q17 request `76fe0f5e24537af72e12d1680fe588ba`, relevant-source-v3 `2afefe81ee6b52335b0f11670b5eb32f454be599c61b3f9552deb44cef417172`:261 labels ×3 shapes =783 observations; both growth rules passed. Three first misses cleared their automatic fresh-process confirmations in the same invocation; zero confirmed misses. Retained admission failures are distinct from measured retries. No new benchmark run was requested.
- Native startup receipt: median490ms, budget1000ms; samples520/510/480/480/490; strict first launch2800ms is separately disclosed. This is not a universal 60/120fps claim or a claim that every startup frame is under16.7ms.

## Raw native acceptance corroboration

Evidence root, private and local only: `/home/lee/aux/vex-private/tandemlog-rc117-20261113`.

Read actual `native-acceptance-summary.json`, `native/final-evidence-verification.json`, both workflow reviews, preservation receipts, Android final result/integration receipt, GTK upgrade/binding receipts, raw before/installed/after canonical files, and hosted Windows lifecycle receipt.

- Independently compared original canonical files to immediately-installed files: both files identical in each lab; GTK original SQLite also identical. Independently compared final canonical prefixes: all original files retained their exact initial bytes. This corroborates preservation instead of trusting the helper’s booleans alone.
- GTK upgrade receipt identifies retained2026.11.1 to exact2026.11.2-rc.1 bundle with the accepted Flatpak hash; binding/person metadata preservation is recorded. All five retained main GTK normal-exit files are0. Semantic review records17 checks; this is not17 hosted tests or a Windows claim.
- Android retained package snapshot shows116→117, unchanged firstInstallTime and identical canonical hashes immediately after installation. Final result binds the accepted APK hash, synthetic SAF folder/person/writer, SQLite `ok`, native integrity pass, no repair, and cleanup with emulator/owned ports absent. Twelve semantic assertions are all true. The helper’s `workflowCoverage=PENDING` expressly covers install-only; completed workflow review is separate, not silently invented from this field.
- Recomputed all100 Android manifest image hashes. Checked final verification’s Android review hash, final-result hash, combined-summary hash and public-manifest hash against actual files: all match.
- Inspected actual native screenshots: Android persistent Food, large task editor, Unicode cold-reopen, final integrity; GTK imported learned row, narrow200% Light task editor, final integrity. They show the claimed synthetic rows, estimated markers, readable wrapped editor/actions, retained Unicode/multiline text (with the disclosed missing emoji glyph), and matching integrity totals: Android2logs/46records/94305bytes; GTK2logs/60records/122402bytes. Private integrity screenshots contain local test-folder identifiers and correctly are not selected for the public bundle.

## Disclosed limitations are not publication blockers

1. **No Windows GUI:** explicitly consistent with release policy, which uses hosted installer lifecycle plus portable inventory and leaves GUI trial to Lee. Actual Windows receipt reports passing after-install, after-upgrade, after-uninstall and after-reinstall phases. Do not substitute that for a GUI test claim.
2. **No native receipt-import UI:** GTK uses the exact installed Flatpak bundled CLI plus inspected native results. Android uses exact-source production APIs on the private current synthetic canonical copy, then synthetic peer append-only replay into the isolated SAF folder plus native result inspection. The Android integration receipt distinguishes birth and existing-container link effects, duplicate receipt behavior and preserved peer prefix. This is meaningful integration evidence but not execution of the APK’s import UI or proof of that UI’s file-picker path. Current policy does not require adding an unrelated new import-UI gate to this frozen RC; retain the explicit limitation.
3. **Preparation assumptions were wrong, not accepted-source regressions:** independently checked Food Search code resolving drafts then clearing selection (`food_page.dart:333`), required expiration (`food_editor.dart:418`, required-expiration tests), and manual date never-estimate contract (`food_shelf_life_ui_test.dart:539`). Manual prefill remains confirmed; receipt-calculated dates are estimated. Do not report the old assumptions as passed. Viewport retention and Search-input behavior are different contracts.
4. GTK has only one retained person; Android covers creation/switch/restoration of a second synthetic person. No claim of GTK multi-person startup. No newer prior RC beyond stable116 is being fabricated. The emulator’s missing bean-emoji glyph is disclosed, with persisted codepoint evidence separate from rendering.

## Public evidence, media and records

- Independently verified exact public inventory: **67 checksum-covered files plus SHA256SUMS (68 total)**; no extras or missing manifest entries. This resolves the harmless67/68 wording difference between the task and final verifier.
- Representative public images visibly contain synthetic RC117/seed data and synthetic tester names, not household records. Inspected public JSONs for household host paths, SAF URIs, live-data paths and credential markers; none of those strings appeared. Public UUIDs in integration summaries identify synthetic fixture effects, not household records. Raw profiles/canonical logs/failures remain private.
- Read the independent editorial `artifacts/tandemlog-rc-20261113/recheck.md`. All eight repo Before/After PNGs are byte-identical to its reviewed originals; notes link every image and all paths exist. Independently checked application `lib/` delta from editorial HEAD02cb56e5 to candidate518be438: empty. No new UI review is needed merely because release tooling/evidence landed afterward.
- The release README still has old preparation/pending wording at review time; another owner is editing evidence concurrently (working-tree README/native changes observed). Routine finalization must replace stale pending status with actual completed candidate/native evidence and these explicit gaps before publication. Do not change source/build or rerun CI for this records-only integration.

## What remains — publication before handoff

Proceed through the already-reviewed RC private-draft publisher: exact candidate source/assets, main-pinned reviewed notes/media, **all four** assets present before finalization, prerelease true, Latest false. Run the existing publication gates; anonymously verify the final public assets/hash/size/APK identity/signature, tag target, notes/media and unchanged Latest/historical state. This reviewer did not run mutation commands or independently re-review the publisher implementation; its prior independent tooling review/tests remain the supplied prerequisite.

**Handoff is NOT ready-to-use.** The private Leela directory contains prepared isolation/profile/launch scripts and compiled helpers only; no installed/coexisting/bound/usable-launch receipt exists. No physical-device work was attempted here. Publication readiness does not finish release delivery: after public verification the parent must retain handoff as unfinished under the current no-device/live-data restriction. Do not tell Lee the RC is installed, give a nonexistent working shortcut, or ask him to start testing yet. A later authorized handoff must use the accepted portable ZIP, separate non-synced profile/data and verified coexistence/binding/usable launch. Stable promotion/live rollout remain unauthorized.

**Final decision: publish-ready candidate; no new QA, source fix, CI redispatch or qualification needed. Finish accurate evidence integration, gated prerelease publication/public verification, then track the separately blocked handoff.**
