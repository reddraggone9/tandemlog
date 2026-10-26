# ADR0035 — exact completion instants and viewer-local history

Status: Lee accepted2026-10-26; implemented locally, unreleased. Supersedes
ADR0034's civil-date-only completion scope. Publication/live adoption remain held
by ADR0031; no original history or published release is rewritten.

## Goal and decision

Record actual command-time completion and show globally newest history first,
without repeated per-row dates or an unsolicited clock badge.

- Every NEW task.complete is required revision3, all snapshot/native/checklist/
  retained-successor modes. Its values carry `completedInstant` only, never
  `completedAt`, a completion zone, or an approximation flag. The single encoding
  is UTC `YYYY-MM-DDTHH:mm:ss.ffffffZ`, years0001–9999, exact component roundtrip.
  Revision3 is cumulative with revision2's additional schedule-zone names.
- Capture the injected clock inside serialized preparation, after final checklist
  consent, refresh and freshness/write guards. Cancellation/stale consent samples
  nothing. Device-clock rollback is not monotonized with the causal clock.
  Existing uncertain-write receipts/recovery retain precisely the prepared bytes.
- Resolve the recurrence anchor in the freshly refreshed task zone (or captured
  device zone) at that same instant. Bake the successor schedule/proofs into the
  event as before; replay and Undo never recompute it from a viewer's timezone.
- Keep the canonical completion-set winner (clock,writer,sequence), including
  reopen/Undo semantics. Project instant/microseconds/order from that ONE surviving
  contribution, clearing all together. Instant is display order, not admission.
- Completed/search sort descending by instant, then descending completion order,
  then immutable task ID. Group headings and search metadata derive the viewer's
  local civil day. Completed rows omit the repeated date. Open-task timing/Today,
  tags, assignee and chronological drag restrictions stay unchanged.

## Compatibility and conversion

Required revision is in each hashed operation. Frozen r1/r2 readers reject r3;
unknown future completions stop common admission and writes in BOTH modules,
retaining last-good state. Existing partial-tail waiting/retry rules remain.
The current decoder retains r1/r2's historical date meaning; live command paths
cannot emit them. Disposable Task projection generation5 and action-decode layout3
invalidate old derived witnesses without changing protected identity or authority.

The external ADR0031 normalizer must enrich EVERY historical completion, including
undone, checklist and retained contributions, during its existing single cutover.
`tool/normalization/completion_instant.dart` supplies the offline pure adapter:
explicit ISO instant if date-consistent; otherwise ORIGINAL semantic scalar clock
nanoseconds divided by1000 if date-consistent; otherwise noon of the old recorded
day in its evidenced completion-era zone (UTC default). A whole skipped date uses
noon UTC on that day. An absent date uses the validated original clock. Conversion
methods belong only in the external receipt. No runtime inference or second
migration; no transport/file/cache/arrival timestamp source.

External frozen reader/source-format inventory, actual installation mapping,
sealing, real-copy replay and production adoption are not supplied or executed by
this checkout. The adapter and unchanged synthetic stable-v3 prefix replay are
bounded development evidence, not a claim of that held real-copy acceptance.

## Alternatives and validation

Rejected storing duplicate civil date/zone: the successor already contains the
capture-time recurrence result and display follows the viewer. Rejected sorting
by causal clock or preserving original-zone date headings: neither gives global
instant chronology. No approximation marker was requested or added.

Frozen sources/inputs retain their old bytes/hashes. Independently generated r3
operation/action vectors are separate. Tests cover strict encoding, frozen-reader
refusal, normalization, cross-zone headings, winner/retraction, confirmation across
midnight, unchanged recurrence, exact-byte retry/restart and cache/full-replay
oracles. Native Linux/Android review and existing performance/release boundaries
are recorded separately; timing budgets and accepted performance fixture bytes
are never loosened or overwritten by this change.

Owner: Tandemlog maintainers. Revisit upon a demonstrated conversion input shape,
zone-rule upgrade, or explicit request for a task-history details surface.
