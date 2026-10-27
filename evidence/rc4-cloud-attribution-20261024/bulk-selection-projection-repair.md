# Bulk selection projection repair (development)

The fixed source-pinned Farnsworth diagnostic completed four fresh processes,
504 observations and 252 raw cost traces with no replacements. This is supplied
local-executor evidence, independently reviewed from private archive SHA-256
`85344011e9a7331806f9502955e7583b6936f50a7289bd14bfa60e56d9d54112`.
It used runtime034a57d plus the diagnostic-only patch, based on521ab0e.

| Cell | Bulk delete median ms | Maximum ms |
| --- | ---: | ---: |
| Small, observation off | 19.503 | 20.502 |
| Small, observation on | 19.372 | 20.418 |
| Large, observation on | 19.744 | 23.079 |
| Large, observation off | 20.176 | 21.617 |

These fixed-order, five-sample cells cannot estimate observer overhead by
subtraction or establish a rare-tail rate. The focused processes do not reproduce
the original full-suite heap trajectory. Lower maxima are consistent with a
variable tail; they do not explain or clear the retained33.909ms enforcing miss.
Both off/on cells use the same diagnostic-patched binary. No UI input or hardware
presentation latency was measured, and this diagnostic cannot qualify a release.

## Attribution without double counting

Both instrumented shapes made two live snapshot reads, each a representation
memo hit. Across the five retained samples per shape, inclusive medians were:

| Operation | Small ms | Large ms |
| --- | ---: | ---: |
| Both snapshot calls combined | 2.520 | 2.582 |
| Whole three-task selection | 2.734 | 2.782 |
| Selection SQL/result retrieval (inside selection) | 1.140 | 1.155 |
| Decode796 visible rows (inside selection) | 1.542 | 1.551 |
| Three command preparations combined | 1.799 | 1.794 |
| Incremental local semantic validation | 4.287 | 4.377 |
| Append plus durability barrier | 0.820 | 0.919 |

Parent/child intervals overlap; do not sum these rows with their contained SQL,
native, projection or transaction intervals. Medians of separate operations also
need not describe one common sample. The19.744ms large/on median sample had
selection2.785ms (query1.145ms, decode1.567ms), both snapshots2.536ms, command
preparation1.533ms, semantic validation4.008ms and append1.074ms. The existing
partition classified7.460ms as unclassified, including new `diag.*` spans.
Unioning **all** raw intervals left1.001ms uncovered wall time in that sample
(and0.808ms in the small/on median sample). This is interval coverage, not causal
CPU, GC, kernel service time or allocation accounting.

The large/on maximum23.079ms had snapshots4.468ms, selection3.731ms (query2.058ms,
decode1.619ms), preparations1.956ms, validation4.558ms and append0.680ms. The
observed slower sample therefore does not establish that the repeated Dart decode
caused either that tail or the original33.909ms sample.

## Narrow source change

`TaskStore._selection` previously called `rows`, decoding every visible Task/user
row before retaining the selected three. The snapshot memo holds a comparison
string; it is not a source of fresh selection maps. This candidate retains both
live snapshot checks and the complete queue/refresh/admission path, while a fresh
SQL query filters requested **logical JSON IDs** before Dart decoding. It reuses
the exact visibility join/predicates and global rank order, retains the Dart
kind/ID checks and cardinality errors, and uses one JSON-bound parameter to avoid
a SQL variable per requested ID. No selected map is reused from the snapshot memo.

The filtered path is conservative about decoder parity. Projection writers use
`jsonEncode(Map)` and the clean-close witness binds the typed cache rows; damaged
cache reuse rebuilds from canonical history. Nonetheless, the existing snapshot
pass strictly decodes **all** visible rows before selection. During an actual
snapshot representation miss it compares the already-generated Task-list encoding
with those exact original Task raw strings. Only an exact app-style encoding
allows logical-ID filtering. Duplicate labels, whitespace or other noncanonical
Task encodings use the original full Dart `rows` decoder. This proof is retained
only with the existing bounded snapshot memo, adds no cached row payload and
supplies no selection/freshness authority. Oversized/nonretained snapshots fall
back too. Memo hits retain the proof only after exact live raw/order equality.

Caller guards are documented as nonmutating. For compatibility with diagnostic
or erroneous callers that stage SQL row writes after the snapshot, the bulk path
checks the connection's `total_changes()` around a nonnull guard and uses the
original decoder if it changed. A false guard still throws staleness immediately.
No guard means no extra counter queries. This covers staged row mutations, not a
new contract permitting arbitrary schema replacement or store reentrancy.
Focused Dart tests reproduce strict JSON5 refusal before/after the guard for
selected **and unselected** rows, duplicate-label last-key selection and duplicate
logical-ID cardinality refusal, and stale-before-decode priority. The independent
601-case SQL model review is supporting normal-state evidence; these Dart tests
close its specific decoder-parity qualifications without weakening cache guards.

The query may still visit other SQL rows and adds a logical-ID predicate. Net
latency improvement is **not yet measured**; no speedup or gate acceptance is
claimed. No canonical formats/bytes, event ordering, semantic validation, receipt,
Undo, peer-change guard, tail cleanup, durability, native owner or budget changes
are intended. New regressions cover global order, atomic receipts/Undo/prefixes,
stale-before-invalid error ordering, live staged visibility/kind/position changes,
duplicate logical IDs, and large missing selections. Existing full validation
results are recorded separately; fresh exact-source hosted/native/reference
acceptance remains pending. No further performance batch or CI was dispatched.

The original0/504 runner failure, setup/control failures, enforcing qualification
failure and all latency/history-growth limits remain unchanged. See
[the active handoff](live-handoff-vex.md) and
[performance policy](../../design/performance-gate.md).

## Local development validation

The final decoder-parity refinement passed the full1,535-test Flutter suite
(6m40s),26focused selection/snapshot/cache-proof controls, Flutter analysis and
all400Dart format checks. Current-source native validation passed4Rust and107
frozen admission/worker contracts; repository tooling passed198tests. Linux
release compilation and native-library/payload ABI/notices verification passed
without launching the application. The native-contract suite's generated timing
JSON was retained separately and the historical tracked baseline restored.

Diagnostic-only rebased hooks are kept out of this product commit. Focused
controls exercise direct3-row selection counts, legacy full-decoder fallback,
exact receipt/Undo bytes and throwing observer callbacks. The preparation's
incomplete synthetic Task was refused by normal validation; its failed test log
is retained and the fixture corrected before package freeze. The completed
four-cell historical diagnostic remains the only timing evidence for this
repair; no candidate speedup is claimed.

Fresh exact-source hosted/native/reference acceptance remains separate and
pending; no new measurement, CI, foreground or release was launched by this
change. Existing failures and consumed requests remain unchanged.
