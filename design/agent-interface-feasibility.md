# Agent-interface implementation feasibility

Status: **section 9.4 and writer cardinality resolved; implementation in progress**.
Baseline: stable2026.10.9/build106 source b6dbe70, current main452fe88;
accepted design9a67395 integrated linearly in release branch
`vex/agent-interface-20261029`. The separate accepted-design checkout is unchanged.
This is not RC/native acceptance or a passing performance qualification.

## Headless Dart/native assets — Linux source proof PASS

Pinned Dart3.13.4 built [the synthetic probe](../test/support/agent_headless_probe.dart)
with `dart build cli --target test/support/agent_headless_probe.dart --output
build/agent-headless-probe`. The compiled AOT binary, with DISPLAY and
WAYLAND_DISPLAY unset, loaded native SQLite and the existing reviewed text
engine, created a private synthetic unified workspace, opened Tasks, initialized
shared text and opened Food. `ldd` on the executable listed libc/libm/libpthread/
libdl, not GTK/Flutter. The text engine uses the injected/default executable-
relative library location; the probe copied its existing reviewed library into
`bin/lib` without changing its bytes. No new dependency or toolchain upgrade.

[Receipt](../evidence/agent-interface-feasibility/headless-linux.json) binds
payload hashes and scope. The first build failed certificate validation through
the inherited proxy; the normal direct HTTPS route succeeded with proxy variables
unset, not with certificate checking disabled. The first runtime probe exposed
missing synthetic folder setup; the corrected probe creates it before opening.
These are preserved findings, not candidate reruns.

Windows already has a pinned native-assets AOT process harness in
`.github/workflows/validate.yml` (Compile exact-source synthetic profile process
harness). That is a useful build precedent, **not proof of the agent CLI**.
Packaged headless Flatpak launch, its folder sandbox access, and both Windows
installer/ZIP launches remain pending and mandatory before release acceptance.

## Writer cardinality — resolved: implementation limit, no format decision

The accepted design requires distinct agent identities/installations/logs and
no agent-count cap. Existing v5 source carries count-only ceilings of 256
(probe `test/support/agent_writer_limit_probe.dart` from commit c1f2444,
removed with the ceilings in 46bde26 and superseded by `test/writer_count_test.dart`;
[receipt](../evidence/agent-interface-feasibility/writer-limit.json): 256
accepted, 257 rejected, no writes).

Independent read-only review (2026-10-29) verdict: **not a canonical format or
compatibility decision.** ADR0031 lists the canonical bounds (16 MiB action,
32 MiB file, 256 MiB workspace, 10,000 effects) and sets no writer count; the
256 exists only as code constants. Record shape, hashing, `v:5` and meaning are
unchanged. Removing the count is already covered by the accepted "no agent-count
cap". Old stable106 readers fail closed without writing above 256 writers
(`Too many installation histories.` sets `safetyFailure`; commit/cache guards
refuse; a >256-entry action fails decode), consistent with the existing rule that
older readers must update.

Implementation path:
1. Remove the count checks at `unified_record.dart` (observed > 256),
   `unified_history.dart` folder history count and protected inventory count,
   keeping per-entry, uniqueness and superset checks. Delete unused
   `FoodStore.maximumStreams`. **Keep** the manifest owner cap: the manifest is
   only the conversion snapshot; new installations join via `writer.joined`.
2. Byte bounds remain the only admission limit (no replacement count).
3. Tests: 257/1,000-writer actions accepted with manifest still capped; folder
   with ≥257 histories; inventory round-trip >256; frozen stable106 refuses a
   257-writer workspace with unchanged bytes.
4. Registered: `writer300-refresh` checks exactly300 physical histories, complete join admission, unchanged Tasks/Food values, canonical inventory and replay under the existing refresh budgets on all three shapes (see [performance coverage](performance-gate.md#bounded-cache-proof-overlap-and-installation-cardinality-refresh)).
5. Release note: workspaces above 256 installations (agents included) need every
   device on this release or newer.

## Restart-safe text Undo — feasible with existing native APIs

Private native spike (`tandemlog-agent-undo-spike-20261029`, Rust 7/7, prepared
Undo 12/12) passed four fresh-process reconstructions: peer edits preserved,
successive selective Undo, repeated Undo acknowledged without append, later own
action undone. Conditions:

- Keep **one durable Undo actor/allocation per agent field context**, recovered
  from the writer's own canonical `task.textEditUndone` claims; a first Undo
  allocates normally through the existing claim.
- Rebuild from canonical history (not a checkpoint): own edits via `apply_owned`
  with effect IDs as operation metadata, peers via remote `apply`; replay each
  own historical Undo via `prepare_operation_undo` + **exact durable byte
  equality** + `commit_undo`. Plain remote replay of old Undo loses Yrs's
  in-process redone graph (reproduced wrong `ReviewCheck…`).
- Already-undone is decided from durable `data.operation`, appending nothing.
- Atomic mixed action: build all text compensations and non-text retractions
  inside one `prepareFromFreshInputsInProfileQueue` builder and one
  `UnifiedRecord`; the GUI `_undoMixedTextOperations` loop is not reusable.
- Not covered: GUI histories with multiple Undo actors per writer/context. Agent
  profiles are new writers and never inherit GUI history as owned.

Evidence is synthetic native payloads, not canonical-envelope crash qualification;
integrated store crash tests remain required.

## Remaining section9 decisions and evidence

- Profile selection: separate CLI namespace from GUI, one private profile per
  agent; honor only TANDEMLOG_CLI_PROFILE, never silently TANDEMLOG_PROFILE.
  Resolve aliases/symlinks and verify durable role before opening; same-profile
  lock/retry, no host-name identity key. Exact platform paths not yet implemented.
- Read-only: current UnifiedHistory.open auto-joins new writers; preflight uses
  observe:false. LocalProfileDatabase.open takes exclusive SQLite/write
  transactions. A read-only shared session needs explicit no-enrollment/no-
  maintenance behavior and disposable cache state; copying the private DB under
  an identity lease is one candidate, not a verified solution. Original durable
  profile/workspace bytes must remain identical, including future-schema refusal.
- Canonical revision hashes must include sorted exact admitted operation IDs and
  hashes, not only visible fields. Plan hashes must bind exact dependencies,
  revisions, typed effects and command/API version. Validate under the same fresh
  append boundary; no distributed-lock guarantee. Existing action records supply
  durable action IDs; do not invent new canonical provenance kinds for receipts.
  **Implementation deviation (2026-10-29):** task and checklist revisions follow
  this (sorted admitted event IDs). Food container, product and purchase
  revisions hash projected state instead, because Food targets are changed by
  operations on other targets (product edits, merges, purchases) and a
  per-target operation index is not exposed. Accepted consequence: an
  intervening change that restores identical projected state (ABA) is not
  detected by the rev; plans additionally bind the whole observed state at the
  append (agent-interface.md section 11.5).
- Generic purchase source keys are already represented as `{kind,key}` by
  FoodPurchaseLine/FoodPurchase; keep source identity independent of mutable
  receipt-line values. CLI planning/required revisions/planHash remain unbuilt.
- Set/register CLI/MCP cold-open/list and import coverage/budgets prospectively,
  without weakening existing mandatory GUI/store limits. No timing acceptance,
  benchmark controller request or CI dispatch has run for this release line.

The implementation owner retains lib/main.dart integration and the queued Food
row-selection/Move some scope. No GUI/CLI feature, packaged candidate, native
qualification, RC publication or stable promotion is claimed here.
