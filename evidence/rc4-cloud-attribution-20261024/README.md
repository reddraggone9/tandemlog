# RC4 cloud development attribution, 2026-10-24

Development diagnosis and correctness evidence only. Performance acceptance is
**not complete**. No release, live conversion, personal fixture, signing change,
dependency update or limit adjustment occurred. Windows foreground/hardware
validation remains separately pending; no Farnsworth access was used.

## Source and method

Base: `2507e7161be822b0f8a4d7d57a46bbfcc19e5d83` on
`fix/rc4-task-latency-20261022`. The source-only handoff from local transfer
`efe24c400d6240784cd95425fa25a50a7a34caac` was applied and all five supplied Git
blob hashes matched ([receipt](handoff-receipt.json)). It was then reviewed,
corrected, formatted and tested. That local transfer commit was never fetched
or represented as published.

The pinned SQLite3.7.0 native payload omits `sqlite3_trace_v2` (`SQLITE_OMIT_TRACE`).
The unsupported proposed native callback was removed, preserving SQLite bytes
and build options. Optional delegation records Database/PreparedStatement API
wall intervals; these include binding and result conversion and are **not**
engine statement/trigger counts. Native intervals include JSON/FFI/native work.
Observers receive operation names, no SQL/parameters/request contents. Observer
faults cannot replace operation results/errors. Tests cover transaction control,
failed BEGIN/COMMIT/automatic rollback, queue ordering/drain, delegate APIs,
observer disabling, and native success/failure. No native callback is retained.

All224 ordinary AOT action IDs receive bounded cost partitions in diagnostic
mode, including Food, completion, converted targets and first activity/Undo.
The eight startup metrics retain aggregate phase timers. Raw per-sample spans
are written after the measured action and remain in the disposable run output.
Fixed overlap precedence makes exclusive coverage sum exactly to elapsed time;
inclusive operation sums must not be added. This is interval coverage, not causal
async attribution. Overflow/callback faults invalidate diagnosis. Enforcing runs
cannot enable diagnostics; `--diagnose-costs` requires `--measure-only`.

The unchanged activated limits SHA256 is
`50a606cb302eb6a769c760188901132fb8b35b153ecc41dde11a17c95b39742e`.
No case IDs, history shapes, sample counts, first-use checks or retry rules were
removed or relaxed.

## Repairs supported by the review

1. Task comparison tokens query the same live ordered/visible SQL rows every
   call. Exact raw-string/order equality reuses only JSON serialization, bounded
   to4096 rows and a conservative4MiB string/token estimate, cleared on close.
   Changed bytes, visibility/order, staged SQL and rollback retain the uncached
   oracle. Freshness/admission/commit/native ownership checks remain separate.
2. Semantic admission collects Task events without an unused entity regrouping.
   Only the existing exact unchanged canonical-set proof permits skipping sort;
   changed Task evidence retains canonical sort/hash/validation. The regression
   covers peer Food changes, pending references/resolution and a peer Task change.

Repeated provider observations have **not** been removed just because their
await intervals are large: preparation needs a fresh observation, final write
validation must reject peer changes, and confirmation/tail recovery preserve
durability and acknowledgement semantics. Rejected Save must preserve subsequent
typing. These guards are not interchangeable with representation reuse.

## AOT observations and retained failures

[Instrumented before-memo report](aot-instrumented-before-memo.json) and
[uninstrumented after-memo report](aot-uninstrumented-after-memo.json) retain all
per-action summaries, absolute/paired failures, source pins, execution/noise and
the full original report hashes/locations. Original reports/logs remain under
`/workspace/scratch/rc4-cost-dense-20261024` and
`/workspace/scratch/rc4-aot-after-snapshot-20261024`. Each completed all three
sealed shapes,232 metrics, first-use/full replay correctness, no source rewrites,
all pins matched and **zero retries**. Each has timing failures and
`releaseGateAccepted=false`. Instrumented versus uninstrumented timings are not
a controlled speedup comparison. The after-memo run's two paired failures both
implicate peer-Food admission, motivating the exact-proof sort repair.
[All-action diagnostic summary](aot-all-action-cost-partitions.json) retains
every ordinary ID's median/maximum and median-sample exclusive partition for
each shape:1120 measured ordinary partitions per shape, all complete.

