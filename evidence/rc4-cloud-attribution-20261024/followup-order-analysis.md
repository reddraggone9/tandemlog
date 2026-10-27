# Ordering follow-up and retained hosted tails

Commit6a0acdd's enforcing run40134281681 passes correctness and all232 metrics
on every shape, but fails202 absolute checks and123 paired checks (61 Task,
62 Food), with zero eligible retries. [Complete failed samples/bounds](followup-proof-enforcing-result.json).
The host is AMD EPYC9V74, differing from the preceding Intel run. These whole-run
differences do not establish a controlled speedup or regression.

Warm total medians are225.121/378.885/464.693ms and proof medians
48.256/72.763/58.263ms across base/Task/Food growth. All those medians fit their
limits; the Task-growth warm maximum still fails. Cold totals retain misses.
Most ordinary failures are maxima, including a read-only editor open216.208ms
with4.762ms bracketed CPU and a derived metadata append interval385.644ms.
CPU brackets and combined append await are overlapping observations, not exact
exclusive partitions. Aggregate external pressure does not prove the cause of
every slow sample. Limits and the noise policy are unchanged.

The [required Linux startup receipt](followup-required-ci-clean-close.json)
records fresh2077ms/normal close178.425ms and warm262ms/normal close79.319ms,
with clean witness reuse. No core was generated. This successful execution
does not identify or clear the earlier intermittent SIGSEGV. No lifetime
workaround or SDK upgrade is inferred from clean closes.

## A justified CPU repair

Checklist creation rebuilds the global disposable order. The actual diagnostic
action records one production rebuild on all shapes,799 profile position inserts,
and no full semantic-readiness fallback. The pure order algorithm scans the
growing ordered List for membership on each creation and fallback ID. This is
avoidable quadratic membership work; SQL/freshness/native checks are separate.

The repair keeps a temporary Set of placed IDs. IDs remain placed while a move
temporarily removes/reinserts their List position. All move ordering, deferred
resolution, first successor seed and final fallback order are unchanged. The
Set lasts only for that projection call and adds O(N) references; it grants no
admission, freshness or commit authority and retains no global cache.

The [alternating component probe and operation evidence](followup-order-attribution.json)
retain the exact scratch source, hashes and original measurements. At800 IDs,
the component median falls from about2.6ms to0.45ms; at1600 from9.1ms to0.91ms;
at3200 from34.4ms to1.81ms. These are component timings, not action acceptance.
A10,000-case scratch differential control matches the original algorithm.
Committed regressions retain a frozen original oracle and exercise1000 mixed
histories plus an explicit deferred-move/successor/fallback example.

The [source-frozen checklist recheck](followup-order-checklist-validation.json)
uses the existing converted and ordinary checklist scenarios, unchanged seven
repetitions, three sealed shapes and full replay/prefix assertions. All six
families pass correctness. Five measured add samples per family range31.538ms
to50.045ms locally. This narrow run does not replace exact-source enforcement
or native/hardware input-to-presentation acceptance.

## Remaining attribution boundary

The [local syscall control](followup-local-syscall-trace.json) traces only fsync
and fdatasync, never SQL or write buffers. All three diagnostic actions pass
correctness/replay. Across123 calls, the slowest observed syscall wall interval
is4.954ms (SQLite WAL); the slowest canonical-log interval is1.794ms. Syscall
wall time includes tracing and scheduling and is not pure disk service time.
This did not reproduce the hosted hundred-millisecond tails. Their native-I/O
versus scheduling cause remains unresolved; no unavoidable product tradeoff
has been established and no durability or timing limit has been loosened.

Full local1504 units pass in6m31s,21 focused cases and171 tools pass; final
analysis is clean and formatting394 files changes none. [Check hashes](followup-order-local-checks.json).
Fresh exact-source CI remains required.
