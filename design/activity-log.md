# Activity log — next release design (2026-10-30)

Accepted scope: Lee requested a visible, read-only cross-writer Activity log,
interleaved by occurrence, with user/device attribution. This supersedes only
the browsable-audit exclusion in agent-interface.md §6; cross-writer Undo stays
excluded. Bulk-editor Cancel continues to exit selection.

## Canonical derivation and attribution

Use published UnifiedSnapshot records (sequence at or below the per-writer
published frontier; dependency-blocked validated records are omitted), not directory modification times, receipt
arrival or a new log. One atomic record is one activity; historical envelopes
retain their original semantic writer and clock. Show action types, affected
entities, recorded timestamp and installation label/UUID. Names are advisory,
not authenticated identities. Canonical history records the writing installation,
not the active GUI person; assignees are not actors. Therefore display user as
“Not recorded” where no actor was persisted; never infer that Hester performed
an action because a task is assigned to her or a device name contains her name.
No format change or retrospective identity invention. A trustworthy active-user
history would require a separate owner decision about new persisted attribution.

## Ordering and clock skew

Newest recorded occurrence first, based on the existing wall-time-informed
causal clock; ties break deterministically by semantic reference stream, sequence and ID. Current installation labels are
advisory and may differ from the name at the time of the action.
Historical envelopes use the original effect clock, not migration time. These
clocks are max(wall time, observed + 1), so causal observation and future device
skew can move displayed timestamps forward. Without independent clock evidence,
true physical occurrence across offline devices cannot be recovered. Explain
this in on-demand help: recorded device time, affected by clock skew, not arrival
order. Never silently clamp, rewrite clocks, or claim exact real-world ordering.

## UI and cost

Activity log is reached from the existing toolbar menu alongside Settings;
read-only, lazy rows, details on demand, narrow/wide layouts and large text.
No replay or canonical writes just to browse; refresh uses admitted snapshot
notifications. Empty/loading/error states remain explicit. Build derived rows
only while the log is open and only when its admitted revision changes. Opening
and scrolling need bounded visible-response review with realistic history growth;
`activity.read.derive` is registered before measurement at 15ms median / 30ms
maximum on all three matched-history shapes, using the unchanged ordinary
paired-growth rules. No existing limit changes. That label bounds derivation and
sorting, which lazy rows don't. It doesn't bound what a person sees: native
first-visible, scrolling, details and incoming refresh have no numeric budget and
no timed gate, and must be reviewed natively before acceptance, on realistic history.

## Other next-release fixes

Suppress the Food recovery banner for healthy in-flight writes, retaining it for
unresolved reservations/failures. Constrain Move some title/content at 200% text
with keyboard and allow Enter in its free-text location without bypassing an
active autocomplete selection. Increase the slow Windows CLI integration test
margin only (not product/performance budgets), retaining finite timeouts.

## Verification / release

Focused invariant/widget tests, independent code/design/editorial review, dark
native GTK and Android workflow/media, current-source unchanged-budget reference
qualification and mandatory hosted correctness/build/signing/install gates.
Publish an immutable signed prerelease, never Latest; no stable promotion or live
household data. Identity limitation above must remain explicit in evidence.
