# SQL checkpoint representation repair

The actual protected-successor Undo profile includes Base64 decoding and
checkpoint readiness. At seven Task/text-cache SQL read sites, already-binary
state was encoded, passed to NativeTextState.parse, decoded and encoded again
to prove canonical Base64. This is representation work; native readiness, actor,
context, byte/hash and transactional checks remain necessary.

NativeTextState.fromBytes checks the same hard boundary before allocating, owns
an immutable copy and generates canonical Base64 once. The original string
parser remains unchanged for untrusted encoded input. Empty and final-block
over-limit failures retain their original exception classes/messages. SQL/native
limits, pending-state checks, ownership, live observations, durability, queued
ordering, rejected-Save continued typing and peer/tail recovery retain their
guards. No native ABI, persisted format, dependency, signing or budget changes.

A same-binary AOT comparison alternates original/new order, with two warmups and
five measured batches. Checksums and source seals match.

| Input bytes | Original512-construction median ms | Owned512-construction median ms |
|---|---:|---:|
| 256 | 1.707 | 0.597 |
| 1024 | 6.673 | 2.302 |
| 16384 | 110.281 | 37.988 |

This is approximately2.9x faster representation work, not a whole-action or UI
speed claim. [Complete samples](followup-owned-state-codec.json).

Full1508 units pass6m38s, including original-parser byte equality through8MiB,
error boundaries, immutable input/output ownership, actual native pending and
limit checks, history and cache recovery. Analysis is clean;395 files format
with0 changes. The first focused command named a nonexistent cache test; its
45 loaded tests passed, and the actual cache inheritance module passed separately.
The failed command and corrected result are retained in the
[local checks](followup-owned-state-local-checks.json).

[Full local AOT](followup-owned-state-full-aot.json) passes correctness/replay/
canonical prefixes/source seals for all3 shapes and232 metrics each,0 retries.
It retains10 absolute and9 paired failures and is measure-only on a different
resource configuration. It does not satisfy enforcing or hardware UI acceptance.
Fresh exact-source CI remains required for this repair.

The earlier exacta71 CI40143666264 passes Linux/Windows/Android, including all203
native Linux cases and the corrected Session Undo/Discard flow. It fails54
absolute performance checks (42 median misses); both paired comparisons pass.
Its EPYC7763 host differs from the baseline9V45, so no controlled code speed
comparison is claimed. The old intermittent native-close SIGSEGV remains
unwaived despite two clean closes and no core.
[Terminal receipt](followup-food-id-required-ci-terminal.json).

The availability memo and no-retention projection variants had mixed matched
timings. Neither was retained in product source. Their full failed AOT and
[comparison evidence](followup-readiness-rejected-experiments.json), plus the
[unaccepted source patch](rejected-readiness-memo.patch), remain available; they
are not accepted alternatives or instructions to reapply the cache.
