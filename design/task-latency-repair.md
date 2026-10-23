# Responsive canonical actions

RC4 user testing exposed repeated pauses when opening editors, saving, undoing,
completing tasks and starting the app. Ordinary actions were repeatedly decoding
unchanged records, rebuilding unrelated projections and restoring unrelated
native documents. Task and Food interaction coverage must be assessed together.

## Reuse boundaries

The incremental contract in [ADR0007](decisions/0007-canonical-history-integrity.md)
allows an unchanged, previously admitted file to reuse its immutable bytes when
the provider has demonstrated real seek support and its size, identity and
change stamp still match. Growth is read from the last complete newline, so an
old incomplete tail is checked again. Missing seek or metadata, replacement,
shrinkage and changed same-size stamps take the bounded full-read path. A pending
own append always receives a real suffix observation even when metadata is stale.
Provider buffers are copied before asynchronous admission; accepted checkpoints
advance only after the transaction commits.

Metadata hints are change detectors, not integrity proofs. As originally accepted
in ADR0007, same-size damage hidden behind unchanged provider hints can remain
undetected until Settings Verify Logs or a full reconstruction. Those audits
bypass reuse and verify complete canonical bytes. Strict decoding, sealed
migration references, physical predecessor hashes and exact protected byte
boundaries still apply whenever bytes are read. Protected heads use an explicit
chain commitment; old byte-digest checkpoints are fully verified before promotion.

The disposable semantic validator stages a complete delta in one transaction.
It resets on changed/removed evidence or a failed candidate. Native packets,
actor claims, baselines, reference rules and affected projections retain their
checks. Settled point operations require ready explicit births or already-protected
derived identities, with ready dependencies;
new sequences cannot fill old observed cuts. A single recurring completion may
also use an action-local proof of the exact previously selected untouched child
seeds: every child has no own activity, each claim has the same parent/source,
and existing copied items keep their original earliest seed. Retained successor
markers, conflicting claims, missing dependencies and uncertain contexts use the
full readiness path. The existing greatest-fixed-point readiness semantics are
unchanged. Creation, moves and their Undo retain ordering work. Local deleted/suppressed
item eligibility remains separate from canonical peer-ingestion semantics.

The main projection may reuse the six canonical reference audits only when its
owning common history certified the exact visible Task revision. A process-only
certificate binds both prior published and current input; public snapshot
construction, other histories and rejected physical candidates cannot confer it.
Native validation, affected entity closure, order and private editor/Undo owners
remain independent. Full replay stays available as the comparison oracle.

Checkpoint readiness reuses only the successful pure pending-bit result for
exact immutable state bytes under every native limit, within one engine owner.
This bounded memo contains no native handles or actor/admission authority.
Changed bytes, budgets or owner lifetime require a new check.

Recurring checklist membership/mode predicates are reusable only for the exact
completion, actual observed prefix and current legacy baseline/blocked scope.
The owning index verifies each declared cut and may reuse its exact successful
proof after only outside-cut appends. Current global native lineage/collision
resolution still runs; missing or changed interior evidence cannot reuse a cut.

The process-local recurring text input is a final opaque, strictly decoded and
deep-frozen value. Resolvers share its immutable entity/contribution indexes,
not native handles or resolved-field authority. An append strictly decodes only
new canonical records and advances those indexes only for fresh IDs, increasing
writer sequences and globally later order. Interior/reordered/conflicting input
uses generic reconstruction. Retained input is bounded to 4,096 events and a
conservative 16 MiB raw cost. One detached previous input supports a newly
observed complete cut; it has no backlink chain. Successful inheritance cuts
retain at most 128 entries and 2 MiB of accounted keys/frontiers/prefix
references. Failed or pending cuts are not cached, and an arriving interior
record invalidates affected cut evidence.

Checklist membership selects its parent births/copy seeds, every own record of
those item IDs and retractions targeting selected operations, then runs the same
domain projector. Colliding non-item births and cross-entity retractions are
retained for equivalent corruption/order behavior. An observed prefix builds
its own selection indexes; current global native collision and lineage checks
still run. The generic projector eagerly materializes creation membership so
testing each ordered action cannot repeatedly scan a lazy full-history filter.

Materialization sometimes passes the entity's already committed history as a
preparation overlay. An exact ID plus canonical-byte match contributes nothing
new and is removed before trying incremental append; this avoids rebuilding and
decoding the whole recurring input on ordinary completion. Different bytes,
unknown IDs and non-monotonic additions retain strict decoding/reconstruction.
No pending overlay is published as committed input. SQL-stage candidates replace
the retained input only in the existing post-COMMIT publication callback; failed
later projections leave the prior input, rows, protected heads and editor/Undo
owners intact.

