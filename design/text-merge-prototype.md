# Test-first isolated Yrs prototype — 2026-10-04

Status: Lee authorized a bounded cross-platform investigation, not production
adoption. No application dependency, event meaning, durable history, schema,
signing identity or checklist changes are part of this experiment. The isolated
working package is outside the repository; only its decision/evidence summary
is maintained here.

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
| C01–C05 | One historical seed; Save/Cancel; captured-baseline changes preserve concurrent inserts/deletes | Not run after implementation |
| C06–C13 | Offline concurrency, same-location edits, duplicates, all arrival permutations, delayed causal dependencies and checkpoint recovery | Not run |
| C14–C15 | Independent fields and recurring-successor text | Not run |
| C16–C21 | UTF-16, emoji/surrogate boundaries, combining/ZWJ/Markdown, composition commit/cancel and sticky selection | Not run |
| C22–C25 | Selective Undo/Redo as appended compensation preserving remote work | Not run |
| C26–C30 | Malformed/oversized updates, invalid offsets/base64, actor collision, text limits, atomic rejection | Not run |
| C31–C34 | Exact JSON update bytes, checkpoint/tail equivalence, native memory cycles and measured edit/restore/storage cost | Not run |
| A01–A03 | Actual frozen-v3 TaskStore replay; old-reader rejection; explicit old scalar writer admission policy | Not run |
| A04–A06 | Pending-struct retention, wrong root/embed/type admission, fresh-process/truncated/hash recovery | Not run |
| N01–N04 | Linux/Dart native ABI; Android two-ABI packaging/runtime; Windows native runtime; actual Flutter IME/editor integration | Not run |
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
