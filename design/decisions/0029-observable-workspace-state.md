# Observable workspace state

Status: Accepted implementation direction, 2026-10-20; verification in progress.

## Context

A shared v4 admission can enter through either module. The old host copied Task
rows only when TaskStore.refresh reported a new Task revision. If a Food read or
command had already consumed a peer Task change, that revision was already
advanced and even later unchanged polls left the painted Task row stale.
Synthetic native-backed host regressions reproduced both triggers on unchanged
source a4f987ee1805cd62cd963610a8ae2b72883e7b3b; a direct-poll control passed.

An ordinary idle v4 host refresh also scanned the same root three times: Task
refresh, initial occurrence conversion planning, then Food refresh. Existing
exact-byte validation memoization avoided unchanged native Task replay, but
did not avoid those full wire reads and Food projections.

## Decision

A focused WorkspaceState session exposes the current immutable Tasks, users,
Food and health slices and one observation boundary. Canonical files remain
durable authority; this is a replaceable process-local projection, without a
new file, event, database or durable revision counter.

The existing shared SQL admission stages both modules. Fallible derivation
happens before COMMIT; projection assignment and settled health precede observer
delivery. Observers cannot turn a committed command into an append failure.
Failed admission retains last good content and publishes health separately.
Pending saves, incomplete history and recovery can change health while content
is equal. Slice identity is reused only after exact semantic equality.

The host subscribes to the exact open handle pair/session generation. Replacing
or disposing that pair detaches the subscription before closing handles. Draft
controllers, captured baselines, selection, focus and disclosure remain owned
by their existing editor/presentation sessions. New canonical state updates
availability and command guards without reconstructing a draft.

Ordinary v4 reconciliation uses one admitted read for both modules and initial
occurrence planning. Each actual mutation retains its fresh admission and
canCommit checks. V3 retains its independent module readers and isolated Food
failure behavior; its snapshot is a vector of admitted projections, not a claim
of one physically atomic legacy read.

Tasks retain time/zone/boundary invalidation through ViewClock. Hidden Task
projection work can wait until Tasks becomes active. Food derives grouping and
visible IDs once per current semantic state, workspace, view, search and filter
values. Focus/progress/error repaints reuse that result; expiration colors still
respond to the civil day.

## Alternatives

Per-action copies or an unconditional Task refresh after every Food action
would repair selected triggers while preserving multiple display authorities
and redundant scans. Metadata-only freshness would weaken admission. A generic
state framework or a new synced projection format is unnecessary for these
two modules.

## Consequences and verification

Retained snapshots must remain deeply immutable. Command reads retain their
existing fresh SQL/admission semantics; UI snapshot reads do not query SQLite.
Tests must cover indirect peer admission, coherent mixed-module publication,
rollback, pending/error-only transitions, throwing observers, mismatched cohorts,
reopen/close and draft preservation. Native visual and exact-artifact acceptance
remain separate gates; older artifact evidence keeps its source attribution.

Revisit if another module needs a concrete shared publication boundary or if
measured projection cost justifies more incremental derivation. Do not infer a
need for a general event bus or bypass canonical validation.