Editor target checks use the same positioned/non-deleted/non-suppressed rows
predicate with an entity ID, followed by the same decoded Task-kind check.
They no longer decode unrelated current rows to inspect one Task. Ordinary
single-task editor Save and deletion use these target guards instead of
serializing unrelated Tasks into a global comparison token. This preserves the
documented allowance for unrelated Task updates; the native context and
ownership proofs and preparation's expected canonical revision remain checked.
Global content/order snapshot guards remain in place for bulk actions and moves. A target-only deletion must explicitly pass a null global snapshot and a target guard; without either form of protection it is rejected before entering the queue. Completion
also plans synchronously inside its owning queue after admission, then uses the
same after-refresh command path. Reservation still rechecks the expected
canonical revision before capture/append; a peer race cannot publish stale
completion or successor data. It no longer performs a second preflight refresh
or serialize all current Tasks merely to compare them with themselves. Settled admission rejects a
successfully decoded wrong-kind view before inspecting that entity's birth and
derived lineage; matching-kind targets retain every readiness/provenance check.
Malformed-cache parsing keeps the existing proof/fallback error ordering.
Food grouping retains each already-computed display grouping key for its sort
comparator; expiry priority and the exclusion of estimated status from that key
remain unchanged. These avoidable costs were identified in native callback
profiles; storage timings alone do not establish input-to-paint acceptance.

## Startup and disposable state

An already validated private projection can initialize a cold destination only
when its complete canonical raw set equals the visible candidate. Hidden or
rejected candidates cannot initialize visible SQL state. Lookup indexes are
created after validated rows replace old cache rows.

A clean-close witness binds canonical Task input, manifest, format generation,
native support, typed cache rows and readiness. It is created only after queue
drain and equality with the independent validator, and consumed durably before
reuse. Missing, damaged, incompatible or unclean caches rebuild. Metadata mixes
projection state and preferences: only order_projection and
text_baseline_verified belong in this proof or projection copy. Checklist
expansion preferences stay intact. No unfinished Save intent or restart replay
is added.

An accepted desktop close now awaits one idempotent shutdown future before
returning the native exit response. Busy or canceled draft decisions do not
start shutdown. Accepted closure quiesces new input and producers, drains existing
work, and attempts every close in the existing owner order. Widget disposal joins
the same future. Cleanup failure is reported once and explicitly exits the
quiescent app rather than exposing half-closed resources. Host tests verify lease
release, witness creation and actual proof reuse without relying on unmount;
actual GTK/Windows native-close validation remains a separate gate.

A separate layout2 decode cache stores exact outer record strings and their
already validated typed Task/Food fields, bounded to 4,096 records and a 16 MiB
payload. Its one-shot clean-close receipt binds location, installation, manifest,
protected heads, native support and cache layout. Restoration verifies the whole
payload checksum and binding before exposing immutable records; final opaque
receipts bind each typed module to its actual record/effect position, kind and
raw string. Food retains its cheap operation-shape validation. Missing, damaged,
stale or unsupported receipts fall back to strict canonical decoding. This is
private disposable-cache corruption detection, not authentication against an
adversary replacing both the cache and its proof. Closed validation or
normalization changes require a cache-layout change.

The cache never authorizes unseen bytes: startup still reads actual canonical
files and checks their physical chains, protected heads and sealed migration
references. Exact raw-string matches may reuse decoded objects. Settings Verify
Logs bypasses this decode shortcut. The Task projection witness separately reads
and checks typed SQL rows and readiness; cache JSON parsing, checksums and table
proofs still scale with the saved cache. No cached restart snapshot or durable
unfinished-save intent is introduced.

Canonical decoding yields between bounded complete-record slices before the
admission transaction, while retaining the profile queue and frozen input bytes.
SQL admission and staged native mutations remain synchronous.

## Measurement and remaining scaling

Release AOT storage/application/readmodel measurements are distinct from native
input-to-paint UI measurements. The versioned synthetic performance gate covers
the explicit Task/Food inventory and repeated histories; private fixtures and
raw evidence remain outside the repository. Performance acceptance cannot
substitute for state, Undo, replay, corruption and crash correctness checks.

