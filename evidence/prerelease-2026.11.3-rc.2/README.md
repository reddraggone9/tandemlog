# Housekeeping RC122 — published experimental prerelease

Source is based on main f25eb97e, which already contains published RC121 including prior RC119 work. No old candidate artifacts or claims are reused as acceptance of RC122.

Changes: shared FilledButton minimum painted height48dp with unconstrained growth; real16dp Task/Food dialog gutters at2x; reviewed crypto3.0.8, sqlite3 3.9.1 and setup-java6.2.0. Diagnostic SQLite trace/interrupt methods transparently delegate, without enabling tracing. Historical-reader harness resolves its archived manifest/lock; production historical decoder bytes unchanged. Dev reference reporting advisory; candidate and reusable defaults remain fail-closed. No format change.

Local checks:1946 Flutter tests PASS, analyze clean;312 Python tests PASS/2 skipped; native spacing16, retained Task error/keyboard6, Food form/IME/error matrix12variants, production Food5 PASS. Multi-file native launch/session infrastructure failures are preserved in private logs; isolated invocations passed. Broad task_flow aggregate stopped after54passing cases, not claimed as full native pass. Initial hosted CI43734987630 covered executable source1afb55ef; later source repairs each received fresh CI as recorded below.

Native cold start on4d45be5e: median480ms<=1000ms; samples490/460/480/520/480ms; strict first launch2610ms reported, not budgeted. Quiet window requested/admitted, services restored and fence released after measurement. Canonical result committed separately.

Independent notes review PASS, see notes-review.md. Review captures previously sent to Lee are native Linux synthetic simplified layout harness only, not Android or actual full editors. They are not release-note images; text-only notes accepted by independent reviewer. Android/Windows visual after evidence not claimed.

Architecture/docs/debt review: changes confined to shared style/layout and transparent diagnostic adapter; no new persistence format or duplicated business rules. Dependency exact source/native/runtime byte reviews retained privately in housekeeping investigation SQLITE.md and JAVA.md. Leela model-free updater already deployed separately; first scheduled skip-active observed, no newer stable installation yet exercised.

Qualification, signed candidate, exact-artifact native acceptance and anonymous public verification are completed in the final section below. Stable and all live user data untouched.


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
An independent profiling/fix worker subsequently produced the minimal repair recorded below.
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
pass logs; not claimed as a clean wrapper exit. At that repair handoff, native checks and fresh hosted
CI/full exact-source qualification were still required; subsequent completion is recorded below.


## Repaired source accepted for signed-candidate build

Exact sourcee5a36ed3: all10 hosted jobs CI43743649759 PASS, dispatched once for
that graph after local1946tests/analyze and native restored-history9/Food5 PASS.
Fresh cold-start median550ms PASS (560/550/560/550/550; strict first2670ms).
Fresh controlled reference request3c90570285f760b119339d6deb28582e compiled,
measured ONCE and sealed; absolute and both history-growth budgets PASS,
relevant-source-v3 SHA2e31fb667dc90bd7d7f769ab2f89df8a39c0c32ed8811898f9409b020e20f293.
Original executor/final/cleanup independently consistent, allpins/correctness/
timing/release gates true, no remaining exact processes/owned active units.
Three first misses passed only their automatic same-invocation confirmations;
original warnings retained in the sealed bundle. PriorRC121/q24 bundle retained
separately; earlierRC122 failures never overwritten or reused as acceptance.
Repository reference and cold-start verifiers both independently PASS.

Restoration verified: exact Transmission settings/container restored, backup
writer thawed, backup.timer restored to originalactive after stopping its new
admissions during measurement; background music/Jellyfin restored and quiet fence
released. Exact fallback timer inactive. Already-finished cold-copy unit absent.
No ARC parameter or budget change; targeted reclaim only before admission.
Native artifact acceptance, signed candidate and publication subsequently completed as recorded below.


## Published exact accepted RC122

Signed candidate43747681400 on7e280f19910e02803f3f1aef156b121d4eede242 PASS,
including mandatory reference/cold-start gates, full hosted correctness/platform
builds and owner-signed non-debuggable universal APK. Shared durable waiter
completed/downloaded all three artifact groups, inventory/checksum/source/signer/
version/installed-lifecycle verification PASS. APK SHA911349e9ddbb71b05a566be4889b0aa3c815729c29a8bcbd85728c66fb60a805.
Final independent notes review229004ef PASS over exact f25eb97e..7e280f19;
text-only notes accepted, no meaningful UX change omitted.

Independent exact-artifact Android407a8c43 and GTK422ee169 native acceptance PASS
for both stable118→122 and previous publishedRC121→122. All install-time canonical
bytes, binding/history/integrity preserved; synthetic edits append-only. Android
UID/firstInstallTime and exact read/write SAF grant unchanged. Actual native dark
2x Task/Food Save/Cancel/dirty recovery/reopen, scrolling/lower fields/keyboard
reachability,48dp buttons and16dp inner gutters verified. Android narrow390dp and
additionalwide780dp captured; GTK narrow/wide captured with physical keyboard,
not mobile on-screen keyboard. Both cold-reopened; GTK four normal exit-zero
closes total. All owned emulator/GTK processes/ports/display cleaned up. Inherited
unchanged old Search/sort/pruning manual matrix explicitly NOT_RUN; mandatory
current-change, history preservation and cleanup assertions retained. Full CI
still covers unchanged functionality. Windows hosted setup lifecycle/portable
inventory PASS; Windows GUI acceptance is not claimed.

Published 2026-11-15T19:22:49Z (13:22CST):
https://github.com/reddraggone9/tandemlog/releases/tag/v2026.11.3-rc.2
Immutable experimental prerelease with all four exact accepted assets, not Latest.
Anonymous verifier PASS on every public size/hash, APK signer/version/nondebuggable,
reviewed notes, source/tag and immutable flag. Prior55 releases/tags unchanged;
Latest remains stable2026.11.2/build118. No asset rebuilt or relabeled.

Routine dependency PR15/16/20 CLOSED after released source; held1/2 untouched.
Exact public portable RC122 staged with isolated existing copied workspace and
fresh-writer profile on Leela, separate Start-menu **Tandemlog RC test** shortcut.
Version/member hashes/profile binding/data preservation/launcher checks PASS.
**Remaining real gap:** current input desktop is locked Screen-saver; usable GUI
launch unverified without foreground takeover. No app GUI launched or desktop
switched. All real-data-derived handoff evidence remains private. Stable/live
install and data untouched; no stable promotion.

Original harness Before/After captures were accurately labeled and relayed before
RC work. Additional review media are genuine exact-candidate synthetic native
Android/GTK captures under private native-prep and the household artifact directory;
they are not release-note images. Parent handoff report lists exact paths.
