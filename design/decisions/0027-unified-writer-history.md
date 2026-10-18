# ADR 0027: One app-wide writer history and optional installation names

Status: published experimentally as 2026.10.7-rc.2/build91 for isolated disposable trials.
Adoption/consolidation of abandoned writers is deferred by Lee (2026-10-18).

## Context and decision

Tasks and Food have separate canonical streams and append/recovery authorities.
Lee approved replacing them with one complete app-wide linear history for each
immutable installation writer, including original Tasks and Food history.
Coordinated conversion must preserve original semantic IDs, bytes, hashes,
clocks, conflict ordering, Undo references and native text lineage.

A v4 activation manifest binds one conversion epoch and original source seals.
Each writer has one .applog containing a closed canonical envelope, monotonic
common sequence and clock, previous hash, one transaction frame and an immutable
semantic effect. Historical effects retain their exact original wire records.
Physical app positions are distinct from semantic IDs. Future Task and Food
effects use the common allocator and recovery receipt.

Future frames declare exact observed common frontiers. A reader validates the
whole format and physical evidence before publishing effects. Publication is a
fixed point of complete writer prefixes and domain readiness: a missing Task,
Food, native, Undo, tag or checklist prerequisite holds the whole frame, and
later frames observing a held prefix wait with it. Physical bytes remain
protected while effects wait. Legacy single-event semantics retain their
existing pending-reference behavior.

Use the existing serialized local profile and protected SQLite authority.
Reserve final frame bytes once, recover those exact bytes after interruption,
and never allocate a second set of identities on retry. Caller guards must pass before the common reservation commits. Receipt callbacks run after that durable acceptance point because native sessions bind receipts irreversibly. A callback failure retains the accepted exact intent for recovery; it cannot leave a bound native preparation without authority. Preserve every old
trusted writer head, retained cache/import receipt, byte prefix and range
observation when establishing the new authority. Rebuild reproduces identical
canonical bytes; projections are disposable.

An optional writer.named event changes only the writer's display label.
Blank clears the label. Duplicate names are allowed. The immutable writer UUID
determines identity, attribution, deduplication and ownership. Unnamed writers
use a short-ID fallback. A reinstall or replacement creates a new installation
history even when it uses an old device's display name. Original installation
histories remain under their original writers.

## Boundaries

Conversion and activation are restricted to disposable workspaces in this
milestone. Production migration and deletion remain unauthorized. Experimental
publication followed accepted coordinated participant acknowledgements, durable
crash recovery, cache reread, application adapters and exact native acceptance.

Adoption, ownership transfer, retirement of old writers, a history browser and
a large-history performance project are outside this release. Ordinary efficient
refresh remains a requirement; no new sync service or permissions are authorized.

## Alternatives and consequences

Separate active Task/Food allocators cannot provide one ordered writer history
or a shared transaction/recovery boundary. Archiving old logs while starting a
new chain would not provide complete history. Reinterpreting old IDs or hashes
would break durable references and is rejected. A coordinated format change
requires capable participants and an explicit activation barrier; offline or
late legacy writes must stop the trial rather than be silently omitted.

Human labels solve the immediate reinstallation/replacement identification need
without adoption and custody rules. Equal names do not imply equal writers.
Revisit consolidation after a concrete management or measured performance need.

## Implementation status

The isolated branch includes the wire/conversion model, shared coordinator,
common outbox and append-only recovery, preserved native/domain semantics,
dynamic installation enrollment and optional naming events. Task/Food command
adapters include native text, checklist, Undo and import recovery. Both host
sections open one coordinator and share safety admission and pending retry.
Settings uses the shared form-validation controls for optional names.

UnifiedTrial implements synthetic-only staged activation, participant input and
output validation, protected exact backups, crash phase recovery and owned-source
cleanup. New installations retain separate immutable writer IDs. Duplicate
human labels do not adopt old histories. The retained migration roster is not a
permanent installation membership list.

The affected aggregate passes 139 tests. Full regression passes 1298 tests with
clean analysis, and 85 tooling tests pass. Independent source/architecture/privacy
review clears the isolated draft scope. Private checkpoints retain exact receipts
and failures. Exact owner86-to91 upgrade, v3/v4 recovery, fresh setup, read-only replay and
media/editorial acceptance subsequently passed independent review.
[Candidate and publication receipts](../../evidence/prerelease-2026.10.7-rc.2/publication/README.md)
retain exact artifact binding and platform/UI qualifications. The local schema3-to4
upgrade is forward-only: stable/build85 and RC.1/build86 cannot reopen that upgraded
profile; existing v3 shared workspaces remain v3. No production migration or
deletion occurred; experimental publication is complete.