Ordinary owned actions reuse one certified admitted snapshot, validate their
typed delta and observe the exact appended suffix before publishing both
projections. Unchanged peer logs are not reread. Incompatible, pending or uncertain
candidates retain the conservative path. Immutable collection copies, inherited
text resolution, ordered prefix comparisons and current visible-row snapshots
still traverse input; zero canonical file reads do not imply constant CPU cost.
Warm startup reuses decoded actions after checking actual canonical bytes and
validates the separate clean projection witness; it does not promise a zero-read
restart or a constant-time cache proof. These costs are
reported rather than described as constant time. Full UI responsiveness, cold versus warm startup, action-specific limits
and scaling need separate measurements. The Linux startup tool requests graceful
close only on the measured process's owned window and requires exit status zero.
A clean-repeat label also requires prior stopped-witness checks and actual
production Task/decode reuse counters. SIGTERM trials are explicitly abrupt and
do not prove clean-witness reuse. OS page caches are not flushed.
No performance limit may be loosened
without the owner's approval, and no correctness failure qualifies for a noise
rerun.

An ordinary peer refresh may reuse Food delta admission only after proving
that every prior visible Food ID retains its exact canonical bytes in the same
manifest/ownership mapping. The existing fully-ready index checks new records,
clocks, bulk target sets and dependencies; removed/replaced old records,
non-monotonic delivery and pending inputs retain full admission. A new Food
record no longer forces reprojection of every historical Food edit. Exact
Task-set certification is separate. The owned suffix confirmation also avoids a
second copy of the already-owned concatenated immutable physical buffer.

Remaining immutable physical/list/map/ready-set copies scale with retained
history references. Current visible-row serialization scales with current
entities. These are representation costs, not required durability guarantees.
For a rooted read under a ready, actual owning history, text resolution
synchronously selects a detached closure from strictly admitted records and
relation indexes. This applies below and above the whole-input budget of
4,096 Task records or 16 MiB raw cost, so an ordinary append does not invalidate
and reconstruct a whole-history text input. Selection requires its
current committed key or the exact inserted candidate scope; general validator
fallback cannot borrow old committed rows as candidate input. Declared cuts,
competing seeds, copies, retractions, baseline and native collision checks remain
separate. The selected-cut type cannot stand in for a generic complete prefix,
and selected memo provenance survives weak-receipt collection. Selected cut
retention has the same 128-entry/2 MiB accounting bound; oversized cuts are not
cached. Generic, sparse, foreign and unready inputs keep the full oracle.
Relevant lineage and required baseline work may still grow; this removes the
unrelated-history cache cliff without raising caps or claiming constant time.

The repair changes no canonical format, atomic action boundary, durable signing
safeguard or live workspace. Stable publication and live cutover remain separate
acceptance decisions.

## Recurring text and measured calibration

The sanitized history-only calibration exposed a recurring-text decode cache
cliff above 2,048 records: repeated scans evicted later-needed entries and
produced about 21,000 decode/freeze misses per inherited title Save.
RecurringTextMemo now snapshots its bounded exact-raw entries for one scan and
refreshes hits through ordinary accounting. Its entry cap is 4,096 with the
same 16 MiB retained raw-payload budget. A batch can temporarily retain another
bounded old payload set and references; 16 MiB is not a peak-heap guarantee.
Changed bytes still decode fully, and conflicting records still fail.

The selected path and generic path share that one strict, deeply frozen,
exact-raw record pool. Each selected index, available-sequence map, head scope
and observed cut is built anew; decoded-record reuse grants no contextual
validation or admission authority. Lazy heads use the same bounded pool.
Clearing it releases all cached records before native cleanup is attempted.

Reverse tag-reference validation uses the owning validator's committed relation
index only for its current verified snapshot or exact inserted candidate scope.
It selects every removal targeting the pending event and every event on a
completion's successor, including inactive removals. Candidate membership is
still checked against actual SQL bytes. The existing token, entity, clock,
index and derived-seed checks run unchanged. Foreign, unready and generic full
validation retain the SQL oracle. This avoids scanning unrelated historical
Notes for every local title Save without skipping tag integrity checks.

Move-anchor existence and validation queries also use an expression index on
event type and before target. Otherwise unrelated historical moves remain a
type-filtered scan even when title edits use selected text. The ordinary private
projection index initializer installs the index after a canonical rebuild and
on a restored cache; rollback resets that initializer as before. Canonical data
and reference checks are unchanged.

Established derived identities can use point updates when both the prior
physical activity and actual selected seed are ready. A single first pure text
edit also reuses readiness when its prior selected seed is already the earliest
ready seed and remains exactly that seed after projection. The same private
proof admits a single Task schedule, assignee or tag edit, native Task text plus
those metadata fields, or a copied item's completed-only toggle. These actions
still pass the existing point dependency and shape checks. For a copied item,
the proof includes its derived parent, since item activity protects the parent
birth too. Changed selection, missing native context, unsupported mixed actions
and ambiguous claims retain full validation. Anchor-only protection does not
grant a broader shortcut. A fixed SQL replay shares one
canonical resolver. Pending native validation does not give unpersisted sibling
effects permission to serve as observed history.

