# 0007 — Canonical record chains and explicit integrity checks

Status: accepted by Lee on 2026-10-03; implementation and exact candidate validation in progress. This replaces the v2-only integrity decision in the earlier Android reconciliation review. No stable release, data reset, conversion or real-data cutover is authorized by this decision.

## Context and goals

Canonical logs must carry their own checkable continuity information. Private SQLite prefix/range receipts alone compare against bytes previously seen by one installation: a fresh device has no such baseline. The application must also keep normal startup and foreground reconciliation incremental. Re-reading all history on each launch is not required to add chain verification for new records.

Lee approved retaining JSONL, embedding a predecessor and current record hash, and exposing **Check data integrity** in Settings. Binary encoding and compression were suggestions, not requirements. Keep the inspectable existing format: no measured size/performance problem justifies additional framing, seeking, indexing or recovery machinery in this change.

## Wire contract

Protocol v3 uses the same per-writer `.jsonl` filenames and a `tandemlog-space.json` manifest with `v: 3` and its canonical workspace UUID. Every complete record ends with exactly one LF. The envelope's fixed key order is `v`, `space`, `writer`, `seq`, `clock`, `entity`, `type`, `data`, `previousHash`, `hash`. Both hashes are lowercase 64-character SHA-256 hexadecimal strings.

The genesis predecessor is SHA-256 of the UTF-8 bytes of `tandemlog:genesis:v3\n<space>\n<writer>\n`, with actual LF characters and the canonical lowercase UUIDs substituted. Thus two writers or spaces have different initial predecessors. Sequence 1 must reference that genesis; every later record references the immediately preceding record's hash in the same writer stream.

The current hash is SHA-256 of UTF-8(`tandemlog:event:v3\n` + canonical record JSON **without** the `hash` field). `previousHash` is included. Hashes cover the protocol version, identities, sequence, exact decimal clock, entity, operation and every payload field. LF framing is excluded from the record hash; private byte receipts still cover the literal admitted file ranges.

Canonical JSON has no insignificant whitespace. Envelope order is fixed above; maps inside `data` sort keys by Unicode scalar value. Arrays retain order. Values are null, booleans, strings, exact integers in JavaScript's safe integer range, arrays or string-keyed maps; floating-point values are unsupported. The nanosecond clock stays an exact decimal **string**. Strings retain Unicode without normalization; quote and backslash are escaped, control characters use `\b`, `\f`, `\n`, `\r`, `\t` where applicable and lowercase `\u00xx` otherwise. Other Unicode is emitted literally. Unpaired UTF-16 surrogates are rejected. Readers reject equivalent but noncanonical spellings rather than hashing an ambiguous reserialization.

## Admission, cached reads and explicit checking

Self-hash, predecessor link, workspace/writer ownership, contiguous sequence, increasing writer clock, closed payload schema and domain/reference rules are all required. Fresh reconstruction verifies the complete current chain from genesis. Reordered/missing middle records, ordinary payload changes, accidental link changes and unsupported complete records fail explicitly. An incomplete remote tail waits; an incomplete owned tail blocks further writing. No check truncates or repairs history.

Private checkpoints retain the complete byte offset, sequence and chain head alongside prior observed-byte receipts. Ordinary open/resume/poll/commands reuse that persisted checkpoint: unchanged size/seek-capable logs read zero history bytes; growth verifies the suffix against the saved head and admits new records transactionally. Providers without usable size/seek support retain the honest full-read fallback. Notifications remain hints.

Settings performs a full current-file verification and compares against any retained observation baseline. Its selectable/copyable report identifies the affected writer log, one-based record and byte offset when available. Diagnostics never need to expose task titles or raw records. Valid newly arrived records may be admitted through the normal serialized path; the check itself appends no events and makes no repairs. Drafts, active edits, selection and Undo remain intact.

## Guarantees and limits

A chain is continuity checking, **not authentication**. A changed middle record cannot retain its old hash; subsequent unchanged links expose the inconsistency. An adversary or maintenance tool can recompute the whole chain. A fresh device has no independent trusted head and cannot detect that complete internally consistent replacement, removal of an entire writer stream, or removal of its final records. Existing private baselines can detect a mismatch or rollback against previously observed bytes/head during a full check.

Incremental reconciliation does not prove the current old prefix is unchanged: a same-size old-prefix mutation can remain undetected until the explicit check or fresh full reconstruction. Even growth can leave a changed prefix unread; the new suffix only proves that it refers to the saved predecessor. The Settings action makes full verification available to users, rather than suggesting that an unexposed Dart API is an ordinary recovery action. Neither sync nor these hashes replace backups.

Event ordering remains the approved exact wall-clock/causal scalar and `(clock, writer, sequence)` tie-break. Receiving events never changes their timestamps. Hashes do not establish human recency. Undo remains a new named contribution-retraction event; historical records and hashes are never rewritten. Replaying a completion still derives one successor without appending an event.

## Compatibility and coordinated test data

All participating apps must use the new protocol. V1/v2 manifests and envelopes fail with a specific preserve-old-data message; no decoder relabels them as v3 or adds hashes in place. Old SQLite files and installation identity are retained. This prerelease break is permitted before the first stable release, but disposable test data does not authorize deletion: coordinate backups, closed apps/devices and fresh test contents separately while keeping the permanent folder/share configuration. Markdown remains authoritative throughout prereleases. Final latest-source freeze/import/handoff is still a separate coordinated stable cutover.

The approved pre-stable cleanup removes the tests-only `setTags` API and separate `task.tagsChanged` wire meaning; real edits already use atomic `task.edited.tagChanges`. Materialized `tagOrigin` remains necessary for stable successor tag tokens and is not a canonical payload field. Generic `task.operationUndone` can no longer target recurring completion with a successor: true Undo uses `task.recurringCompletionUndone`, while checkbox Reopen continues to use active `task.completionUndone` and preserves successor work. No draft event is silently reinterpreted as another meaning.

Lee additionally approved the installation-level exact sequence/head guard, Linux parent-directory barriers and Android duplicate canonical-name rejection. A guard independent of folder location closes the restored-backup/new-path event-ID fork; prepared exact candidate prefixes survive uncertain append acknowledgments. Linux creation and atomic replacement flush files and parent directories, with interrupted barriers retried. Android refuses ambiguous canonical display names before selecting a document URI, including before cached unchanged-file skipping. These safeguards do not make arbitrary providers power-loss durable or authenticate writers.

An unresolved prepared suffix remains reserved even if a scan finds only the older complete prefix. Otherwise a delayed provider write could collide with a different new payload using the same event ID. This conservative safety choice can require coordinated recovery after an append failure whose bytes never arrive; the app does not silently rotate the writer or clear pending state. Exact observed prefixes may be acknowledged while their missing suffix remains reserved. The guard is safety metadata, not a second task source or automatic durable outbox; it contains sequence/hash pairs rather than user content.

## Validation and revisit triggers

Required evidence: cross-language canonical golden hashes, payload/link/genesis mutation, Unicode and serialization rejection, sequence/clock/reference checks, fresh replay, retained-cache rollback checks, unchanged/suffix-only I/O, partial batch/crash/acknowledgment recovery, recurrence/Reopen/Undo convergence, explicit Settings success/error/copy/draft flows, and exact native Android lifecycle/SAF regression. Candidate 37 is superseded and remains unpublished. Final candidate hashes and runtime results belong in status/runtime QA.

Revisit authenticated heads/device signatures, checkpoint publication or history compaction only when there is an explicit threat/recovery requirement. Those designs need key lifecycle, rollback and peer handling decisions; no keys or automatic coordinated history repair are introduced here.
