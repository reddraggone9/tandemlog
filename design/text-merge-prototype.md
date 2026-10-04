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
| N02–N04 | Android two-ABI packaging/runtime; Windows native runtime; actual Flutter IME/editor integration | Android SO cross-builds pass; hosted Windows and actual Android/editor runtime pending |
| P01–P02 | Release size/init/cold/warm engine comparison and long-lived tombstone/document/RSS cost | Not run |

Engine-level composition/Save tests do not prove native Flutter IME behavior.
Cross-compilation does not prove Windows/Android runtime acceptance. A converged
string does not prove safe admission, checkpoint completeness or old-client
compatibility. Report each gate as pass, fail or not run with its exact evidence.

Evaluate Yrs [0.28.0 API](https://docs.rs/yrs/0.28.0/yrs/) with pinned crate bytes
and reviewed build hooks. It provides a text CRDT, state/update encodings,
sticky indices and selective Undo; these features still require an application
boundary. The experiment cannot silently replace the approved wall-clock causal
event order or drop original operations when undoing a causal update.

Before adoption, decide legacy scalar admission and a versioned reader boundary,
client identity allocation, resource limits/native parser isolation, restartable
Undo and materialized checkpoints. Consider other Yrs shared types only as
recommendations; no generic domain/store rewrite is authorized.
