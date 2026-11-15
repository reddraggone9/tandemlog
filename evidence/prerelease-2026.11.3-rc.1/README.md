# 2026.11.3-rc.1 / build 121 — published experimental prerelease

## Published build121 acceptance

Published [v2026.11.3-rc.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.11.3-rc.1)
on 2026-11-15 at 13:41:07Z, candidate 43713450238, exact source
`77dadb649e2ba6fafa0b7f613dc71b8717f96a55`. Immutable prerelease, **not Latest**;
stable2026.11.2/build118 remains Latest. Reusable private-draft repository tools
ran all source/provenance/signer/inventory/checksum gates; no artifact rebuild.

- Exact source CI 43711307056: all 10 jobs PASS, including reference verification.
- q24 sealed benchmark reused only after repository v3 identity re-verification
  PASS. Native cold-start 470ms retained. No benchmark/native timing rerun.
- Exact signed121 APK and Flatpak freshly accepted over stable 118 and RC117:
  all four paths, 12 native checks each, PASS. Canonical prefixes, install identity,
  Android SAF grant, isolated binding, SQLite integrity and GTK normal exits pass.
  See `build121-native-acceptance.json` for explicit exclusions and evidence caveats.
- Final independent minimal anchor repair and actual notes recheck PASS;
  three reviewed native synthetic Before/After comparisons and separate
  purchase-import improvement bullet published. See `build121-notes-review.md`.
- Anonymous public verification PASS: all four downloads match accepted hashes
  and sizes; APK owner signer/version121/non-debuggable verified; source tag,
  exact notes and all three commit-pinned image bytes verified; 54 prior releases
  and 54 prior tags unchanged. See `publication/public-verification.json`.
- Windows hosted install lifecycle and portable member provenance PASS. No Windows
  GUI acceptance is claimed. Exact121 isolated Leela portable installation and
  shortcut are staged; usable GUI launch remains unverified on its locked desktop.
  Release step 6 handoff completion remains tracked separately by its owner; this
  is not a publication gate under steps 3–5. Stable/live data untouched.

### Historical validation record

The following earlier pending/failed-candidate entries retain their original
attribution and are superseded only by the exact build121 acceptance above.
Rejected signed 119 and 120 were never published; q23 failure is not a pass.

Scope: Tasks and Food retain selected rows that still match a changed Search;
Food without expiration sorts before dated Food, including Search. Normal Inbox
above Stock and Deleted recency ordering stay unchanged. No persisted-format,
schema, replay, migration or Undo changes.

## Review and local checks

- Combined source is linear atop stable 118; Search6ef5087 and ordering9ae31b4.
- Independent code/docs review found a stale-target race across the dirty-editor
  prompt in both Search handlers; fixed in 8829707, with before-fail/after-pass regression coverage.
- Full Python tooling: 310 tests pass, two skipped. Static analysis clean.
- Dart formatter: 509 files unchanged. Combined Flutter suite: 1,924 passed before the follow-up correction; 25 targeted tests and focused analysis passed after it.
- Native Linux synthetic production-UI captures: 8/8 Before and 8/8 After; native selection parity: 16/16. Captures cover 2c0a4ef to 9ae31b4, not the subsequent guard correction. Independent screenshot review passed after correcting an initial-frame capture. Three comparison images under design/media/search-food-20261114. Dark/light, wide/390px and 200% ordering checked. No Android/Windows or signed-artifact acceptance claimed.
- Media recipes, raw captures and logs retained privately in tandemlog-next-20261114/media; pre-existing grammar/unit-wrapping observations are not release blockers.
- Final code follow-up review passed. Independent notes/media review found duplicate image links and excess image captions; corrected and rechecked successfully. Final reviewed media committed in 33d1764. Native synthetic review captures delivered to Lee before candidate work.
- Final focused Search/Food regressions: 48 passed.
- Initial hosted CI on f053075 found a stale native integrity-test finder: Search correctly retained the editor, so the task title matched both editor and list row. Reproduced natively; test-only correction 4fa63ca targets the keyed row and explicitly asserts retained selection/editor. Original failing native test passed after the fix; complete native integrity group passed 2/2. No integrity, draft or Undo assertion removed.
- Original PR CI 43644360497: all non-reference jobs passed except native shard 1; union skipped. Manual CI 43644355241 ran redundantly and was cancelled by the next source push. Fresh automatic PR CI 43646368424 tests 4fa63ca; redundant manual dispatch 43646363311 was cancelled before execution. Retain the original failure rather than treating the corrected run as an unchanged-source retry.

