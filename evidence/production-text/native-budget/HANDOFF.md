# Canonical native resource/actor gate — 2026-10-04

Owned implementation: only `native/text_engine/src/lib.rs` and `native/text_engine/src/admission.rs`. Experiment wrappers still include the one canonical source. No new dependency, ownership/thread rewrite, production commit/publication, signing, native Android build or security billing. New tests are `experiments/yrs-spike/tests/test_resource_limits.py` plus separately labeled supplemental `test_resource_atomic.py`. No frozen existing tests were edited. Original C34 regenerates `experiments/yrs-spike/evidence/performance.json` as a test side effect; parent notified, no restoration over root-generated evidence.

## Test-first and validation

Resource/inspector preimplementation freeze SHA256: `663064224a7d5fb30abd4624bb58fed592bee95974be8080b1625321793487f4`.

Red against the previous canonical production SO:15 cases,13 failures,2 already passing cases (`red.txt`). First implementation:14/15 green; B08 exposed that filling replay weight exactly could leave no byte for the prior Undo marker (`green-first.txt`). Fixed by reserving one compact Undo replay marker before accepting non-Undo writes, without changing frozen assertions or pruning history. Final15 green (`green.txt`). All original75 plus these15 pass together,90 total (`green-all.txt`); both existing Rust worker negative tests pass (`green-native.txt`). All six Python freeze hashes verify unchanged (`frozen-test-sha256.txt`); stable rustfmt check passes on both owned source files.

Additional postimplementation targeted validation covers exact-receipt commit rejection and queued remote-update rejection, both retaining the frozen preparation, live state and original Undo (`atomic-receipt-validation.txt`). This supplemental pair is not described as preimplementation red. Its initial receipt fixture used cap300, which legitimately admitted measured committed weight296; measured preparation weight244 and committed weight296 led to tightening the cap to270 while retaining every assertion. Original fixture/hash/output and revised fixture hash are preserved separately (`postimplementation-test-original.py`, `postimplementation-test-sha256.txt`, `atomic-fixture-calibration.txt`, `postimplementation-test-revised-sha256.txt`). No native code changed for this calibration.

Locked canonical release build, pinned Yrs0.28.0/toolchain1.99 (`build.txt`), has no warnings. Final tested LinuxSO:
`/tmp/tandemlog-production-text-target/x86_64-unknown-linux-gnu/release/libtandemlog_text.so`.
SHA256: `945c219d8191fa861020aae90c577e5b8814d17b625570d50b9d510614c16f2d`.

After text_store explicitly identified a stale testing copy missing GUID metadata, this verified artifact was atomically copied to `/tmp/tandemlog-production-text-libs/linux/libtandemlog_text.so`. Parent and both integration agents were notified to use a fresh process. Already loaded old libraries are unaffected. No rebuild is now in progress. `implementation-sha256.txt` records final source/library hashes.

## Exact API

`inspect {update}` has no owner/name. It bounded-decodes base64 and uses the existing strict plain-text V1 Admission parser plus Yrs V1 decoder before returning `{structActors:[sorted unique positive int53 IDs]}`. Actual content struct authors include historical actor1 when present. Delete-set references, insertion-origin references and Skip causal holes are not claimed writers. Malformed/trailing/foreign-root/embed/format/etc packets return errors without actor metadata or document mutation. Inspection's decoded operation cap is1MiB; it does not open generic richer payload admission.

`new {name,client,seed?,limits?}` and `restore {name,client,checkpoint,limits?}` accept optional partial limits with exact keys:

- `visibleUtf16`: default65536; hard maximum8MiB units.
- `updateBytes`: default65536; hard maximum1MiB decoded operation bytes.
- `stateBytes`: default/hard maximum8MiB native encoded full-state/checkpoint bytes.
- `sessionBytes`: default/hard maximum16MiB retained session replay/preparation payload weight.
- `retainedBytes`: default/hard maximum64MiB retained serialized ownership payload weight per owner.

Unknown keys, nonobjects, booleans, zero, negative/noninteger values and values over hard maxima are explicit errors. Defaults preserve prior65536 visible/update admission cases such as C27/C30. Draft inherits source limits. Root application constructors will use visible500 titles/10000 notes, update1MiB, state8MiB/session16MiB, with canonical event JSON's1MiB cap remaining stricter than the native operation cap after base64/envelope expansion.

