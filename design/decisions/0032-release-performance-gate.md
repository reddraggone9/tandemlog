# ADR0032: release performance regression gate

Status: accepted by Lee on 2026-10-22; implementation and initial limit activation are separately evidenced.

[ADR0033](0033-controlled-reference-performance.md) prospectively changes host
roles after Lee's2026-10-25 approval:controlled reference absolute/growth
qualification,mandatory hosted correctness and advisory hosted timing. Existing
limits,coverage,seals,retry constraints and separate native/release gates remain.


## Context

RC4 exposed seconds of delay in ordinary local editing. Correctness tests did not detect this. Lee approved release benchmarks across Task and Food actions, with action-specific limits, owner approval before loosening them, investigation of redundant work first, and bounded retries for external load.

## Decision

Use a separate required release-mode AOT performance job alongside correctness tests. The versioned public synthetic inventory includes explicit and inherited Task text, capture, metadata, completion, recurrence, checklist operations, bulk actions, Food changes and Undo, readmodels, navigation preferences, peer admission and cold/warm startup. Matched history sizes must keep entity IDs and current state identical. Record dimensions, canonical bytes, warmups, every measured observation, median/maximum and paired scaling. Preserve timing boundaries and coverage gaps.

Initial limits must be calibrated and reviewed for the stated runner class before activation. Intended responsiveness on representative realistic data is separate from bulk, startup and larger synthetic regression budgets with justified headroom. Passing a generous bound does not establish responsiveness or prove history-independent complexity. (2026-10-27: the earlier "roughly 100 ms" figure was Lee's rough upper guess for a local save, not a target; see [What sets acceptable latency](../performance-gate.md#what-sets-acceptable-latency-lee-2026-10-27).) Once activated, loosening any limit requires Lee's explicit approval. Do not discard cases, redefine metrics or regenerate baselines to obtain a pass.

One timing rerun is permitted only with independently recorded external CPU pressure and unrelated work for every implicated failing size, unchanged bindings and fresh workload processes. Repeat the entire three-shape suite and both comparisons once; retain both attempts. Correctness, coverage, integrity or binding failures are terminal and do not qualify as noise.

Use generated data only in repository/CI. Seal exact source, dependency/compiler/native/SQLite binaries, package roots, limits, fixture inventory and compiled executable. Enforce bounded physical resources and finite child lifetimes with verified cleanup. Required release execution never treats measure-only calibration as acceptance.

Storage/application timings do not substitute for native input-to-visible-response acceptance. Keep separate desktop and Android observation, and report unmeasured controller, layout, paint and input costs explicitly. See [the gate contract](../performance-gate.md) and [runtime QA](../runtime-qa.md).

## Alternatives

Debug/test-runner wall-clock assertions mix compilation and scheduling noise with product cost. Private histories are unsuitable for public CI. A universal fixed millisecond cap ignores startup and scalable bulk semantics. Automatic limit updates and retry-until-green would conceal regressions. Manual-only testing lacks repeatable coverage; a standalone storage suite alone cannot accept UI responsiveness.

## Consequences and revisit triggers

CI takes additional time and requires source-bound timing artifacts even on failure. Fixture dimensions, runner changes, new actions, storage changes and regressions trigger coverage/calibration review. An actual bottleneck must be investigated before a relaxation is proposed. Hardware changes do not silently rewrite accepted limits. Signing safeguards and prerelease/stable/live-data adoption gates remain independent.

## Amendment 2026-10-26 — official rerun after non-reproduction

Lee approved one further, separate allowance on 2026-10-26: when an enforcing
reference qualification fails on timing only and separately recorded diagnostic
runs of the same source cannot reproduce any failing label, one official rerun of
that unchanged source is allowed. Pass proceeds; a second failure is repeatable
and must be investigated and fixed. Limits, coverage and the in-run noise retry
above are unchanged; retry-until-green remains prohibited. Tooling enforces the
limit and the recorded-diagnostic precondition; see
[ADR0033](0033-controlled-reference-performance.md#amendment-2026-10-26--official-rerun-after-non-reproduction).

## Amendment 2026-10-27 — borderline result on already qualified source

Lee approved on 2026-10-27 14:56 CDT: when identical relevant source (same
relevant-source identity) has already passed a qualifying check, a timing
failure within normal run-to-run variation is a borderline limit, not a
regression. It does not block the release and is queued for a look at the limit
or the scaling behind it. For exactly this case it replaces "a failed rerun is
repeatable"; the official-rerun rule stays for other cases. Budgets unchanged.

Tooling outcome `borderline-accepted` (`tool/performance/borderline.py`) fails
closed: it needs a verified earlier passing qualification of the same identity,
an otherwise complete enforcing result with correctness, coverage, replay,
execution and all absolute limits passing, and only history-growth misses each
at most 5% over its bound. The declared band comes from q9–q11 storageAdmission
growth at 99.8%/96.3%/101.6% of bound on identical code. It writes a queued
follow-up record naming each borderline metric. Rejected alternatives: a band
computed from the passing receipts' spread (one or two receipts give no usable
spread; a wide one would loosen limits silently) and accepting any miss of
passed source (retry-until-green). Revisit if borderline results recur on the
same metric: that is a limit or scaling problem to fix, not noise. Details:
[borderline result](../performance-reference-qualification.md#borderline-result-on-already-qualified-source).
