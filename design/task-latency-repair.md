# Task latency repair (development only)

RC4 user testing found repeated pauses on startup, opening task editors, Save,
Undo and completion. The common history refresh repeatedly decoded unchanged
canonical records, while full semantic/projection replay repeatedly decoded the
same events and scanned JSON relationship predicates without indexes.

The repair reuses bounded immutable decoded records only for exact source
strings, uses a deterministic complete semantic-history validation key, and
indexes entity/successor/checklist lookups in the disposable SQLite projection.
Expression indexes are created after canonical rows replace old cache contents,
so malformed old cache JSON cannot prevent its ordinary rebuild.

Every provider read, byte limit, protected prefix, manifest/policy, physical and
semantic chain, future-required-event fence and admission check remains. SQL
projection rebuild and same-session uncertain append/native actor safeguards
remain. This adds no durable intent, restart retry, history-format change or
migration.

Synthetic regression coverage exercises 600 native tasks plus a second writer,
warm capture, one-record title Save/Undo and completion/Undo, cold reopening,
unchanged provider reads, invalid complete records, same-length prefix mutation,
and malformed old cache recovery. Realistic private-copy benchmarks and their
raw reports stay outside this repository. Debug storage timings demonstrate
the avoided work; native release UI timing remains a separate gate before a
future candidate. No personal fixture belongs in source or CI.

Stable publication and live cutover remain on hold pending successful user
acceptance. This repair does not authorize a new release.


## Incremental repair follow-up (development, acceptance pending)

The initial decode/index repair still rebuilt unrelated Task state on every new
action. The follow-up retains a disposable semantic validator between actions,
stages each complete delta under one SQL transaction, and projects affected
entities (including derived successors, checklist parents, move anchors and
text-baseline transitions). An invalid or non-monotonic candidate resets this
validator; canonical full replay remains the recovery/audit oracle.

Unchanged refreshes still read and compare exact bounded provider bytes and
protected heads. They reuse the admitted snapshot only after those checks;
size/mtime/range hints do not prove prefix integrity. Task-only actions reuse
unchanged Food admission by exact semantic input. Some global validators,
readiness computation and changed-history admission still scale with history;
the 100ms native Save target is not yet an accepted result.

A clean-close witness can reuse an intact local projection on the next startup.
It binds canonical visible Task input, manifest/generation/native support,
typed cache tables and readiness. It is durably consumed before reuse; hidden
physical effects still require validation. The witness is created only after
queue drain and equality with the independent semantic cache. Missing, damaged,
crashed or incompatible caches rebuild from canonical history. Cache-wide proof
hashing runs at open/close, never on ordinary Save. Explicit rebuild always
bypasses restored-cache eligibility. This stores no unfinished Save intent and
cannot authorize a restart write.

Private-copy measurements and screenshots remain outside the repository.
Hosted CI on the earlier18dbff7 passed all platforms; that success does not
attribute acceptance to this subsequent source. New regression, native timing,
independent review and replacement-candidate gates remain required.

## Current measured boundary

Changed histories reuse parsed immutable records only after the freshly read
committed prefix matches byte for byte and the manifest matches. An old
unterminated tail is always reparsed. Projection revision and readiness
certificates are disposable local values, never canonical format changes.

A fully ready graph can validate a pure text delta without auditing unrelated
non-text references. Eligibility is established before insertion, requires an
existing ready birth and known Undo target, and retains native packet, baseline,
new/reverse Undo and affected-field validation. Any uncertain native result runs
the skipped global checks before fallback readiness or commit. Cold replay,
mixed actions, unresolved histories and explicit cache rebuild keep full checks.
The visible projection uses a readiness certificate from its exact prior
published candidate; publication alone is not treated as readiness.

Remaining work is explicitly measurable: reads still verify complete bounded
canonical bytes; semantic-input ordering/digest keys and projection revisions
still traverse prior Task events; visible-row snapshots traverse current rows.
Repeat startup consumes and validates the cache witness and canonical source,
so its cost still grows with cache/history size. Full replay is reserved for
cold, invalidated or uncertain state, but this does not yet establish constant
time ordinary operations or the requested native latency.

Release-mode standalone AOT measurements are storage-only, not UI timings.
Current realistic-copy Save/Undo remain above 100ms; the repair is not accepted
for replacement publication yet. Exact measurements and private source/input
bindings remain outside the repository.