The [final uninstrumented recheck](aot-uninstrumented-final.json) completed from
frozen product/tool source under `/workspace/scratch/rc4-aot-final-20261024`:
all three shapes passed correctness/232-metric coverage and full replay, all
pins matched, zero retries. Dense-food passed its absolute limits. Dense-1 failed
title/Notes Undo and cold startup; dense-2 failed converted bulk-reorder Undo,
checklist add, historical Food-details Undo and cold startup. Both paired checks
still fail; exact per-case samples/bounds remain in the report. Peer Food changed
no Task evidence and ran zero Task sorts in every sample, but its Food-history
paired median still fails. This is not complete performance repair/acceptance.
The cloud cgroup permits16GiB/4CPUs and is not the required
6GiB/2CPU/no-swap release environment. Exact-commit enforcing CI is separate.

## Linux release framework diagnosis

A separate copied tree built the release-only
`integration_test/linux_release_action_costs.dart` target; the controller refuses
the ordinary application without its compiled sentinel. [Build log](linux-diagnostic-build.log),
[input source pins](linux-input-source-pins.json) and bundle hashes in each result
bind the inspected inputs/outputs. Source and bundle stayed unchanged during
each probe. Automated source-to-binary attestation is explicitly false.
The committed build-log view trims trailing whitespace; local-checks.json records
the original unmodified log's hash/location, and that original remains retained.
All333 pinned diagnostic inputs match the development checkout except JSON
Unicode escape formatting in coverage-v1.json; its parsed content is identical.

One fresh process per shape, GTK1280×720 in cloud Xvfb1600×1200, software GL,
Light theme, public synthetic data only. Hit-tested framework pointers and the
framework text channel exercise nine actual application paths; polling does not
force frames. Timers stop at a framework post-frame callback, **not presented
pixels or OS input**. Screenshots are outside action timers. Separate engine
frame build/raster durations share neither a presentation acknowledgment nor a
causal timing sum with action intervals.

| Action (framework post-frame ms) | Base1320 | Task2640 | Food2640 |
|---|---:|---:|---:|
| Task open |125.084|89.856|112.773|
| Title Save |492.429|392.697|378.972|
| Title Undo |486.387|539.686|409.140|
| Complete |473.917|471.184|635.106|
| Completion Undo |440.178|516.037|542.635|
| Food section |102.268|116.279|99.236|
| Food open |35.751|35.734|36.998|
| Food Save |219.342|268.260|239.677|
| Food Undo |180.373|305.534|85.760|

All three pass semantic Task/Food restoration, six actual action appends,
canonical-prefix preservation, fresh full replay with unchanged canonical bytes,
native resource disposal, controller-owned WM_DELETE and normal process exit0.
Every action partition is complete and reconciled. Results:
[base](linux-dense1-result.json), [Task growth](linux-dense2-result.json),
[Food growth](linux-food-result.json); full verification/frame events:
[base](linux-dense1-events.jsonl), [Task growth](linux-dense2-events.jsonl),
[Food growth](linux-food-events.jsonl).

For base title Save492.429ms, exclusive interval coverage is SQL5.344ms,
native8.104ms, durability3.948ms, provider-await287.951ms,
refresh residual104.243ms and unclassified80.849ms (plus queue/body/control).
Provider await includes event-loop/scheduler waiting; it is not measured kernel
I/O service time. Refresh residual includes decoding/hash/Dart work and scheduling.
SQL/native API duration alone does not explain the pause. Render/scheduler,
allocation, direct raw SQL and separate write/flush attribution remain gaps.
Food section's large unclassified interval is also unresolved. These samples do
not establish median/tail or all-action UI acceptance. No limits were loosened.

The [Task](tasks-linux.png) and [Food](food-linux.png) screenshots were visually
inspected: realistic synthetic rows, readable controls and correct section/user
state, with no observed layout defect. They are Linux screenshots, not Windows
or Android evidence. [Earlier harness failures](prior-harness-failures.json)
retain missed-hit and ambiguous-selector failures; those harness corrections are
not retries under the release timing-noise policy.

## Local checks and remaining gates

[Log hashes/tails](local-checks.json): full unit suite1500 passed before the final
sort-only optimization; final focused120 passed afterwards (history, projection
atomicity, workspace/Food, snapshots, diagnostics and rejected-Save/text guards).
Tooling166 and Windows harness controls20 passed. Analysis and formatting clean.
Default Linux release build, native payload/ABI, fresh/warm startup and normal
owned-window exit passed. No foreground Windows run or hardware timing occurred.

