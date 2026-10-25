# Controlled reference qualification — operating protocol

Implements [ADR0033](decisions/0033-controlled-reference-performance.md). No
hardware multiplier;`limits-v1.json` SHA256 remains
`50a606cb302eb6a769c760188901132fb8b35b153ecc41dde11a17c95b39742e`.
The implementation is not qualified until host/controller registration,a fresh
reference receipt and exact-source hosted CI all pass. Do not promote old samples.

## Required roles

- Hosted Linux/Windows/Android correctness/build/native checks remain required.
  Hosted AOT uses `--hosted-advisory`,strict physical caps and all232metrics across
  all3shapes. Correctness,replay,integrity,coverage,source/tool/fixture drift,
  invalid growth contracts and incomplete child cleanup remain fatal. Only timing
  comparisons become advisory;every raw miss/log remains. No timing retry.
- Controlled Farnsworth runs the **same** uninstrumented enforcing harness,without
  measure-only/advisory/diagnostic flags. Both absolute and both growth-rule sets
  must pass with existing2warmups/5samples. The original at-most-one externally
  justified full-suite timing retry is preserved,never retry-until-pass.
- Hosted `reference-performance` independently verifies the committed bundle.
  Missing or stale data fails;passing hosted timing never substitutes for it.
  `releaseGateAccepted` in the standalone result means only its AOT scope,not
  owner-signed/native-visible/release/live acceptance.

## One-shot execution authority and registration

Parent coordinates the existing authorized local executor. Use the existing
reviewed manager/unprivileged lab route and corrected pressure controller. No
new persistent runner,network listener,SSH key,sudo rule,service or security/power
change is implied. Cloud is the sole repository writer;local source is immutable.

`tool/performance/reference-host-v1.json` registers the reported i5-12600KF,
x86_64,kernel7.2.11-arch1-1,16logical CPUs,Python3.14.8 and ext4 measurement path,
plus exact SDK/native/SQLite/dependency/lock/limits pins. The registration came
from the parent's read-only collection,not a cloud host probe. The reviewed
controller revision2 is registered by SHA256
`937e002fcee5a3f54786999f3956b3b0412afc27c22f4d5fb986c5367191ff0b`.
Its adjacent pressure module remains SHA256
`f67076216c21ae898dd0728132bbbfe388af307b8734c056f0ab5d05b7797e10`.
The source and original host fault evidence were reviewed privately;registration
publishes only the required hash,not the private controller source or bundle.
Unknown/pending registration or material drift fails. Do not merely rename a host.

Keep the reviewed controller bytes stable across candidates:read the exact
source/nonce from the reviewed per-run request and verify them,with fixed bounds
in code. Do not embed the forthcoming Git commit inside controller source:the
profile itself pins that controller hash,which would otherwise create a circular
commit/hash dependency. This is one existing-manager adapter,not a request daemon
or permission to accept jobs from untrusted callers.

The per-request manager adaptation must preserve:

| Control | Required |
| --- | --- |
| Ownership | existing verified lab UID/GID1002,unique transient manager/workload units |
| Memory / swap / CPU / pids | 6GiB /0 /200% /128 |
| Manager settings | RuntimeMax1500s,TimeoutStop1s,StartLimitBurst1,StartLimitIntervalinfinity,Restartno,KillModecontrol-group,OOMPolicykill |
| Workload settings | RuntimeMax1500s,TimeoutStop19s,Restartno,KillModecontrol-group,OOMPolicykill;BindsTo+After exact nonce manager |
| Outer qualification bound | **one invocation,25minutes from PID1 manager activation**,plus one shared20s termination cleanup (19s workload+1s manager);no external retry/extension |
| Pressure | corrected ARC-aware stable preflight and genuine-pressure checks;global swap allocation alone is not swapping proof |
| Concurrency | no emulator,app,other benchmark or build/test load;never kill unrelated work |
| Cleanup | unconditional exact-unit stop/query,MainPID0,owned processes absent;preserve timeout/errors |

The invocation may contain the existing eligible full-suite noise retry within
that25minute bound. If it cannot finish,the result fails and is retained. Future
execution is coordinated through parent after tooling/registration review;these
commands do not launch anything on their own. No foreground window is needed.

Revision1 was not registered:its independent workload could survive abrupt
manager death. Revision2 binds the workload lifetime to the exact manager and
prevents restart,with a deadline anchored to PID1 activation and one shared
19+1second stop window. Privately reviewed synthetic PID1 fault evidence covers
SIGKILL with a stubborn workload,manager timeout and accepted-but-unobserved
launch;all six owned units ended inactive/failed with MainPID0 and empty/absent
cgroups. This establishes those lifecycle cases,not actual root-controller plus
benchmark integration or performance acceptance. Missing invocation/result,
counters,cleanup or deadline evidence still refuses qualification.

The existing management route must start the nonce manager with
`systemd-run --wait --pipe --collect --service-type=exec`,the manager settings
above,and a clean environment running `/usr/bin/python3 -I -B` on the privately
reviewed controller. Keep the existing supervised10second heartbeat stream open;
EOF or35seconds without valid heartbeat cancels. Do not use a finite stdin pipe.
After the manager exits,invoke its `finalize` mode separately through existing
management access,with the same six path arguments and a finite timeout fitting
the **original** activation+1520second deadline. Finalize can only read status and
write evidence;it cannot launch units. Do not overwrite a failed finalization,
reuse a claimed request or restart an uncertain invocation.

## Fresh request and immutable inputs

Prepare a detached clean checkout at the requested policy/source commit using
the existing reviewed SDK/locked packages. Controller,request and outputs stay
outside the immutable measured tree. No user workspace/profile/import argument
exists;the harness generates its public synthetic data once and seals it.

