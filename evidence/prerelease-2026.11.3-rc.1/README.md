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
- Release notes/media independent review pending.

## Release gates

Hosted correctness/build/native CI, controlled reference performance, native
cold-start receipt, signed candidate, exact-artifact Android/GTK upgrade checks,
publication and anonymous verification are pending. No candidate is accepted or
published by this record. Windows GUI coverage is Lee's trial, not hosted CI.
