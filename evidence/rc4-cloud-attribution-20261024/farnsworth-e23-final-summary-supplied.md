# Farnsworth comparison — supplied final summary

This records the parent's final local-executor summary of
`FINAL-COMPARISON-REVIEW.md` on Farnsworth. **Cloud has not read the raw local
artifacts or independently audited those receipts.** Structured supplied values
are retained [here](farnsworth-e23-final-summary-supplied.json). This is qualified
application/storage evidence, not visible UI or release acceptance.

Product remains `e23f00f9640ee5724f4b646d37bc352ca58dc6f1`. The executor reports
117 source/tool matches and5389 compiled pins examined, with only2 environment
package-configuration differences. Their contents were not supplied to cloud.
No source/harness, performance threshold, CI or persistent-runner change follows.

| Observation | Absolute failures | Paired-growth failures | Completion |
|---|---:|---:|---|
| Hosted exact e23 |28|3|All3 shapes/232 correctness metrics pass; enforcing result failed.|
| Farnsworth1 |0|0|All3 shapes/232 metrics and source/tool/fixture/resource/correctness valid, as reported.|
| Farnsworth2 |0|1|Same reported validation; one maximum failure retained.|
| Farnsworth3 |—|—|Aborted during compilation after2.038s; zero timed samples.|

At the supplied summary snapshot there had been no fourth run, and all workload/manager
units were stopped, as reported. A later parent direction separately authorizes
**one fresh bounded replacement attempt**, after external controller correction
and tests, to obtain the missing third completed measurement. The local executor
owns it; e23 and all completed runs/outliers stay unchanged. This is authorization,
not a new measured result; cloud has not executed the replacement.
The comparison produced **two completed timing runs**, not three passes.

The remaining local failure is `copiedChecklist.metadata.complete`, Task-history
growth. Small samples9.662,9.778,10.084,9.719,9.708ms; large samples
10.521,20.643,11.156,10.658,10.181ms. Its unchanged maximum bound is
1.4×10.084+5=19.1176ms. The20.643ms sample remains a failure. Reported bracketed
CPU9.639ms, append0.858ms and zero quota throttle do not identify the cause:
these intervals are nonexclusive and cannot be subtracted as a causal partition.

| Reported baseline median, ms | Hosted | Local1 | Local2 |
|---|---:|---:|---:|
| Title Save |28.503|14.863|14.918|
| Undo |27.049|14.207|14.214|
| Completion |18.648|9.138|9.168|
| Confirmed Food Save |8.878|4.807|4.960|

These support platform-dependent performance and close agreement between the two
local runs for these operations. They do not isolate virtualization from CPU,
filesystem/storage, scheduling or other environment differences, and do not
waive the hosted result or the retained local paired failure.

The local installed-ZFS review reports that MemAvailable excludes ARC data, with
16.71GiB explicitly evictable. Lee corrected the accounting; the external
controller alone adopted a conservative ARC-aware preflight: raw≥2GiB and
raw+min(evictableR/2,6GiB)≥8GiB, using only eligible reclaimable ARC constrained by
ARCmin and stable snapshots. Runtime6GiB/no-swap/200%CPU/128-task bounds and all
performance budgets remained unchanged. Cloud has not inspected that controller.

The corrected preflight allowed the planned third attempt, then its global-swap
guard stopped compilation on54.17MiB allocation growth. Workload swap/OOM were0
and disk swapout did not increase. This records a controller abort, not measured
application latency, a functional failure, proven disk swapping or a memory leak.

Existing hosted syscall evidence remains partial and instrumented. It does not
tie the original slow samples or this local outlier to an exclusive fsync,
metadata, scheduler or CPU cause. No gate or budget change follows. The later single replacement-attempt
authorization above supersedes the earlier no-fourth instruction; all historical
aborts remain retained. Android's isolated helper correction is still pending;
no native Android cases are promoted to a pass by these results.

Next bounded work is only the [proposed UTF8 size-guard review](utf8-size-guard-proposal.md).
Product source remains pinned while that proposal is assessed.
