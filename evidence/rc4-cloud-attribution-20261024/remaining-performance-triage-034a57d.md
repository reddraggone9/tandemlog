# Remaining performance triage — product034a57d

Read-only review on2026-10-25. Full sample/resource extracts and source/report
hashes are in [the JSON receipt](remaining-performance-triage-034a57d.json).
No product edit, new timing run, CI retry or gate change was made for this review.

## What actually failed

[Exact CI40167598688](https://github.com/reddraggone9/tandemlog/actions/runs/40167598688)
is terminal: Linux/Windows/Android PASS, including1515units,174tools and203Linux
native workflows. Overall CI **FAILS performance**. All3synthetic history shapes,
232metrics each, passed correctness/prefix/replay. Zero retries. The driver raised
the timing failure before assigning its final `measurementCompleted` and
`allPinsMatch` fields; those fields remain absent, not inferred true. Independent
inspection matched all118source pins. Original failed evidence is preserved.

Five absolute failures are **maximum-only action misses**; every absolute median
and every startup metric passed this hosted run:

| Shape / action | Median / budget ms | Maximum / budget ms |
| --- | ---: | ---: |
| Base / Task Schedule | 10.095 /35 | 143.987 /40 |
| Base / converted Task Assignee | 11.488 /35 | 176.982 /45 |
| Base / converted Task Assignee Undo | 9.852 /40 | 46.142 /45 |
| Task-growth / confirmed imported Food details Save | 9.984 /15 | 29.243 /20 |
| Task-growth / confirmed imported Food details Undo | 7.306 /15 | 32.813 /20 |

Three paired metrics failed. These overlap two absolute failures; they are not
three additional independent user actions:

| Growth / action | Large median / paired bound ms | Large maximum / paired bound ms |
| --- | ---: | ---: |
| Task / confirmed Food details Save | **9.984 /9.3125** | **29.243 /12.7700** |
| Task / confirmed Food details Undo | 7.306 /9.7825 | **32.813 /13.3776** |
| Food / checklist-confirm completion | 35.850 /41.73375 | **60.819 /51.7138** |

Thus **one paired median** remains the strongest possible repeatable-work lead;
its repeatability across independent current-source runs is not yet established.
Base/Task-growth contain1325/2645physical records and997/2317Task effects, with
identical796Task rows and329Food containers. Food-growth retains those live rows
while increasing Food effects329→1649. This controls current state, not every
runtime allocation or cache/collector condition.

## Sample attribution and unresolved gaps

Times below are ms. CPU counters bracket the operation and include probe overhead
outside its action timer; append is an inclusive async provider interval. These
columns are **not an exclusive wall-time partition** and cannot be subtracted to
claim a precise scheduler, GC, fsync or SQLite service-time breakdown.

| Sample | Action wall | Bracketed cgroup CPU | Inclusive append |
| --- | ---: | ---: | ---: |
| Schedule base maximum | 143.987 | 21.374 | 125.369 |
| Assignee base maximum | 176.982 | 11.190 | 10.235 |
| Assignee Undo base maximum | 46.142 | 10.346 | 19.763 |
| Confirmed Food Save base median | 5.050 | 5.550 | 0.302 |
| Confirmed Food Save Task-growth median | 9.984 | 10.044 | 0.476 |
| Confirmed Food Save Task-growth maximum | 29.243 | 28.956 | 2.382 |
| Confirmed Food Undo Task-growth maximum | 32.813 | 28.778 | 1.755 |
| Checklist-confirm Food-growth maximum | 60.819 | 18.516 | 0.321 |

Schedule's slow append interval is the dominant observed wait; the counter does
not identify the responsible syscall. Assignee and checklist-confirm have large
elapsed/CPU discrepancies outside append. No sampled cgroup quota throttling is
reported; this does not exclude host scheduling, storage waits or other pauses.
Food's median/maximum CPU grows with elapsed time, so treating all misses as
fsync tails would be unsupported. Allocation/GC versus application work is still
unresolved without current action-scoped CPU/allocation evidence.

All five measured confirmed Food Save samples (ms, original order):

- Base:4.742,5.050,4.926,5.132,5.550.
- Task-growth:7.344,9.984,29.243,18.543,5.568.
- Food-growth:6.528,6.738,6.058,6.564,5.982.

Base and Task-growth median Food Save both append one record, read2files, decode
zero Task snapshot rows, run zero Task semantic validations and zero Task sorts.
Their bracketed I/O is nearly identical (rchar4875/4880;wchar6058/6058). This does
not prove constant allocation or absence of history-dependent CPU work.

Source review confirms the fully ready Food receipt confirmation is already an
indexed ID/hash lookup (`FoodStore.isAdmitted`/`FoodAdmission.confirmsReadyRecord`),
not a full Task-history scan. The fallback for incomplete admission is necessary.
`FoodUndoHistory.record` rechecks exact confirmation before registering an action;
capacity50 and receipt identity/hash guards remain necessary correctness checks.
The benchmark deliberately includes the same application confirmation/Undo
boundary, beyond backend-only Save; do not remove it to improve the measurement.

Prepared admission still copies immutable physical/effect/record collections in
`UnifiedHistory._prepareInProfileQueue` and `_confirmPreparedAction`. This is a
plausible allocation lead, but the retained samples do not attribute the missing
4.934ms median to those copies. Changing snapshot representation now would be
speculation and introduce ownership/iteration/retention obligations. Necessary
pre-reservation freshness, post-append exact-byte confirmation, peer-change
fallback, rejected-Save continued typing and owned-tail cleanup must stay.

## Environment comparison, with its limits

The immediately preceding enforcing CI40164354926 had179absolute failures
(13medians,179maxima) and105paired failures (12medians,103maxima). Independent
comparison with40167598688 proves **identical AOT executable**
`b462ea6d80c213e50190b59862e62ba4d446ed0764c6e2b398be27918ee2a2c9`,
all source/tool/dependency maps, original fixture/limit/binary bindings and resource
caps. The native-runner repair is outside this standalone AOT executable.

The hosted CPU changed EPYC9V74→EPYC9V45; kernel6.17.0-1022-azure and caps6GiB,
2CPU,no-swap,128pids match. This is strong execution-environment sensitivity
evidence, **not a measured code speedup or proof virtualization specifically
caused the failures**. It does not separate CPU, storage or scheduling causes.
Neither run qualifies for an unchanged retry under the existing noise policy.

The source-controlled cloud-local full AOT evidence at6e400f7 uses the same
application/storage source as034a57d. It has no action or paired failures, but
four startup maximum misses: base warm-cache27.980/25ms, cold-total940.157/935ms,
cold-history897.509/890ms; Task-growth warm-cache42.192/40ms. All its absolute
medians pass. Its Food Save base/Task-growth medians are6.890/7.326ms and maxima
7.699/10.806ms, so the latest hosted paired-median miss does not reproduce there.
However it uses16GiB/4CPU/unbounded swap, another kernel/CPU and differently built
native bytes. It is useful contrasting evidence, not a controlled gate result.

The separately supplied Farnsworth **e23** series0/0,0/1,0/0 versus hosted28/3
also supports a platform-dependence hypothesis, retaining its single growth
outlier and all infrastructure aborts. Cloud has not directly reviewed those raw
files. It predates UTF8guard/current source and does not fill the current-source
reference gap. The new [fixed three-observation034a57d protocol](reference-034a57d.md)
addresses that gap without gate substitution, budget changes or persistent runners.

## Retained startup profile

The improved [open-only CPU profile](followup-cold-start-cpu-profile.json) covers
21fresh-profile opens at**e23**,21404samples,21.468sample-weighted CPU seconds,
zero reported lost events. It excludes init/close/replay but includes control/
report overhead. It predates the UTF8guard repair and uses the cloud-local caps
and native build. It is neither a current exclusive wall-time partition nor a
visible-response measurement.

Dominant **overlapping inclusive** shares:

- History refresh72.3%; physical-record decode38.0% (UnifiedRecord.decode37.5%).
- Semantic-effect validation30.6%; Task full semantic validation27.2% and Task
  semantic replay26.2% overlap that work.
- Canonical-value construction20.2%, CurrentOperation.decode17.7%, LogEvent.decode
  16.9%, CurrentOperation encoding8.8% and contentHash9.7% overlap their callers.
- Text materialization10.8%, baseline validation10.5%; native text calls3.6%.

Leaf shares: SHA10.045%,UTF8buffer filling6.032%,canonical quoting4.920%, allocation
stub1.346%,malloc0.869%,SQLite VM0.804%. **27.719%leaf is unresolved**. SHA/UTF8/
quoting together account for about21%leaf CPU, but required hashing itself needs
UTF8 and canonical bytes; this is not a21%removable-work claim.

This prioritizes future decode/canonical-allocation investigation over a blind
SQL rewrite. Required canonical equality, digest/identity/chain checks, immutable
ownership and semantic validation are guarantees, not removable overhead. Current
startup is within hosted limits (cold-total medians633.089/914.888/935.200ms;
warm-total163.583/295.359/352.874ms for base/Task/Food-growth). A new startup
optimization would not directly repair the present action-only failures.

One possible later narrow experiment is reusing normalized CurrentOperation on
**privately proven immutable decoded LogEvent instances**. CurrentOperation's own
hash/encoding are already memoized, but public LogEvent data can be mutated and
its public canonicalRaw is not trusted authority. Global memoization or blindly
returning raw bytes would change behavior. The old profile also cannot tell how
much encoding is a necessary first computation. This is **not selected for a
product patch** without current call/allocation attribution and equivalence proof.

If that experiment becomes justified, propose its exact helper boundary before
editing and first test public caller mutation, frozen deep ownership, predecessor
overrides, error identity/order/messages, malformed Unicode, legacy/default
normalization, unknown/noncanonical fields, hash/identity tampering and frozen
serialized bytes. Then run domain/storage/native-owner regressions, full unit/
tool/analysis/format checks and source-sealed all-action/first-use/history-growth
AOT evidence. No speedup or guard removal is established by this review.

## Recommended next step and remaining acceptance

Prioritize **three predeclared current-source reference observations** with the
corrected local controller and fresh118/5390pins. Compare all samples and failure
counts; establish whether Food's paired median recurs before changing product.
If it recurs, use bounded current-source action-scoped CPU/allocation/GC attribution
to choose one concrete redundant-work repair; publish expected invariants/tests
before edits. If it does not, retain the failure/environment evidence and propose
any gate-host strategy separately for Lee's decision. No gate waiver is requested.

Current-source native203-test/normal-close/disposal passes and older e23 Android
emulator functional checks retain their original scope. Full-action physical
Windows input-to-presentation timing, current-source native/device gaps, fresh
candidate gates and live-cutover prerequisites remain open. The prior Windows
TaskOpen32/Save61/Undo58ms sample was framework-postframe-only and never all-action
acceptance. No cloud/software-rendered number establishes hardware presentation.

Documentation-only validator preparation passed8regressions; source118pins match
current bytes and034a57dGit objects. Its normalized5390inventory matches retained
hosted and cloud-local input maps apart from the explicitly reported2package
configs. Original enforcing-failure flags are correctly rejected as completed
diagnostic input. Synthetic regression flags are test data, never new benchmark
evidence. No measurement/process is active in cloud at this checkpoint.
