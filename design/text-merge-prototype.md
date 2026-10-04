# Test-first isolated Yrs prototype — 2026-10-04

Status: Lee authorized a bounded cross-platform investigation, not production
adoption. No application dependency, event meaning, durable history, schema,
signing identity or checklist changes are part of this experiment. The isolated
working package was first created outside the repository, then mirrored under
[experiments/yrs-spike](../experiments/yrs-spike/README.md) to obtain repeatable
hosted native Windows/Linux checks. It is a separate crate with a separate
lockfile; no production app imports or packages it. Its manually dispatched
read-only workflow has no signing secrets or publication capability.

The acceptance tests were frozen before implementation in standalone commit
`5727ff4725e9ed740cc89ae68ef2f3c233aaf895`. The 34 executable cases failed with
34 missing-library errors, establishing the recorded red baseline. Test SHA256
`436c9ce892e61f85bd9af3eacf1b4ff95cddf389e88253e439c1153f4c978c79`;
additional-gate JSON SHA256
`ca8e98d43691820308f3327104c171da29e56723d6c31253a92008c79731e524`.
Assertions must not be weakened to make an engine pass. Any necessary test
clarification is a separate explained revision.

| Cases | Required behavior | Current result |
|---|---|---|
| C01–C05 | One historical seed; Save/Cancel; captured-baseline changes preserve concurrent inserts/deletes | Pass, native Linux release bridge |
| C06–C13 | Offline concurrency, same-location edits, duplicates, all arrival permutations, delayed causal dependencies and checkpoint recovery | Pass |
| C14–C15 | Independent fields and recurring-successor text | Pass for correctly routed fields; misrouting not safe yet |
| C16–C21 | UTF-16, emoji/surrogate boundaries, combining/ZWJ/Markdown, composition commit/cancel and sticky selection | Pass, engine/bridge scope only |
| C22–C25 | Selective Undo/Redo as appended compensation preserving remote work | Pass, session Undo only |
| C26–C30 | Malformed/oversized updates, invalid offsets/base64, active actor collision, text limits, atomic rejection | Pass for sampled cases; full malicious update admission remains blocked |
| C31–C34 | Exact JSON update bytes, checkpoint/tail equivalence, native memory cycles and measured edit/restore/storage cost | Pass, synthetic scope |
| O01–O04 | Source-bound one-shot Save, reject remote draft import, failure retains draft/prior Undo | Three failures reproduced before fixes; four pass after fixes |
| A01–A03 | Actual frozen-v3 TaskStore replay; old-reader rejection; explicit old scalar writer admission policy | Nine production compatibility tests pass; old scalar admission remains undecided |
| A04 | Pending structs retained through full checkpoint, excluded by ordinary diff | Pass: full restore yields xAB; diff restore yields xA |
| A05 | Wrong-root/embed/type admission | **Fail**: foreign root/text accepted invisibly into state; seed conflict also reproduced |
| A06 | Fresh-process/truncated/checkpoint-hash recovery | Not run for a new text protocol; existing v3 app checks remain unchanged |
| N01 | Linux/Dart native ABI | Pass, actual Dart3.13.4 native FFI |
| N02 | Android two-ABI packaging/runtime | ARM64/x86_64 SO cross-builds pass; runtime/Flutter packaging not run |
| N03 | Windows native ABI/runtime | Pass: 38 Python cases and actual Dart FFI on hosted Windows2022 |
| N04 | Actual Flutter IME/editor integration | Not run; engine composition flags do not prove UI behavior |
| P01–P02 | Release library load/checkpoint, deletion churn and document/RSS cost | Bounded Linux measurements pass; app cold start/unbounded-state acceptance not run |

Engine-level composition/Save tests do not prove native Flutter IME behavior.
Cross-compilation does not prove Windows/Android runtime acceptance. A converged
string does not prove safe admission, checkpoint completeness or old-client
compatibility. Report each gate as pass, fail or not run with its exact evidence.

## Completed bounded result

[Hosted probe37213304140](https://github.com/reddraggone9/tandemlog/actions/runs/37213304140)
passes at source `29827ebadc97eed96d3e0f542c2f579cb7106b2e`: native Linux and
Windows each pass38 frozen/review-added cases and actual Dart3.13.4 FFI. Android
libraries cross-build with the official NDK28.2/API24. Downloaded archive API
hashes/CRC verify. The initial hosted Android setup failed because `sdkmanager`
was absent from PATH; explicitly locating the existing official command fixed
it. No runtime or application-package claim follows from those SO builds.

The sampled malformed-input subprocess rejects1003 inputs without state change,
within512MiB/10CPU-second bounds. This is sampling, not a native-parser security
proof. Foreign-root data is reproduced as retained invisibly in full state;
conflicting historical seed IDs produce mixed text instead of rejection. Those
are **adapter admission failures**, not claims that Yrs rejects unsupported app
semantics on the caller's behalf. The prototype remains unsuitable for real data.

Local Linux release measurement, with OS page caches unflushed: 2000 one-character
edits take23.41ms including Python/JSON/FFI; in-memory checkpoint restore takes
0.040ms. Raw updates total23743B, engine checkpoint2026B. These exclude canonical
envelopes, disk/SQLite, Flutter startup and user input latency. Five fresh-process
library loads take0.331–0.445ms; first document creation0.192–0.225ms. Creating2000
synthetic fields takes51.83ms and increases process peak RSS from16680 to22740KiB;
2500 replacement edits take20.94ms and restore from a3433B JSON checkpoint.
Hosted libraries are926544B Linux,864256B Windows,842784B ARM64 Android and953048B
x86_64 Android, before application packaging.

Recommendation: continue only the narrow text adapter after field/seed/actor
identity, strict ingress, separate state budgets, legacy-scalar admission and
real Android/editor tests are resolved. Keep ordinary tags, relative-anchor
ordering, validated schedules and domain commands. Y.Map replacement does not
supply observed-remove set, additive counter or coupled-schedule invariants;
Y.Array insertion/deletion does not by itself enforce logical item uniqueness
through concurrent moves. Checklist title/notes could reuse a hardened text
adapter; checklist identity/deletion/recurrence should remain domain rules.

Evaluate Yrs [0.28.0 API](https://docs.rs/yrs/0.28.0/yrs/) with pinned crate bytes
and reviewed build hooks. It provides a text CRDT, state/update encodings,
sticky indices and selective Undo; these features still require an application
boundary. The experiment cannot silently replace the approved wall-clock causal
event order or drop original operations when undoing a causal update.

Before adoption, decide legacy scalar admission and a versioned reader boundary,
client identity allocation, resource limits/native parser isolation, restartable
Undo and materialized checkpoints. Consider other Yrs shared types only as
recommendations; no generic domain/store rewrite is authorized.