A committed publication shares one current resolver between editor captures
and Undo owners. The native packet graph reuses an already frozen packet only
for exact canonical bytes, with every metadata, data, claim and update check
still performed before its duplicate shortcut. Ordinary local native commands
delegate canonical validation to the complete candidate check, which runs
before reservation callbacks or append. Creation and baseline checks remain
local, and observed-frontier checks still require old persisted SQL membership.

On the i5-12600KF Linux worker, with a two-CPU quota and 6 GiB memory bound,
the retained earlier public calibration (trial47, source snapshot46) used two
warmups and five samples per action. Both fixtures have 793 live Tasks, three Users, two checklist items
and 329 Food containers, with identical current state. They contain 1,325
and 2,645 physical records (1,688,850 and 3,180,181 canonical bytes).

| Storage/application operation | Smaller median / maximum (ms) | Larger median / maximum (ms) |
| --- | ---: | ---: |
| Explicit Task title Save | 67.18 / 69.52 | 96.75 / 101.78 |
| Inherited Task title Save | 94.65 / 103.14 | 154.51 / 167.62 |
| Recurring completion with native checklist | 132.50 / 134.06 | 228.34 / 232.19 |
| Derived successor title and Notes Save | 119.02 / 122.24 | 212.96 / 221.00 |
| Derived successor completion | 184.55 / 186.80 | 351.47 / 361.13 |

This is calibration, not accepted release evidence. The observed maximum of
five samples is not a p95 or p99 estimate. Fresh-profile startup does not imply
a flushed OS page cache. Actual native input-to-paint timings remain pending.
The larger synthetic budgets are separate from the roughly 100 ms ordinary
action target on representative realistic data; passing them cannot establish
that target. These retained numbers predate the incremental admission and layout2 cache
repairs; they are not current-source acceptance. Current candidate results need
their own exact-source receipts, including residual recurring costs, startup
proof work and the separate native UI boundary.


The owned ready checklist-seed lookup reuses the same validated owning scope
as text resolution and reads its exact per-item copy relation. It returns every
matching claim, sorted by canonical event order, including competing or retracted
completions. This avoids rebuilding
a scope-wide copied-descriptor index or scanning its payload budget for an
unrelated ordinary edit. Generic, unready, stale and suppressed scopes retain the
full SQL oracle; the descriptor cache budget remains unchanged.


Clean-cache startup preserves the same generation2 byte digest, scope binding,
kind/position checks and opaque receipts. Fresh decoded JSON trees are frozen in
place before unmodifiable views escape, avoiding redundant collection copies.
Pure whole-batch verification runs in a short-lived Dart isolate with only three
immutable strings; profile transactions, canonical reads/admission and native
text ownership stay on the owning queue. The one-shot proof is consumed durably
before awaiting the worker. Unavailable or failed optional verification falls
back to strict canonical reconstruction. This improves UI responsiveness rather
than promising that verification or disk durability takes less than100ms.
A full owned canonical candidate may reuse its already-computed Task root after
an exact cached ID/raw bijection; a cached prefix retains its own root check
before any arriving delta is admitted.

An untouched derived identity can change its selected birth when activity first
protects it. A single native pure text edit, Task point metadata edit, native
Task text plus point metadata, or copied completed-only toggle avoids full
readiness only when a private action-local proof records the earliest ready
selected seed before the edit and verifies the exact same identity after
projection, including a copied item's derived parent. Task metadata remains
limited to schedule, assignee and tag changes, with ready user and observed-tag
dependencies checked by the existing predicate. Both generic monotonic incremental validation and owning
append validation retain native pending/context checks and the all-old-ready
precondition. A failed postcondition restores the full path; later surviving
seeds, unsupported action shapes and uncertain claims remain conservative. No public DTO or
caller-supplied key grants this proof.

The remaining full readiness path indexes the earliest copy birth by
compareEvents once, including retracted and competing claims, instead of
repeating transitive copy lookups. Successor selection, native checks and every
readiness dependency remain unchanged.

Copy-seed lookup uses the existing owning validator's exact per-item claim
relation, not a transitive text-selection closure. The snapshot key, owning
validator, readiness and byte-exact inserted-candidate checks are shared with
selected text reads. Empty claims return an empty result; an untrusted scope
falls back to the original SQL oracle. All competing/retracted claims and
candidate claims are retained in compareEvents order. No new cache or size
budget is introduced.
