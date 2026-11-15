# RC120 purchase-import admission-key repair (diagnostic, not qualification)

Source under investigation: 6e65fe88bb535dbe2344d0589f6d36897399dada.
Original q23 remains immutable, failed and unsealed. It confirmed dense-food
purchase import 805.825/818.007 ms and own-Food-history growth failures.

## Attribution

Reduced-family AOT diagnostics reuse benchmark.agentCli, including its canonical
prefix, state, import and fresh replay assertions. The retained q23 synthetic
fixture was read only; a /tmp manifest changes only its now-relocated workspace
path. No production profile, household service or foreground device was touched.
Local host was not quiet-admitted/reference-capped; these are NOT gate samples,
and cannot explain every millisecond of the original whole-suite workload.

Temporary Stopwatch prints (removed from production source) measured:
- FoodStore._planPurchaseImport: only 0.1–0.4 ms; receipt matching is not the cause.
- AgentWorkspace.open: history dominates, not FoodStore opening or close.
- UnifiedHistory._restoreStore and admitFood: each planned commit opens two
  histories. Existing admission builds a fresh Food memo key on both opens,
  sorting all IDs, SHA256-hashing every raw effect, serializing the digest list
  as canonical JSON and SHA256-hashing that again. This grows with withdrawn
  own Food history even when current state is identical.
- key1.log: commit opens spent 18.389/18.137 ms constructing Food keys out of
  38.319/38.236 ms full Food admission; fixed1.log: 0.167/0.163 ms key construction
  out of 18.535/18.549 ms admission. Whole-action one-offs are noisy and are not
  an A/B acceptance comparison.

## Repair and invariants

Use an immutable process-local FoodAdmissionInput: manifest digest plus exact
ID/raw map. Hashing manifest/count selects a bucket only; equality checks all
IDs and raw bytes, independent of iteration order. At most four entries remain,
with the existing LRU behavior. Same-size changed payloads/IDs cannot reuse a
cached admission. This removes redundant whole-history canonical serialization,
per-effect SHA256 and sorting; it does not skip Food semantic validation.
Strings are referenced, not copied. The removed foodEffects map existed only
for digest construction. Canonical bytes, persistent format/layout, Undo,
readiness, pending-reference handling, full replay and controller budgets do
not change. No cache-generation bump: no persisted meaning changed.

The new direct regression covers order independence, equal-sized collisions,
manifest/ID/raw/removal changes and caller mutation. Existing history tests
cover incremental delivery, missing dependencies and full replay equivalence.

## Reproduction / follow-up

Compile tool/performance/purchase_import_diagnostic.dart with the pinned Dart.
Run with TANDEMLOG_TEXT_LIBRARY pinned to the candidate native library and
LD_PRELOAD set to the reviewed .dart_tool/lib/libsqlite3.so (standalone Dart
compile does not embed this package's native asset mapping). Output must be a
new absolute scratch root. The driver cannot create a qualification receipt.

Parent must independently review this patch, then run new exact-source CI and
reference qualification before any signing/publication. q23's failure cannot be
replaced by these reduced local diagnostics. If the gate still fails, continue
profiling history restore rather than retrying unchanged source or budgets.

## Test environment recovery

Initial Flutter invocation attempted redundant pub resolution and was stopped;
no dependency files changed. The first --no-pub invocation encountered loopback
WebSocket HTTP502 from inherited proxy routing and was stopped. Setting
NO_PROXY/no_proxy=127.0.0.1,localhost fixes the test transport (not app source).
The full loopback-correct suite's two startup-fixture cases need pinned Dart on
PATH for their Python subprocesses; their original errors are retained, and the
cases are rerun with the pinned SDK PATH after that suite settles. No performance
gate or action limit was changed by these test-runner environment corrections.

## Local correctness result

`flutter analyze --no-pub`: no issues. Full `flutter test --no-pub` completed
1926 passes and only the two SDK-PATH fixture-environment failures described
above. After supplying pinned Dart on PATH, both fixture cases plus the new
memo-key regression passed (3/3). Thus all 1928 tests passed across the full
suite and its environment-corrected targeted completion. This includes unit,
widget and workflow tests; no native foreground workflow was changed.
`dart format --output=none --set-exit-if-changed` and `git diff --check` passed.
No CI was dispatched and no gate was run.

## Fair interleaved comparison

After tests and analysis had stopped, four alternating A/B rounds per shape ran
on this host with only each diagnostic process pinned to CPUs0,1. Both AOT
binaries carried identical temporary phase/key instrumentation; `before` used
old digest keys and `after` used exact-map keys (then named privately; moving
the identical class to food_admission.dart makes the invariant directly testable).
There was no household quieting. This is CPU affinity, NOT the reference CPU
quota/quiet admission. `interleave.py`, binary hashes, all16 raw logs and
`interleaved-summary.json` retain order and results. Every run passed the
original family correctness/fresh-replay/prefix assertions.

Whole planned purchase import median across four diagnostic samples:
- dense-1: 244.962 → 228.9605 ms (6.5% reduction).
- dense-food: 462.676 → 388.644 ms (16.0% reduction).
- large-minus-small: 217.714 → 159.6835 ms (26.7% less history-growing cost).
Food key construction median across the whole family: dense-food20.556 →
0.1835 ms, dense-1 3.5335 → 0.0655 ms. Individual full-action values remain in
the JSON; no sample was dropped. These medians are diagnostic aggregation only;
they do not replace the one-sample reference gate, loosen any bound or show
that the exact-source full-suite qualification will pass.

Large raw logs are losslessly retained as `.log.gz` to keep source review compact.
