# Focused Food tail investigation — 2026-10-26

Development diagnosis, **not performance qualification**. Vex accepted the explicit
cloud/local stop-write receipts at 07:39:13 UTC and independently verified the
clean takeover checkout and remote development branch at
`096f79b545645fce2aa095e92eb581558a727840`. Historical dirty work was preserved;
the stale local product checkout was not used. Runtime product is unchanged.

## Original failed samples

The original full-reference logs contain useful per-action counters:

| Action / growth shape | Wall | Durable append interval | Bracketed cgroup CPU | Quota throttling |
|---|---:|---:|---:|---:|
| Confirmed Food Save / Task history, sample 6 | 14.777 ms | 10.225 ms | 4.840 ms | 0 |
| Historical three-container details Undo / Food history, sample 5 | 15.915 ms | 0.578 ms | 6.025 ms | 0 |

The Save's other four measured append intervals are 0.395–0.448 ms. Its slow
sample's wall time outside that append interval is 4.552 ms. This localizes its
excess elapsed time to the durable-append API interval; it does **not** distinguish
fsync, filesystem scheduling, process descheduling or other work inside that API.
Do not weaken the durability barrier to meet a timing limit.

Undo's other append intervals are 0.487–0.525 ms: its long tail is elsewhere.
Cgroup CPU is a bracketed aggregate including threads/controller, not a CPU-time
partition of the action. Wall minus CPU is not a measured I/O-wait or GC duration.
Both failed actions have one physical append, two file reads, zero semantic Task
sorts, zero Task-row decodes and zero semantic-validation reruns. Exact receipt
confirmation uses the current Food admission index; the fallback linear scan is
not evidence that this run scanned all history.

## One focused diagnostic batch

Added [`food_tail_diagnostic.dart`](../../tool/performance/food_tail_diagnostic.dart).
It imports the existing benchmark's `food-historical` and
`converted-food-confirmed` scenarios unchanged, with existing cost hooks enabled.
It retains each family's setup/order, two warmups, five measured repetitions,
exact receipt/state assertions, fresh-profile replay and canonical-prefix checks.
The complete suite's earlier heap/process history is absent. No new fixture,
acceptance sample, qualification receipt, budget, retry allowance or production
behavior is introduced.

Pinned Dart 3.13.4/Flutter 3.47.5 and the original native/SQLite libraries were
verified against the original report's hashes. Product sources were copied
byte-for-byte to a new isolated lab. The initial compiler succeeded but its
output mode was 0600 under the private umask; launching it failed before any
workload. That receipt and empty workload log remain preserved. The same binary
was made owner-executable, with unchanged SHA-256, and the previously unstarted
batch ran once. No measured sample was discarded or replaced.

Execution: 07:42:45–07:43:00 UTC, three serial shapes, 14.078 seconds total.
Actual limits: 6 GiB, no swap, 200% CPU, 128 tasks; 180-second systemd hard bound,
45 seconds per shape, 10-second stop grace and control-group cleanup. Memory peak
266,907,648 bytes; swap peak, OOM events and quota throttling all zero. Unit exited
successfully; independent readback found MainPID 0, empty ControlGroup and no
nibbler processes.

All **six family replay/correctness/prefix checks** passed. All **420 action
intervals** (300 measured, 120 warmup) have complete, reconciled cost partitions.
These interval categories use overlap precedence, not causal async attribution.

| Shape | Confirmed Save median / maximum | Historical details-3 Undo median / maximum |
|---|---:|---:|
| Base | 4.807 / 7.280 ms | 5.502 / 5.709 ms |
| Task-history growth | 4.899 / 5.315 ms | 5.446 / 5.967 ms |
| Food-history growth | 5.255 / 6.197 ms | 6.402 / 6.860 ms |

The two original spikes did not recur. Target-action queue-wait intervals were
2–5 microseconds; there were no native-API or full semantic-validation spans.
The base Save's 7.280 ms sample includes 2.749 ms of SQLite API interval coverage;
that is a new diagnostic observation, not the cause of the original failure.
No broad history-scaling defect, specific GC cause or safe causal product fix has
been established. Do not call the reference qualified on these reduced runs.

## Outcome and next evidence

Original qualification remains **FAILED**: two paired-maximum misses, all
per-shape correctness and absolute checks passed, no eligible unchanged rerun.
The remaining useful diagnostic is individual durability-call and scheduler/GC
attribution, particularly outside Undo's append interval. Preserve fsync and exact
receipt semantics; only a meaningful candidate warrants a new full qualification.
No release, live-data adoption, dependency change or CI dispatch occurred here.

Raw originals, all focused traces, source pins, binary hash and both launch
receipts are retained privately on Farnsworth. The handoff/project checkpoint
records their paths. Formatting-only changes after execution are not a new
runtime validation claim.
