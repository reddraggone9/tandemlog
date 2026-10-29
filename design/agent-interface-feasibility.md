# Agent-interface implementation feasibility

Status: **investigation in progress, no product implementation accepted**.
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

## Writer cardinality — executed existing-source conflict, assessment pending

The accepted design requires distinct agent identities/installations/logs and
no agent-count cap. Existing v5 has a shared256-installation ceiling, including
GUI writers and preserved historical writers:

- `unified_manifest.dart`: at most256 bootstrap owners.
- `unified_record.dart`: at most256 observed frontiers per canonical action.
- `unified_history.dart`: at most256 protected observed writers and histories.

[Pure synthetic probe](../test/support/agent_writer_limit_probe.dart) constructs
and round-trips256-writer manifests/actions, then attempts257. The
[receipt](../evidence/agent-interface-feasibility/writer-limit.json) records256
accepted (51746/31892bytes, far below byte limits),257 rejected. No filesystem,
profile or canonical writes occur in this probe.

This is not resolved by choosing profile directories: reusing a writer identity,
deleting old histories or allocating an artificial fixed agent pool contradicts
the accepted ownership/data constraints. The possible implementation is to remove
count-only ceilings while retaining total workspace, file and action byte limits,
bounded validation and exact frontier/hash checks. Whether that is an authorized
implementation-resource change under the accepted unlimited-agent requirement,
or requires a separate durable compatibility decision, is undergoing independent
assessment. **Do not infer a new approval gate merely from this observation.**
No count, byte or performance bound has been changed.

## Restart-safe text Undo — independent native proof pending

Existing native `apply_owned` and `prepare_operation_undo` support named receipt
ownership. Native `undo_operation` selects only that stack item, not an unrelated
latest item, and documents disable GC. However TaskStore currently registers
owners using process-retained captures/pre-Save bases and explicitly refuses
out-of-session text Undo. The native proof must reconstruct ownership from
canonical receipts after process teardown, preserve later peer/own contributions
and establish all-or-nothing mixed-action preflight. Current session behavior is
not accepted as a substitute. No claim of feasibility/completion yet.

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
- Generic purchase source keys are already represented as `{kind,key}` by
  FoodPurchaseLine/FoodPurchase; keep source identity independent of mutable
  receipt-line values. CLI planning/required revisions/planHash remain unbuilt.
- Set/register CLI/MCP cold-open/list and import coverage/budgets prospectively,
  without weakening existing mandatory GUI/store limits. No timing acceptance,
  benchmark controller request or CI dispatch has run for this release line.

The implementation owner retains lib/main.dart integration and the queued Food
row-selection/Move some scope. No GUI/CLI feature, packaged candidate, native
qualification, RC publication or stable promotion is claimed here.
