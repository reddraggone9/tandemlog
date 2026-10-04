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
| C26–C30 | Malformed/oversized updates, invalid offsets/base64, active actor collision, text limits, atomic rejection | Pass for sampled cases; sampled malformed updates rejected; pinned plain-text admission added below |
| C31–C34 | Exact JSON update bytes, checkpoint/tail equivalence, native memory cycles and measured edit/restore/storage cost | Pass, synthetic scope |
| O01–O04 | Source-bound one-shot Save, reject remote draft import, failure retains draft/prior Undo | Three failures reproduced before fixes; four pass after fixes |
| A01–A03 | Actual frozen-v3 TaskStore replay; old-reader rejection; explicit old scalar writer admission policy | Nine production compatibility tests pass; late legacy loser policy approved; activation/bootstrap implementation remains untested |
| A04 | Pending structs retained through full checkpoint, excluded by ordinary diff | Pass: full restore yields xAB; diff restore yields xA |
| R01–R14 / A05 | Root/type/seed/actor admission, hidden/pending content, startup/restore and trailing bytes | 13 failures reproduced before hardening; all14 pass afterward on native hosted Linux/Windows |
| A06 | Fresh-process/truncated/checkpoint-hash recovery | Not run for a new text protocol; existing v3 app checks remain unchanged |
| N01 | Linux/Dart native ABI | Pass, actual Dart3.13.4 native FFI |
| N02 | Android two-ABI packaging/runtime | Synthetic Flutter APK packages both verified native libraries; actual Android runtime pending |
| N03 | Windows native ABI/runtime | Hardened revision52 and Dart FFI pass on actual hosted Windows2022 |
| N04 | Actual Flutter IME/editor integration | 10 session/widget cases and native Linux integration pass; composition injected, real Android OS-IME pending |
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
semantics on the caller's behalf. These historical failures are retained as evidence; the scoped hardening below addresses them. The prototype remains unsuitable for real data until the remaining adoption gates pass.

Local Linux release measurement, with OS page caches unflushed: 2000 one-character
edits take23.41ms including Python/JSON/FFI; in-memory checkpoint restore takes
0.040ms. Raw updates total23743B, engine checkpoint2026B. These exclude canonical
envelopes, disk/SQLite, Flutter startup and user input latency. Five fresh-process
library loads take0.331–0.445ms; first document creation0.192–0.225ms. Creating2000
synthetic fields takes51.83ms and increases process peak RSS from16680 to22740KiB;
2500 replacement edits take20.94ms and restore from a3433B JSON checkpoint.
Hosted libraries are926544B Linux,864256B Windows,842784B ARM64 Android and953048B
x86_64 Android, before application packaging.

Recommendation: continue only the narrow text adapter after durable field/actor
identity, separate state budgets, approved legacy-scalar loser behavior, shared activation bootstrap and
real Android/editor tests are validated. Keep ordinary tags, relative-anchor
ordering, validated schedules and domain commands. Y.Map replacement does not
supply observed-remove set, additive counter or coupled-schedule invariants;
Y.Array insertion/deletion does not by itself enforce logical item uniqueness
through concurrent moves. Checklist title/notes could reuse a hardened text
adapter; checklist identity/deletion/recurrence should remain domain rules.

## Admission hardening (isolated, 2026-10-04)

