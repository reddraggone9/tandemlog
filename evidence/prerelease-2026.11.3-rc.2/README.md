# Housekeeping RC122 — validation in progress

Source is based on main f25eb97e, which already contains published RC121 including prior RC119 work. No old candidate artifacts or claims are reused as acceptance of RC122.

Changes: shared FilledButton minimum painted height48dp with unconstrained growth; real16dp Task/Food dialog gutters at2x; reviewed crypto3.0.8, sqlite3 3.9.1 and setup-java6.2.0. Diagnostic SQLite trace/interrupt methods transparently delegate, without enabling tracing. Historical-reader harness resolves its archived manifest/lock; production historical decoder bytes unchanged. Dev reference reporting advisory; candidate and reusable defaults remain fail-closed. No format change.

Local checks:1946 Flutter tests PASS, analyze clean;312 Python tests PASS/2 skipped; native spacing16, retained Task error/keyboard6, Food form/IME/error matrix12variants, production Food5 PASS. Multi-file native launch/session infrastructure failures are preserved in private logs; isolated invocations passed. Broad task_flow aggregate stopped after54passing cases, not claimed as full native pass. Full hosted CI43734987630 dispatched once on executable source1afb55ef; later commits are version/release-note metadata only.

Native cold start on4d45be5e: median480ms<=1000ms; samples490/460/480/520/480ms; strict first launch2610ms reported, not budgeted. Quiet window requested/admitted, services restored and fence released after measurement. Canonical result committed separately.

Independent notes review PASS, see notes-review.md. Review captures previously sent to Lee are native Linux synthetic simplified layout harness only, not Android or actual full editors. They are not release-note images; text-only notes accepted by independent reviewer. Android/Windows visual after evidence not claimed.

Architecture/docs/debt review: changes confined to shared style/layout and transparent diagnostic adapter; no new persistence format or duplicated business rules. Dependency exact source/native/runtime byte reviews retained privately in housekeeping investigation SQLITE.md and JAVA.md. Leela model-free updater already deployed separately; first scheduled skip-active observed, no newer stable installation yet exercised.

Qualification, signed candidate, exact-artifact native acceptance and public verification remain pending. Stable and all live user data untouched.


## Qualification blocker (2026-11-15)

Final graph daf12289 passed all10 hosted jobs in CI43737969405 (one dispatch for
that graph; earlier43734987630 passed before an independently reviewed quiet
admission infrastructure fix). Local tooling after that fix313PASS/2skipped.
Admission correctly recognizes a kernel-frozen rsync without treating its
`--exclude=.gradle` argument as an active Gradle build; controller and budgets
unchanged. Review a9189937 PASS with independent25tooling tests.

First actual reference request failed AOT compilation BEFORE measurement because
prepared package_config metadata named the alternate development cache while
the pinned controller uses the canonical cache. Original compile failure,
request, result and cleanup retained privately; no timing sample or seal claimed.
A fresh request with canonical compatible config compiled and ran once.
Its Food own-history growth `agent.write.purchaseImport2` failed both the first
sample (148.443ms small,465.95ms large,bound433.99675ms) and policy-owned
confirmation (139.583ms small,655.436ms large,bound414.06175ms). Gate rejected it;
no seal, candidate or publication exists. See confirmed-failure-summary.json.
An independent profiling/fix worker owns the minimal performance repair.
No unchanged-source qualification rerun, budget change or noise dismissal.

All setup/restoration receipts retained privately. Exact downloader settings and
container state restored; backup copy kernel-thawed; already-finished cold-copy
unit absent; music/Jellyfin restored and quiet fence released. Independent
restoration timers inactive. Targeted ARC reclaim occurred only before admission,
with c_max/module parameter unchanged and raw memory independently checked;
no extra ARC credit was granted and no cache intervention occurred during timing.


## Profiled repair

Integrated ebb0d009 (independent worktree commitc0bb55c0). Diagnostic profiling
identified stored-history decode isolate fan-out: ten workers per session and
two concurrent session opens during a planned CLI import under the2CPU quota.
One pure-data decode worker per restore preserves decoder, validation, ordering
and fallback behavior while removing history-size-dependent spawn/transfer work.
Matching bounded diagnostics: large purchase import428.728→278.161ms, growth
1.98x→1.41x, whole-family CPU9.585→7.386s. These are explicitly diagnostic, not
full qualification or substitutes for the failed original samples.
Independent code/data-integrity reviewer1b43f2d9 PASS; binding/seal/tail/sequence/
offset/migration/prefix checks unchanged, no instrumentation or budget edits.
Affected133tests PASS. Integrated full1946Fluttertests PASS and analyzer clean.
Terminal wrapper again reported descendant-cleanup unknown exit AFTER complete
pass logs; not claimed as a clean wrapper exit. Native checks and fresh hosted
CI/full exact-source qualification still required.
