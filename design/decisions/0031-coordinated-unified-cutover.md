# ADR 0031: Coordinated unified-only cutover and required operation revisions

Status: implementation authorized by Lee on 2026-10-20. Development and validation on copies are authorized. Live cutover and release publication remain separately held.

## Decision

Use one current unified append authority per writing installation. A private, one-time tool outside this repository validates and normalizes old canonical formats into the current operation format. The app does not coordinate a distributed history conversion or expose a time-zone opt-in. Unknown future operation families or revisions fail closed.

The September/October v3 backward-reader commitment is superseded for this separately coordinated cutover by Lee's explicit authorization to normalize historical records and remove the old wire decoders. Immutable originals, frozen decoders and a conversion report stay outside the live workspace and app repository. Existing published releases and tags are unchanged.

A retired importer's output may be consolidated only under explicit reviewed authorship mapping; actual household/device assignments remain in the private conversion report. Other historical-to-current installation assignments must be established from actual profiles or explicitly decided; sync node names and user/person IDs are not installation identity. Missing mappings stop conversion. Five active devices are not proof of five historical writers.

## Identity, authorship and normalization

Physical unified writer/sequence and historical semantic identity serve different purposes. Normalization rewrites the wire representation and physical attribution, not the meaning of an immutable operation reference. Retain stable semantic identity/reference anchors where native text context, observed prefixes, Undo, tag tokens and recurrence proofs require them. These are functional references, not copied source text or formatting provenance. Every normalized record has its current author explicitly; a retained reference namespace is not an active writer or a claim that a retired installation remains active.

Current operation content is independently hashed in the new format; the common unified chain covers the complete normalized body, including reference anchors and attribution. Converted bootstrap prefixes are sealed by the current manifest. Only those immutable prefixes may carry historical reference anchors distinct from their normalized content hash. New live reservations must derive their anchors from their own exact current content. No legacy JSON is embedded or accepted by the app.

The converter must validate old hashes/proofs before generating the new seals, then compare replay, native field lineage and reference outcomes through both implementations. Never flatten native documents into visible strings, silently remove tombstones, remint entity IDs, collapse Undo contributions, or use a final-row snapshot as a substitute for history. If a reference must change, recompute its complete dependent proof graph or stop explicitly.

## Required revisions on first persistence

Operation families and integer revisions form a closed registry. A revision is emitted only when its persisted meaning is needed. Revision1 retains the frozen existing time-zone rules; timezone-bearing operations using a newly supported name use the required revision that defines those fixed rules. Installation, startup, selection of a draft value, Cancel and no-op Save change no shared metadata. Future revisions are rejected rather than skipped by readers that do not implement them.

There is no separate mutable time-zone floor to race the first Task write. The required revision and data are in the same hashed operation. Same-session exact receipt/native ownership remains. Unfinished intent is not persisted or retried after restart. Partial remote tails wait for completion; complete unknown required semantics stop common admission for both modules.

## Client simplification and retained safety

Remove legacy live Task/Food file backends, the in-app upgrade dialog/session/participant protocol, runtime legacy conversion and the capability opt-in. Current domain reducers and native semantics remain even where an old operation normalized into the same current meaning. A domain action is not a legacy wire decoder.

Retain one private SQLite owner, protected settings/writer identity, common acknowledged heads, ordered shutdown, byte bounds, conflict/corruption fences and same-session uncertain-write/native capture safety. Unfinished Save bytes live only in memory. Canonical complete records determine what survived restart. Lee accepts loss of unacknowledged unfinished work; no durable outbox or restart retry is required.

One atomic user action/Save is one LF-terminated action with multiple typed effects. Logical effect IDs are independent of physical action positions. Bounds are16MiB/action,32MiB/file,256MiB/workspace and10000effects. The current bounded1000-item Food import fits one action. Conversion preserves each old committed operation rather than inventing atomic grouping.

Nonowners ignore unterminated tails without changing them. Before a new action the owner can compare/truncate only its suffix. Read-only refresh/preview does not clean it. Complete invalid records remain corruption. Android must prove rw/seek/truncate/fsync on the actual provider. An append-only provider unable to discard an abandoned suffix after restart must refuse a new write; replacing the committed prefix is not a fallback.

Keep installation ID and folder selection, plus selected person, appearance and last section when straightforward. Reset other local state, including drafts and unfinished Save/import intent. Canonical Undo effects, text lineage and history remain. Full profile snapshots/pending-save rescue are optional precaution, not cutover prerequisites. Do not reset an actual profile during development.

## Cutover procedure and validation

Inventory actual continuing installation IDs and explicit author mapping. Stop apps, settle sync and preserve accepted canonical copies plus immutable originals. Local unfinished state may deliberately reset; only simple settings are inputs. Run the tool against owned copies and a complete explicit mapping, never a live synced root. Compare intermediate and final projections, native text/context/Undo, recurring completion and successor references, deletion/restoration, manual order, Food inverses, duplicate/reordered delivery and future writes.

Publish the verified converted set only under separate coordinated live-cutover approval. Old binaries remain stopped after switching. Preserve originals and rollback material; returning after new-format writes needs explicit reconciliation, not blindly copying old files back.

The implementation needs a new exact candidate and native acceptance before any release. This ADR authorizes no live migration, database move, profile reset, release or unrelated dependency update.

## Alternatives, consequences and revisit trigger

The in-app participant/activation protocol and separate timezone floor are withdrawn: this household can arrange one offline cutover. Removing persisted restart retry also removes its retry-created duplicate scenario. Same-session uncertain-write reconciliation and native actor safety remain.

Retaining functional reference anchors avoids rewriting a native proof graph merely to consolidate physical authors. Flattening history into final rows would lose Undo, text lineage and recurrence meaning and is rejected. Missing ownership requires an explicit mapping decision.

The current native Undo button targets one saved text action; older text saves are undone separately. Extending that gesture to multiple native saves needs a deliberate native transaction design. Revisit record budgets/admission scanning with measured workloads, or provider support if native testing cannot prove safe suffix truncation. Exact native acceptance and independent review remain gates before a candidate is ready; live cutover and release require separate approval.