Use exact Dart3.13.4/gen_snapshot,reviewed native text/SQLite binaries and the
registered dependency inventory/package-language contract. Existing034a native
artifacts may be reused for this policy-only change because native/runtime source
has not changed;future native/dependency changes require new provenance review
and registration. Do not modify binaries or package roots to get a pass.

After the parent has reviewed the bounded controller adaptation and its hash:

```bash
python3 tool/performance/reference_receipt.py request \
  --repo "$qualification_source" --controller "$reviewed_controller" \
  --output "$qualification_request"
```

The request binds a fresh nonce/UTC time,exact source commit and all relevant
tracked file bytes/modes,host-profile hash and controller path/hash. Dirty,
untracked or nonliteral relevant source is refused. The actual controller bytes,
environment,caps and source/request pins are rechecked during measurement.
Receipt/docs-only descendants remain valid only when the complete relevant
identity is unchanged and the request commit is an ancestor. Changing runtime,
tests,assets,workflow,gate tooling,host registration or limits requires a fresh
request/run. No generic branch-name or age-only freshness shortcut exists.

## Existing manager payload — no wrapper ownership change

Launch **only inside** the existing manager's bounded unprivileged workload unit,
using its curated environment and the actual Dart SDK binary:

```bash
/usr/bin/python3 "$qualification_source/tool/performance/run_gate.py" \
  --repo "$qualification_source" --dart "$reviewed_dart" \
  --native-library "$reviewed_native" --sqlite-library "$reviewed_sqlite" \
  --expected-limits-sha256 50a606cb302eb6a769c760188901132fb8b35b153ecc41dde11a17c95b39742e \
  --reference-request "$qualification_request" --output "$qualification_run"
```

No `--measure-only`,`--hosted-advisory` or `--diagnose-costs`. Do not set SQLite
LD_PRELOAD on the manager/shell;the driver applies it to actual Dart/AOT children.
The fresh output must not exist. All3shapes retain identical current state and
initial prefixes,their module-specific history growth,all232labels,2warmups/5samples,
first-use fixtures and complete replay/prefix/native-owner assertions. Failures
remain raw data. No per-action rerun or discarded outlier.

## Cleanup adapter and export

After the actual controller has stopped/queried its owned units and processes,
the local executor maps its original verified receipts into `cleanup.json`:

```json
{
  "requestId": "EXACT_REQUEST_NONCE",
  "controllerSHA256": "EXACT_REGISTERED_REVIEWED_CONTROLLER_HASH",
  "ownedUnitsInactive": true,
  "ownedProcessesAbsent": true,
  "inputPinsUnchanged": true,
  "withinDeadline": true,
  "activeProcesses": 0,
  "workloadSwapBytes": 0,
  "oomKills": 0,
  "completedAtUTC": "ACTUAL_UTC",
  "deadlineUTC": "ORIGINAL_ACTUAL_UTC",
  "errors": []
}
```

These fields must come from actual manager/process/cgroup/pressure readbacks,
not assertions filled by hand to satisfy a parser. Preserve the original
controller logs and failed/uncertain cleanup. Mapping uses the existing verified
manager controls;it must not suppress a stop/query error or relaunch uncertain work.

Only after cleanup,separately from the stopped manager,seal a fresh bundle:

```bash
python3 "$qualification_source/tool/performance/reference_receipt.py" seal \
  --repo "$qualification_source" --request "$qualification_request" \
  --run "$qualification_run" --cleanup "$qualification_cleanup" \
  --output "$qualification_bundle"
```

The exporter rechecks the executable hash/execute bit and all actual generated
canonical fixture bytes,then retains the request,complete report,compile/generation/
attempt logs,fixture manifests,cleanup and exact member hashes. It does not export
personal data or the executable/canonical workspaces. Original raw run output stays
with the local executor. Partial/failed export remains evidence,not qualification.

Parent/reviewer examines the original manager/result evidence and the sealed
public-synthetic metadata/logs through the existing route. Cloud independently
verifies the bundle before committing it at
`evidence/reference-performance/current/`;that evidence-only commit preserves the
relevant identity. No unauthenticated `passed:true` file substitutes for the
authorized executor and review. This is an explicit trusted-executor attestation,
not a claim that a hash proves physical execution;no new signing key is needed.

## Hosted consumption and Vex cutover

```bash
python3 tool/performance/reference_receipt.py verify --repo "$checkout"
```

The required read-only job verifies request/commit ancestry/current identity,
host/controller/SDK/dependencies/package roots/seals/import closure,caps,all input
and log hashes,each registered sample/order/summary,both growth contracts/limits,
any retry's original noise eligibility,and complete cleanup. Historical,
advisory,instrumented,missing,mismatched,incomplete or over-budget results fail.
Documentation changes cannot rewrite original failed statuses.

Run one exact relevant-source CI after fresh qualification is committed;do not
dispatch duplicate CI while the local run is pending. All ordinary platform/
correctness jobs remain hosted. If source changes while qualification/CI runs,
retain the old evidence and prepare the next genuine source-bound request.

For Vex: fetch the pushed checkpoint,read the current request/profile/receipt and
verify them before relying on a pass. Missing qualification means blocked,not
permission to disable the job or reuse the old3measure-only passes. Coordinate
one product writer and owned process cleanup. Hard cloud stop-write remains
Oct26 13:00UTC;explicit ownership handoff is separate. Foreground/native-visible,
physical-device,signing/candidate/editorial/release/live-cutover gates remain open
under their existing qualifications. The policy transition authorizes none of
those operations or new persistent infrastructure.
