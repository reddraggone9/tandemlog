# Admission identity/work budget gate

Owned changes: canonical `native/text_engine/src/lib.rs`, `admission.rs`, new `experiments/yrs-spike/tests/test_admission_units.py`. Single parser/source, no dependencies, history pruning, native allocator rewrite, commits or publication.

## API and mechanism

Owner limits accept optional positive integer `admissionUnits`, hard cap8388608; omitted legacy default8388608 preserves prior historical230000-unit checkpoint tests. Limits response echoes this key only when explicitly supplied, preserving prior exact five-key response. App explicitly sets100000. `inspect` accepts optional top-level `admissionUnits`, default100000, same validation/hardcap. It continues returning only actual sorted struct authors, never delete references or Skip identities.

`Admission::parse_with_budgets(bytes, byteCap, unitCap)` checks string UTF16 count and cumulative identity count BEFORE populating per-unit HashMap entries; rejects oversized content before Yrs Update decode/materialization. Client counts, cumulative struct blocks, cumulative delete ranges, and cumulative Skip span each have explicit unit-budget work bounds. Identity units are retained historical UTF16 units including deleted content, distinct from visible text or encoded bytes. Skips are work only, not author/content identities. Independent categories have separate bounds rather than accidentally charging one valid identity multiple times.

Incoming owner operations preflight both individual packet and combined union with established identities BEFORE temporary Yrs integration; repeated identities are counted once and must match prior content. Whole generated/rebuilt owner full state and prepared nested replicas are checked before staged swap/registration, so edited/deleted history cannot evade cap. Captured drafts inherit limit. No canonical files touched; rejection preserves live/doc GUID, draft, pending compensation/token/receipt, and session Undo intent. Strict structural cap does not promise all future Undo fits: Undo itself creates new restoration identities, remote/history growth can exhaust capacity, and compensation can reject atomically while retaining intent.

## Frozen evidence and correction

Original six tests frozen preimplementation hash`bc4fcb73dacf3fc2f758e73c6a417a2c0b8879bc10d85b4cf25abfe28572de5f`; original bytes saved`frozen-original.py`. Preimplementation red:6fail (`red.txt`). First implementation5pass/1failure: U03 mathematically impossible assumption that seed3 + two replacements =5 retained identities could also restore Undo's sixth identity under cap5. Intermediate work accounting also counted blocks+ranges jointly and rejected too early; corrected independent work categories without changing frozen assertions.

Parent explicitly approved fixture-only U03 correction: cap6, rejected third insertion`NN` would create7 retained identities; existing positive Undo then creates sixth. All assertions retained. Corrected hash`a8d03b906fceffa824c23ac2fb843f2848cec1c0bd31d057d185151db3f2b790`. This is six corrected cases green, NOT all original six frozen cases green. Frozen original/hash and intermediate failures preserved. No arbitrary Undo reserve or weakened exact cap added.

Final all98 Python PASS: unchanged prior90 + prior supplemental2 + corrected6. Two Rust worker negative tests PASS. Existing freeze verification recorded in`old-freeze-verification.txt`. Supplemental postimplementation pending rejection validation checks exact pending token/update, unchanged live state, unchanged captured draft, and successful exact-receipt commit after rejection (`pending-immutability.txt`). This supplement is not preimplementation-frozen.

Original C34 regenerates its performance.json during aggregate test execution as before; no manual edit/restoration over root evidence. Historical acceptance measurements in previous /tmp directory unchanged.

## Build and measured acceptance

Production SO staged atomically at`/tmp/tandemlog-production-text-libs/linux/libtandemlog_text.so`, same bytes as release target, SHA256`892d5048fc30c615fd672a6d6e9a8000ca8fdf6723271e54317356debf9bc6b3`. Fresh process needed. Pinned1.99 release build clean; Rust source formatted with installed stable rustfmt. No build running; adapter/store owners notified.

Exact valid1MiB decoded fixed packet on final build:
- title500: rejection2.184ms, payload-readyRSS16008KiB, process peak18224KiB, delta2216KiB.
- notes10000: rejection3.099ms, payload-readyRSS18340KiB, process peak20876KiB, delta2536KiB.
- error`admission identity budget`, exact state unchanged. Prior unchanged-build fixture was276–326ms/~224MiB transient delta. Thus scoped measured blocker fixed well below requested~20MiB delta; no full RAM-cap claim.

Final representative1000 near-full replacements with admissionUnits100000:
- title: maxedit2.908ms, p95edit1.832ms, read0.063ms, prepare0.044ms, save2.296ms, prepareUndo0.305ms, commitUndo0.429ms.
- notes: maxedit11.469ms, p95edit3.357ms, read0.049ms, prepare0.022ms, save5.099ms, prepareUndo2.557ms, commitUndo3.231ms.
Remote edits survive and prepared save packet equals saved packet. All fresh subprocess diagnostics individually bounded60seconds; actual completion normal. Raw`final-measurements.json` and reproducible`measure.py` preserved. Notes maxedit increased from prior4.611ms due additional state checks and host noise; measured below16ms on this Linux sample, not universal UI/mobile promise.

RSS includes Python launcher/fixture/JSON plus native engine; payload-ready subtraction isolates practical added peak approximately, not native allocator ownership proof. Serialized64MiB remains NOT RAMcap; a configured100K identity history and multiple clones can exceed compact serialized bytes materially. Actual worstallowed8MiB state/fullsession saturation, Android peakmemory/latency and2000-task Flutter owner instrumentation remain separate root acceptance gates. No automatic pruning/restart/reset to recover budget. Budget fallback preserves canonical log/outbox and draft; coordinator recovery remains root-owned.
