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
