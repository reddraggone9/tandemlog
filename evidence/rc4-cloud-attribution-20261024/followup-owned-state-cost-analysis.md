# Exact5dc enforcing failure costs

Run40148192820, calibration=false, AMD EPYC9V74,6GiB/2CPU/no-swap/pids128.
All three shapes/232 metrics pass correctness.60 absolute failures include only
2 median misses;45 paired failures include2 median misses.0 retries; not accepted.
The priora71 host was EPYC7763, so these are not controlled before/after timings.
[Full summaries](followup-owned-state-required-ci.json) retain all five samples.
[Matched failure counters](followup-owned-state-failure-costs.json) retain the
same uninstrumented action samples and their original log hashes.

| Same-run observation | Action wall ms | Append API wall ms | Bracketed cgroup CPU ms |
|---|---:|---:|---:|
| Food-growth Add1 sample2 |7.276|0.345|7.978|
| Food-growth Add1 sample3 |154.097|144.235|19.002|
| Food-growth Add1 sample4 |79.688|0.389|7.323|
| Food-growth Add1 sample5 |7.632|0.477|7.514|
| Food-growth Add1 sample6 |43.973|37.064|7.603|
| Task-growth title Save maximum |106.717|88.893|18.709|
| Base editor open/Cancel maximum |18.268|0|6.584|

These samples do not decode any Task snapshot rows or run Task sorting. Food
performs2 fresh reads and1 own append, with no Task semantic validation. The
editor sample performs no read/append/semantic validation; it still writes its
existing disposable editor state. No cgroup throttling is reported in these
brackets. This identifies append-contained and outside-append delays; it does
not identify kernel service time or prove an upstream cause. CPU brackets include
probe overhead and all benchmark-service threads; multicore CPU can exceed wall.
Append includes directory/stream work, asynchronous scheduling and barriers.
Do not subtract/add these inclusive values as mutually exclusive CPU/I/O costs.

The Food median43.973ms exceeds15ms; the other median miss is Task-growth
startup.warm.cacheRestore30.378ms/cap30. Maximum-only misses and paired failures
remain blocking even where medians fit. Original external-pressure observations
are retained, but do not establish that every slow sample was noise and do not
make another unchanged run eligible.

The small canonical quoting candidate removes demonstrated literal-buffer
allocation with exact validation/bytes retained. Its9%/21% component microprobe
cannot explain or guarantee removal of these asynchronous tails. Full current
local validation and fresh exact-source CI are required; no durability, native
pending-state, freshness, queue/transaction or peer/tail guard is weakened.
