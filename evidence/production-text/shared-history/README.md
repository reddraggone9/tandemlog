# Shared-history redesign: native/reference foundation

Status: native/reference, resolver, explicit new reference-proof and compact cache
implementation ready for independent review. No release/promotion performed.
Based on the recovered committed checkpoint `34addf6402ebe1d1546abe51e70f5264a929456e`.
Neither failed, unadopted recovery experiment was applied here. Parent separately
verified both original Library archives, their hashes/manifests and the eight-file
index overlay. This consumer's supported Library transfer returned HTTP403.
No old task, source file or synced user data was deleted or changed.

## Contract and test-first record

The graph retains immutable references to original canonical operations, scoped
to the original root context and seed. A recurrence can reuse the same reference;
a concurrent union points at its parents. Each original packet is retained once.
The graph verifies exact canonical metadata and claims, and privately retains the
decoder's deeply frozen envelope. It does not authorize inheritance grants or
derive actors: those remain caller responsibilities during resolver integration.

The new native materializer is an unowned, incremental Yrs document. It never
captures a draft, creates a Save receipt or supplies session Undo. Its admission
identity ledger advances with original packets, including pending dependencies.
A failed apply discards the private handle; callers reconstruct from originals.
Existing editor documents, draft tokens and Undo ownership are separate.

Private Save captures the draft's replayed transactions after its seed was
restored. The transmitted update no longer includes every inherited deletion
range from a state-vector diff. Existing receipt and private replay determinism
checks remain. The approved vendored Yrs patch and all 67 provenance-checked
source files are unchanged; this work is an adapter change, not an upstream fix.

The materializer conservatively charges cumulative input packet bytes plus
per-packet overhead and its native identifier. Per-update, state, retained and
global limits still apply. This can reject duplicate-heavy replay earlier than
the equivalent serialized final state would; it is not a total native heap/RSS
guarantee. The graph deduplicates original packet delivery on normal replay.

The Dart pool keeps at most eight live roots, 2048 snapshot summaries and sparse
checkpoints every 32 operation depths by default, with 16MiB accounted checkpoint
payload. Historical references remain immutable when disposable checkpoints or
live roots are evicted. Snapshot hashes are now lazy; full state is exported only for explicit old
proofs/editor capture or sparse checkpoints. The 32-summary acceptance gate
exports four checkpoints, then one explicitly requested state.
The resolver now shares references, original actor admission and native pools
across completion prefixes. Memo entries retain visible summaries and references,
with neither full-state BLOBs nor copied packet membership sets. Original authority
is retained once in the graph and is separate from disposable memo/checkpoint
budgets; total graph/loaded-history memory still grows with admitted originals.
New canonical prototype adapter2 declares structural history-reference hashes,
while adapter1 keeps exact native-state-hash meaning. Cache version15 stores
compact reference rows instead of inherited BLOBs/frontier arrays. Capture
reconstructs exact state and original IDs for existing editor/Undo APIs. Full
observed-prefix scans and warm command growth remain scaling work.

Six native gates were committed before implementation in `ce3ca26`. Four calls
initially omitted the existing ABI's required `delete=0`; `f08ce0a` corrects only
those fixture arguments and preserves both the original diagnostic and the
proper six-failure red run against the untouched baseline library. That commit
also freezes five Dart reference/checkpoint gates. `97dc6ec` freezes two more
ownership regressions: forged canonical metadata and caller mutation after
admission. Supplementary admission/budget controls in `8442d77` caught omitted
identifier accounting after apply; their valid red diagnostic is retained.
Existing 98 native acceptance cases and frozen scalar fixtures are unchanged.

## Current validation

- Production Linux library: all 107 native acceptance cases pass, including nine
  new cases for concurrent/duplicate delivery, pending checkpoint restoration,
  private-handle quarantine, editor isolation, compact Save deltas and budgets.
- All 487 Flutter unit/widget cases pass, including seven new graph/pool cases.
- After resolver integration, all 488 cases pass. The new resolver case verifies
  16 edited generations consume exactly 16 native packet applications across
  parent/successor resolution, preserve the same inherited reference, and match
  exact cold native state. Existing union/pending/invalid-author gates pass.
- Four Rust ownership/worker tests and all 36 tooling/provenance cases pass.
- Static analysis passes. No UI was changed; earlier recovered-baseline GTK
  evidence is not acceptance of an integrated redesign candidate.
- Final integrated suite: all491 Flutter tests,107 native tests,four Rust and
  36 tooling tests pass; analysis is clean. The one metadata expectation changed
  from cache14 to15; frozen historical bytes and zero-read assertions are intact.
- Bundled Linux Debug recurrence/child Save/receipt Undo passes. Native library
  SHA256: `a9b0c51f4f6cf347e321d9f47a0dec6161be161adfca44eb5be60c7db7a37e56`.
- Native Windows/Android candidate acceptance, remaining scaling work and
  independent implementation review
  remain open. No release or stable promotion was performed.

Frozen red evidence is in this directory. Full green logs are retained in the
consumer's `/workspace/recovery/shared-history-*.txt`; the tracked old timing
artifact generated by the native suite was copied there and restored unchanged.

## Measurement checkpoint

Actual production TaskStore/native FFI, Dart AOT, synthetic fixtures only.
Single runs on this executor; no constant-latency or cross-host timing claim.
At20/80/320 edited generations, cold rebuild is66.344/272.480/1355.529ms.
Native SQLite BLOB payload stays100/101/100B; reference metadata is
3204/12564/50004B. Exact warm/cold projections and original canonical bytes
match in every run. The earlier archived320-generation checkpoint measured
7806.304ms and3408717B of BLOBs, on its original environment.

The first640-request probe hit its90s wall bound at560 generations:3381.280ms
cold rebuild,100B BLOBs,87444B reference metadata. Its raw diagnostic remains
`edited-request640-bounded560.json`; it is not a completed640-generation result.
A second640 probe with a180s wall bound is preserved separately. Warm costs and
full observed-prefix work still grow; performance acceptance remains open. The
new driver retains all generated fixtures and uses a fresh profile for cold replay,
without deleting any files.