[Exact-commit enforcing CI40124976992](https://github.com/reddraggone9/tandemlog/actions/runs/40124976992)
finished for `cb1ea0e1317cd4550ced8349894076652d4e0cfd`, calibration=false:
Windows and Android passed. Linux passed1500 units,166 tools,4 Rust cases,
analysis/formatting, release build and native payload, then normal startup close
crashed with SIGSEGV after readiness. Later packaging/native workflow checks
were skipped. [Receipt](ci-receipt.json), [failed close](ci-linux-startup-failed.json)
and [enforcing performance results](ci-enforcing-performance.json) preserve the
failures. The performance job ran under6GiB/2CPU/no-swap/pids128, completed
correctness on all three shapes, and failed absolute/paired timing. No retry
qualified and none ran. Its terminal timing failure precedes the final
allPinsMatch/measurementCompleted flags; do not turn their absence into a pass.

For example, one Food-details Undo165.926ms includes156.746ms inside the combined
durable append/barrier await, with16.295ms process/cgroup CPU and no quota
throttling in that bracket. This does not isolate syscall service time or prove
an external cause; it does rule out safely removing that durability guarantee to
fit a limit. Another Save206.569ms includes183.773ms append/barrier await.

The [separate Windows QA build40124968554](https://github.com/reddraggone9/tandemlog/actions/runs/40124968554)
passed on the same source, artifact12573485040 (expires2026-10-29). No foreground
run occurred. A local GDB controller initially failed before sending WM_DELETE;
its corrected diagnostic and the reusable tool both observed normal exit and
verified cleanup. Those clean local runs do not erase the CI SIGSEGV.

The initial standalone `rc4-linux-close-diagnostic.yml` captured GDB stacks on the same
Ubuntu24.04 image using at most three fresh public synthetic processes and stops
at the first crash/error. It changes no required gate and performs no AOT retry;
its results never establish timing/release acceptance. Every process result,
native stack and exact test-only bundle is retained. Related upstream Linux
shutdown defects exist ([FlTaskRunner193742](https://github.com/flutter/flutter/issues/193742),
[FlView192873](https://github.com/flutter/flutter/issues/192873)); equivalence is
unproven without this crash's stack. No SDK/dependency/workaround change has been
made on that inference.

[Targeted diagnostic40126806083](https://github.com/reddraggone9/tandemlog/actions/runs/40126806083)
completed on5080c7e: all three normal WM_DELETE closes exited0 under GDB, no
forced cleanup, both debugger/inferior stopped, bundle unchanged. The
[complete report](ci-linux-close-diagnostic.json) binds artifact12572758425,
SHA256 bdd68e156dc4c887ff8bffe81ca14cedc68e1597f7aeab6e2d8653cb6b3c7a36,
retained until2026-10-29. The native library SHA256 matches the failed smoke's
fixture receipt. The original SIGSEGV remains un-attributed and unwaived; these
three non-reproductions are not proof of a fix. No production workaround was
introduced without a stack identifying the faulty lifetime.

The diagnostic addition leaves product/native source, dependencies, performance
source/limits, and required CI workflows byte-identical to cb1ea0e. Its two new
controls bring the local tooling suite to168 passing with the configured
toolchain. Windows CI's full suite completed1498 passed with2 platform skips;
the job, native contracts, product build and installer checks succeeded.

Resumable cloud checkpoint: `/workspace/scratch/rc4-cloud-checkpoint.json`;
toolchain: `/workspace/toolchains/env.sh`. Original failed CI startup/performance
ZIPs and logs remain in `/workspace/scratch/rc4-ci-linux-startup-40124976992`
and `/workspace/scratch/rc4-ci-performance-40124976992`; the targeted debugger
archive (including the exact test-only bundle) remains in
`/workspace/scratch/rc4-linux-close-ci-40126806083/artifact.zip`.

No authorization denial or pending push remains. Technical acceptance is
blocked by the required timing failures (no eligible unchanged retry), absence
of a captured stack for the observed native close crash, and still-held native
full-action/hardware validation. Further timing attribution or a captured native
failure must justify the next repair; no limit loosening is proposed.

Native/UI all-action acceptance and remaining timing failures remain open.
This checkpoint does not authorize a release or live adoption.

Open performance work is owned by the RC4 repair, with exit conditions of
unchanged-budget exact-source AOT enforcement plus faithful native full-action
timing acceptance. Revisit before candidate/release decisions: provider/event-loop
and refresh attribution, unavoidable versus repeated observations, cold startup,
the retained paired/absolute misses, and remaining input-to-presentation gaps.

The [follow-up identity/cost analysis](followup-identity-analysis.md) records the
next minimal representation repair, complete absolute/paired miss tables and
before/after narrow peer observations. The current close diagnostic instead
checks out original cb1ea0e and runs its unchanged startup harness without a
pre-attached debugger, matching the original package/native-library environment.
It captures a bounded core only after a fault and extracts stacks postmortem;
only harness-certified PIDs are admitted, and raw cores remain outside artifacts.
The original failure remains unwaived until identifying evidence supports a fix.

## Exact identity-repair enforcement

[CI40129495617](https://github.com/reddraggone9/tandemlog/actions/runs/40129495617)
tested `c213ea98fce5cf8d43eddd2ab4144a001907ed47`, calibration=false.
Windows and Android passed. Linux passed1500 units, tooling/native checks and
the ordinary release build, then failed normal WM_DELETE close with SIGSEGV.
The original startup result and every earlier failure remain retained.

The [full performance receipt](followup-identity-enforcing-result.json) binds
the archive/report hashes, unchanged limits, all failed samples/bounds and
available CPU/append observations. All three shapes passed correctness and
232-metric coverage, with zero retries. Task-history pairing passed; Food-history
pairing failed only firstDerived.mixed.undo maximum38.759ms versus33.4368ms.
There are39 absolute action/phase failures, including warm/cold startup and
checklist additions. This remains a failed gate. The hosted CPU changed from
AMD EPYC9V45 to Intel Xeon Platinum8573C; cross-run timing changes do not establish
a controlled improvement. Combined append awaits and CPU brackets overlap and
must not be subtracted as exact exclusive costs.

Inspection of the measured warm proof path found allocation of a whole JSON
string immediately before UTF-8 conversion. A narrow AOT component probe over
actual closed synthetic SQLite row inventories compares the original algorithm
with direct JsonUtf8Encoder conversion. Both retain identical SHA256 digests;
the full row inventory, ready IDs and consumed-witness comparison remain.
The candidate changes only encoding allocation. Full startup/action enforcement
and native acceptance remain separate; the component probe does not clear them.

## Ordering follow-up

The [next cost analysis](followup-order-analysis.md) preserves6a0acdd's full
failed enforcement (202 absolute/123 paired checks, zero retries), actual-CI
normal-close receipts, a qualified local syscall control and the next pure
ordering repair. A temporary membership Set removes repeated growing-List scans
without changing move/seed/fallback results or any storage/native guard.
The frozen old-order oracle, mixed-history differential controls and existing
checklist scenarios retain independent correctness/replay checks. All six
source-frozen checklist families pass; full units and exact CI remain separate.
No hosted tail failure or earlier SIGSEGV is waived by those narrow results.


## Food identity follow-up

[Analysis](followup-food-id-analysis.md), [sealed targeted comparisons](followup-food-id-probe.json),
[all-action local AOT including failures](followup-food-id-full-aot.json),
[1505-unit/analysis/format receipts](followup-food-id-local-checks.json), and
[bounded cold-scenario CPU sampling](followup-cold-cpu-sample.json) preserve
current evidence. Only the immutable Food ID string is retained per record; all
constructor/admission/freshness/transaction/durability checks remain. Local AOT
correctness passes every shape/232 metrics, but11 absolute and4 paired failures
remain under unchanged budgets. This is not hosted/native acceptance. The
[handoff](live-handoff-vex.md) records the pending exact-source CI and baseline
concurrency hold.


## SQL checkpoint representation follow-up

[Analysis](followup-owned-state-analysis.md), [codec samples](followup-owned-state-codec.json),
[complete local AOT failures](followup-owned-state-full-aot.json) and
[1508-unit/analysis/format receipts](followup-owned-state-local-checks.json)
record removal of seven self-generated Base64 roundtrips, preserving exact
bytes, bounds, immutable ownership and all native/admission/durability guards.
[Exacta71 CI](followup-food-id-required-ci-terminal.json) confirms203 native
Linux passes while retaining54 enforcing performance failures; it does not
include this later constructor repair. Availability memo/projection experiments
were [rejected with their evidence](followup-readiness-rejected-experiments.json).

2026-10-25 follow-up: [exact-source required CI](followup-owned-state-required-ci.json)
and [native Linux desktop demonstration proof](followup-owned-state-native-demo.json).
Performance remains failed; native CI pending at this snapshot.

Canonical quote follow-up: [component research](followup-canonical-quote-research.json),
[local checks](followup-canonical-quote-local-checks.json), [full AOT](followup-canonical-quote-full-aot.json)
and [retained hosted cost synthesis](followup-owned-state-cost-analysis.md).
All-action enforcement and native hardware acceptance remain pending.

Current e23 follow-up: [required CI failures](followup-canonical-quote-required-ci.json),
[exact-source normal closes](followup-canonical-quote-close.json), [Android plan](android-validation-plan-e23.md).
Instrumented syscall collection is isolated on diagnostics/rc4-io-20261025; no timing acceptance.