`new`, `restore`, `draft` replies retain `ok` and now include actual native `guid`/`client`. `read` retains `text`/`pending` and adds `guid`/`client`. GUID stays unchanged across replay-clone commit; restores/drafts have their actual fresh GUID, not invented equivalents.

`usage {name}` returns `ownerGuid`, `client`, `visibleUtf16`, `stateBytes`, `replayBytes`, `preparedBytes`, `receiptBytes`, `retainedBytes`, `sessionBytes`, `globalRetainedBytes`, `globalLimitBytes`, exact `limits`, and `accounting:"serialized-payload-bytes-not-native-rss"`. Global retained serialized payload is capped at64MiB across registered owners and receipt records.

Both production and spike ABI aliases share the existing worker/allocator. NUL-terminated input frames now permit12MiB JSON; both input allocation aliases permit12MiB+1 including terminator, and both release aliases accept the same bound. Reply JSON is bounded at24MiB. Input pointer/free ownership rules remain unchanged; arbitrary pointer defense is not claimed.

## Distinct limits and atomicity

Existing history/new seed/restore/private clone initial state use the configured state decode budget; ordinary incoming/generated operation packets use update budget. Checkpoint/history can exceed the operation budget while fitting the state budget. Strict admission still bounds parser work by the selected packet-kind byte budget and preserves seed/actor-clock/plain-root rules.

Explicit owner mutations stage the affected owner(s) using the prior replay-clone mechanism on the worker, with the same GUID/Undo origins/groups/anchors/private draft identity. Only after the operation, packet/visible/state/session/receipt/global checks succeed are owners replaced. Save stages both draft and target. Failures leave live document, original Undo, private draft, immutable prepared packet and prior receipts untouched. New/restore owners are validated before registration; duplicate/over-budget restores cannot replace the original owner. No canonical history/files are modified or pruned, and no auto-reset/close/rebuild/discard occurs.

Prepared Undo clone, exact compensation/token, queued remote packets and retained successful receipt responses are counted and can fail explicitly. A successful durable append followed by native commit budget rejection remains a coordinator recovery case: exact outbox/canonical bytes must be retained, not discarded or regenerated. Native rejection itself keeps the original live/prepared state. Restart session Undo persistence is still not promised. Undo has one replay-marker byte of headroom reserved on accepted non-Undo writes, but this is not a promise of unlimited future Undo/redo, restored-state growth or clone capacity.

## Accounting unit and measured engineering limits

The weight is an explicitly defined compact serialized-payload proxy: full Yrs encoded state; retained initial seed; each replay Apply's raw update, UTF8 origin and one kind marker; each Undo/redo marker; source name/GUID, encoded baseline vector and StickyIndex, owner name/GUID/client/composition metadata; recursively retained prepared replica/packet/token/queued packets; and receipt key/name/GUID/raw packet plus its serialized response. It excludes native allocation headers/capacity/hash buckets/Yrs indexes/Undo internal objects and transient replay/scratch/decoder/queued-RPC allocations. It is not an allocator measurement or native RAM cap. No receipt/history pruning is used to fit a limit; requested close/reset only releases disposable session ownership as before.

A fresh Linux Python+native process running all90 cases measured wall3.62s and peak RSS95268KiB (~93MiB), exit0 (`resource-measurements.json`). This includes the230000-unit >300KiB frame/checkpoint case and Python overhead; it is not native-only RSS or a worst-case8MiB checkpoint proof. The strict Admission identity HashMap stores one entry per retained UTF16 unit, so large retained histories and private clones can use materially more native memory than their serialized weight. Exact64MiB native RAM enforcement would require a separate allocator/work/peak-memory design; no such safety claim is made here.

C34's newly generated same-host synthetic measurement:2000 native edits+FFI2925.58ms; checkpoint restore+FFI0.400ms; encoded checkpoint2026 bytes. Replay staging adds measurable edit cost; this correctness gate is not an acceptance claim for long-session UI latency. Root should benchmark real bounded title/notes editing, delete-heavy retained histories and peak native memory before treating these engineering caps as production performance/RAM acceptance.

Remaining root-owned gates: actor registry binding actual author claims, canonical envelope limits, budget fallback preserving canonical outboxes and visible drafts, typed adapter/store integration, long-history native performance/RSS evidence, final Android/native rebuilding and platform acceptance. No accepted APK or production adoption is asserted by this handoff.
