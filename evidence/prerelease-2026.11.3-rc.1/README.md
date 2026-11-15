# 2026.11.3-rc.1 / build 119 — validation in progress

Scope: Tasks and Food retain selected rows that still match a changed Search;
Food without expiration sorts before dated Food, including Search. Normal Inbox
above Stock and Deleted recency ordering stay unchanged. No persisted-format,
schema, replay, migration or Undo changes.

## Review and local checks

- Combined source is linear atop stable118; Search6ef5087 and ordering9ae31b4.
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

Hosted correctness/build/native CI, controlled reference performance, native
cold-start receipt, signed candidate, exact-artifact Android/GTK upgrade checks,
publication and anonymous verification are pending. No candidate is accepted or
published by this record. Windows GUI coverage is Lee's trial, not hosted CI.
