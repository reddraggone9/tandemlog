# Hardware multipliers and hosted timing — retained evidence

Lee approved the clarified [ADR0033](../../design/decisions/0033-controlled-reference-performance.md):
no hardware multipliers;unchanged absolute and history-growth limits qualify on
controlled Farnsworth;hosted correctness remains mandatory and timing advisory.
This explains that choice without rerunning a benchmark or rewriting old results.
[Full descriptive ratios/source hashes](hosted-normalization-analysis.json).

## A constant scale does not explain the tails

Hosted runs40164354926and40167598688 used the **same AOT executable,source,
dependencies,tool/fixture/limit bindings and caps**,but different CPU/execution
environments. Across567ordinary metric/shape pairs whose newer median is at least
1ms (excluding especially unstable tiny denominators):

| Older/newer ratio | Median ratio | 5th–95th percentile | Full range |
| --- | ---: | ---: | ---: |
| Per-case median time | 1.281 | 1.147–1.586 | 0.655–15.418 |
| Per-case maximum time | 1.431 | 1.089–18.739 | 0.092–70.378 |

These are descriptive quantiles over heterogeneous cases,not independent-trial
confidence intervals.24startup pairs have median-ratio center1.396 and5th–95th
range1.252–2.276,also different from ordinary actions. One scalar cannot represent
CPU,allocation,append/fsync,scheduling,startup and rendering equally.

Examples:base confirmed Food Save changes6.758→5.050ms median but159.023→5.550ms
maximum;Task-growth confirmed Food Save reverses7.260→9.984ms median and8.633→29.243ms
maximum. Base Schedule's maximum goes13.244→143.987ms despite nearly unchanged
median behavior. Historical API-only contents has maximum413.820→5.880ms. No code
changed in this executable. A stable hardware factor cannot explain these delays.

The older e23 supplied Farnsworth comparison's four baseline hosted/local median
ratios are roughly1.79–2.04 (TitleSave≈1.91,Undo≈1.90,completion≈2.04,confirmedFoodSave
≈1.79–1.85). A rough2×description may help discussion,but four supplied medians
are not a cross-platform calibration or tail model. Cloud has not reviewed those
raw local files. Current034a reference observations were reported0/0three times,
without reporting all raw local ratios to cloud;do not invent them.

A multiplier fitted to the candidate's own slowdown could hide a uniform code
regression. An independent CPU calibration still would not establish the same
scale for storage barriers,GC or native presentation. Keep raw milliseconds and
fixed limits on the registered reference class;no multiplied pass/fail values.

## Two different comparisons

Same-source **history-growth pairs** compare small/large histories with identical
current state. They reduce some common speed-scale effects but not independent
tail noise:the older hosted run had57Task-growth/48Food-growth failed pairs
(6median misses in each);the newer run had2/1 (1/0median misses). The older local
e23series retained one paired maximum20.643ms versus19.1176ms despite two clean
observations. The current local034aseries was reported clean in all3observations.

These are **not baseline-versus-candidate code comparisons**. A uniformly2×slower
candidate could preserve every same-source history ratio. Absolute limits remain
necessary;any future code baseline/candidate comparison needs independently bound
revisions and comparable host/fixture/lifetime conditions. No new comparison is
performed or silently substituted for either existing growth pair.

## Keep hosted timing advisory initially

The current hosted performance job took9m50s wall time;its three action processes
accounted for497.727s,with3.972s compile and7.406s fixture generation. Removing
timing assertions alone does not remove those production actions,replays and
integrity checks. Instrumentation-only overhead was not isolated,so no saving is
claimed. These are observed costs,not runner-credit or future-duration estimates.

Keeping raw timings while retaining that harness is useful:it exposes large
environment shifts and unexpected operation-specific behavior without repeatedly
chasing green. Use one advisory pass,no noise rerun;fail structural/correctness/
binding/completeness faults. If cost later justifies less timing collection,the
full harness's replay/integrity/source/fixture/coverage checks must remain
mandatory. Deleting the harness because ordinary unit/build jobs pass would lose
distinct realistic-workflow coverage. No scheduling/coverage reduction is part
of this change.