- Final-source local coverage inventory searched both host and integration trees for Search, selection, Food sort and expiration: 166 matched test/helper files. Full host suite 1,926 passed; full native workflow aggregate 274 passed; supplemental standalone coverage 29 passed plus the F1 workflow passed in the initial supplemental run. An initial supplemental aggregation viewport leak was diagnosed; isolated recurrence passed 2/2 and the corrected aggregate passed without product changes. Temporary harness removed.
- Corrected CI 43646368424 on 4fa63ca: all nine non-reference jobs passed, including all four native shards and the union gate. Only the expected stale-reference verification failed.

## Release gates

Source e0f0d4a: CI43662967224 all nine non-reference jobs PASS. Controlled q20 reference qualification sealed: absolute and both history-growth budgets PASS; two first-pass growth misses passed the gate-owned fresh-process confirmation. Native cold-start median 530 ms PASS. Signed candidate, exact-artifact Android/GTK checks, publication and anonymous verification remain pending. No candidate is accepted or
published by this record. Windows GUI coverage is Lee's trial, not hosted CI.

Independent accounting review rejected blanket evictable-DATA credit: small ZIO
linear buffers use reclaim-accounted slab represented in MemAvailable. Reviewed
controller now grants zero extra ARC credit (raw availability only), preserving
all pressure thresholds and workload bounds. Independent zero-credit review and all 310 local tooling checks passed (two
skipped). Reviewed q20 qualification completed and sealed on e0f0d4a; no budgets relaxed.


## Build120 superseding validation

Candidate119/run43675529532 was rejected; it is not accepted for publication.
Production fixes include the Food Search focus correction5050a395 and bounded
admission memo hashingead92a2. Independent review PASS64; full host suite1928 PASS.
Exact sourceead92a263b103bca6fd9ca0969520078b0c9adfe: CI43694706786 all nine
non-reference jobs PASS (receipt alongside). Native cold-start median470ms PASS.
q23 remains an immutable failed qualification; it is not reused or relabeled.
q24 sealed on that exact source: absolute and both growth budgets PASS with
zero extra ARC credit (raw available minimum9.65GiB). Three first-pass misses
passed the policy-owned same-invocation confirmations; warnings remain in the
receipt. Prior q20/current evidence is retained separately, not overwritten.
Current reference and native receipts independently verified by repository tools.
All paused household work restored. No budget/source-identity change.
Exact signed120 Android/GTK stable 118 and RC117 upgrade acceptance, Search focus
regression, publication and anonymous verification remain pending. Windows GUI
coverage remains Lee's isolated portable trial, not hosted CI.

## Build121 reviewed anchor repair

Signed120/run43704078041 is rejected and unpublished: exact GTK RC117 upgrade
acceptance exposed a Search-hidden Food range anchor being resurrected by the
wide single-editor transition. Build121 repairs only that transition and adds
widget/native regressions; independent review 6c0f67da PASS, notes recheck PASS.
Full host inventory1928 PASS plus two corrected-environment fixture checks PASS;
native retention3, keyboard2, row selection6 and layout parity16 PASS.
Private before/after captures and logs: rc121-anchor. q24 relevant-source-v3
identity remains unchanged; no benchmark or cold-start measurement rerun.
Fresh exact CI, signed candidate and artifact acceptance pending.
