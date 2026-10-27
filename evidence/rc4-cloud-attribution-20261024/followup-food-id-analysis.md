# Food identity allocation follow-up

The previous enforcing CI40139838647 retains10 absolute maxima and9 paired
failures; all absolute medians fit. The remaining Food-history pair includes
peer-Food admission median10.379ms against9.5475ms and restore-one
median10.668ms against9.71875ms. Neither failure is waived.

`FoodRecord.id` repeatedly interpolated immutable writer and sequence fields.
Unified history maps and Food readiness/Undo checks read the same decoded records
repeatedly. Matching the existing Task event-ID cache, the candidate retains one
derived ID string on each existing record. Both constructors, exact-byte and
reference checks, the cached-envelope identity check, publication, native
ownership, queue, transaction and durable append/barrier paths are unchanged.
There is no global cache or new persisted authority. Retention follows the
already bounded decoded records and their owner lifetime.

The existing peer scenario was run before/after on the same sealed synthetic
fixtures, with2 warmups and5 measured repetitions. Replay and original prefixes
passed in all shapes. Peer-Food medians were6.267/10.510/10.325ms before and
5.821/7.883/8.294ms after. A wider existing Food-command comparison also passes
correctness but has mixed timings, including a worse restore-one observation;
it does not show all Food latency resolved. Full samples and source/log seals
are retained in `followup-food-id-probe.json`.

The focused97-test set passes: Food records/store/Undo, decoded-cache authority
and unified-history corruption/transaction guards. Full current-source AOT measurement completes all3 shapes/232 metrics, fresh
replay and exact source seals, with0 retries. It retains11 absolute failures and4
paired failures: startup misses in every shape, and Food-growth tails for
converted title+Notes Save, checklist deletion and cardinality500 paired Food
details Save. All ordinary-action medians fit; only startup medians fail.
Peer-Food and restore-one fit the unchanged paired comparisons in this finite
local run. The full1505-unit suite passes in6m25s, final analysis is clean and formatting
checks395 files with0 changes. Exact-source hosted enforcement remains pending. Local development
measurements cannot satisfy the required6GiB/2CPU/no-swap/pids128 hosted gate.
All limits, registered cases, first-use/history-growth checks and retry rules
remain unchanged. Native Windows/Android and hardware presentation acceptance
remain separate; this source change makes no new UI acceptance claim.


A bounded199Hz user-CPU profile of the existing cold-startup scenario captures
zero lost samples and symbolizes Dart frames. The scenario includes fixture
initialization, seven cold opens, intervening cache seals and final replay.
Synchronous sampled stacks include UnifiedHistory refresh (~50.3%) and
TaskStore close/cache sealing (~18.7%); async ancestry is partly unresolved.
SHA-256 is17.3% leaf samples, UTF-8 encoding6.1%, and canonical string quoting3.4%.
These are sample shares, not exclusive action wall partitions. Strict decoding
and integrity hashing are required; this profile authorizes no skipped checks.
Raw perf data stays in scratch; only sanitized symbols/statistics may enter Git.