Fourteen new regressions were recorded before source changes in standalone
commit `cac56d3` at16:15:02UTC, SHA256
`b2656efe7418de7f873749fea4169a456ac7d384763c08b4ed6b055b1a4b8fed`.
Thirteen failed; the duplicate-full-state case already passed. Original34 and
ownership4 assertions/hashes remain unchanged. All52 pass on the hardened local
Linux release library and native hosted Windows/Linux release libraries at
`5470384080f56e03a209f991af6745a941d3b559`,
[run37216546987](https://github.com/reddraggone9/tandemlog/actions/runs/37216546987).
Actual Dart FFI passes on each OS. Official Android ARM64/x86_64 cross-builds
also pass; downloaded ZIP API hashes/CRC and all four native library hashes
verify. Additional gates:8 pass,0 fail,4 not run (A03/A06/N02/N04).
No application source changes.

The adapter uses Yrs's pinned V1 primitive decoder to inspect every incoming
struct before integration, including pending/deleted content. It permits only
unformatted string items rooted in `text`, causal skips and bounded delete
ranges. It rejects foreign roots, nested ID parents, map slots, embeds, format,
shared types, erased/GC structs, reserved flags and trailing bytes. It checks
normalized UTF-16 identity/origins for overlapping actor/clock spans and forbids
extending the reserved historical seed frontier after initialization. New,
restore and Save/import share that admission boundary; rejected inputs leave
committed state unchanged. Integration/order/Undo remain owned by Yrs.

`skip_gc=true` retains original deleted strings for identity comparisons after
checkpoint restore. This is a deliberate bounded prototype cost, not an adopted
compaction policy; old experimental checkpoints with erased identities reject
explicitly. A production field/document-bound envelope, durable actor allocation,
separate visible/update/history budgets, malicious-native-parser isolation,
legacy scalar policy and actual Android/Flutter editor coverage remain open.
Same-seed updates routed to the wrong independent field are not prevented by
this wire allow-list. No durable v3 data is reinterpreted or modified.

The hardened bounded Linux rerun creates2000 fields in61.75ms (process peak
RSS16568→22716KiB), performs2500 replacement edits in20.88ms and restores the
3433B JSON checkpoint. Five fresh-process library loads take0.332–0.603ms and
first-document initialization0.184–0.208ms; OS caches were not flushed. These
are engine/Python/FFI measurements, not app cold-start evidence. The isolated
1003-input malformed sample again rejects all inputs without state change.

Evaluate Yrs [0.28.0 API](https://docs.rs/yrs/0.28.0/yrs/) with pinned crate bytes
and reviewed build hooks. It provides a text CRDT, state/update encodings,
sticky indices and selective Undo; these features still require an application
boundary. The experiment cannot silently replace the approved wall-clock causal
event order or drop original operations when undoing a causal update.

Before adoption, implement/test the approved legacy scalar loser policy and decide
shared activation bootstrap with a versioned reader boundary,
client identity allocation, resource limits/native parser isolation, restartable
Undo and materialized checkpoints. Consider other Yrs shared types only as
recommendations; no generic domain/store rewrite is authorized.

The evidence-only full app run37214941997 also completed successfully on
Linux/Windows/Android. Nested experiment evidence is now excluded from push-only
app builds; executable source changes, PR/manual runs and release candidates
still retain their checks. The hardened source push started full app
run37216546961; this experiment does not authorize application publication.


## Isolated Flutter editor harness

The separate [editor lab](../experiments/yrs-spike/editor_lab/README.md) uses only
synthetic in-memory replicas and an independent Android package. Its 12-case
matrix and assertions were frozen at16:42:24UTC before implementation, repository
commit `e1afed4`. Ten automated session/widget cases and the native Linux Flutter
integration pass; their frozen hashes remain unchanged. A first native run
reproduced loss of the composing range when the remote button stole focus.
Wrapping that control in Flutter's TextFieldTapRegion fixed the source; the
original assertion then passed. This is injected TestTextInput composition,
not actual OS-IME evidence. Actual Android runtime/keyboard checks remain pending.

The API24+ debug lab APK packages ARM64 and x86_64 engine libraries from the
verified hosted hardened revision. Official NDK28.2 `llvm-strip --strip-unneeded`
reproduces each APK-contained native payload exactly. It has a separate temporary
debug signer, contains no app protocol/storage imports and cannot access any
Tandemlog shared folder. Restart intentionally resets its synthetic data.
[Results](../experiments/yrs-spike/evidence/editor-results.json) are separate from
the immutable acceptance matrix. Main app analysis excludes independent
experimental packages; the manual isolated workflow analyzes/tests this one
explicitly, including Linux native integration and Android APK packaging.

[Adoption options](text-merge-adoption-options.md) distinguish the writer upgrade
policy needing Lee's decision from engineering recommendations for routing,
actors, checkpoints and measured budgets. None is an adopted production protocol.

## Activation-policy extension (pre-implementation)

Lee approved late legacy scalar text writes losing after activation, with original
records retained and no reconciliation UI. That does not permit upgraded native
edits to lose. The separate [18-case matrix](../experiments/yrs-spike/evidence/activation-policy-matrix.json)
is written before any activation-policy implementation; all18 are not-run. Earlier
frozen matrices/assertions remain unchanged. The proposed common-baseline bootstrap
and one-time initial-sync limitation are in [adoption choices](text-merge-adoption-options.md).
Actual Android lab/runtime and real OS-IME acceptance remain pending.
