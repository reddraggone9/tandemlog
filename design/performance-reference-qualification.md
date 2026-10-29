# Controlled reference qualification — operating protocol

Implements [ADR0033](decisions/0033-controlled-reference-performance.md). No
hardware multiplier;`limits-v1.json` SHA256 remains
`fb8dd13ad2a89bbce0b3e340b4fd3b4270a459684df1dbb87a1a2b6777501f32`.
The implementation is not qualified until host/controller registration,a fresh
reference receipt and exact-source hosted CI all pass. Do not promote old samples.

## Required roles

- Hosted Linux/Windows/Android correctness/build/native checks remain required.
  Hosted AOT uses `--hosted-advisory`,strict physical caps and all254metrics across
  all3shapes. Correctness,replay,integrity,coverage,source/tool/fixture drift,
  invalid growth contracts and incomplete child cleanup remain fatal. Only timing
  comparisons become advisory;every raw miss/log remains. No timing retry.
- Controlled Farnsworth runs the **same** uninstrumented enforcing harness,without
  measure-only/advisory/diagnostic flags. Both absolute and both growth-rule sets
  must pass with existing2warmups/5samples. The original at-most-one externally
  justified full-suite timing retry is preserved,never retry-until-pass.
  Separately,a failed qualification may receive the single
  [official rerun](#official-rerun-after-non-reproduction) below.
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
controller with the reviewed held-worker completion protocol and admission-ordering corrections is registered by SHA256
`0174e5cb313275afa671292ec2a71411c1a0f69d021afa6a188e72c70125d4d3`.
For the Food-products244-label inventory,the controller differs from R7 only in its hard-coded limits digest (now the registered894f3af1…);existing232-label action budgets and all lifetime/resource controls remain unchanged. The old controller/request remain retained and were never launched.
The combined Food Move some + Agent CLI254-label inventory (2026-10-29) changes the limits digest again (now fb8dd13a…, superseding the branch-local e1187303… and31c41229…);the registered controller's hard-coded digest must be re-registered before any qualification of that inventory. Existing244-label budgets are unchanged.
Its adjacent pressure module remains SHA256
`f67076216c21ae898dd0728132bbbfe388af307b8734c056f0ab5d05b7797e10`.
The source and original host fault evidence were reviewed privately;registration
publishes only the required hash,not the private controller source or bundle.
Unknown/pending registration or material drift fails. Do not merely rename a host.

2026-10-27 library re-registration (2026.10.8 line): `libtandemlog_text.so`
`c9b95cae…` (pinned Rust 1.99.0, locked offline build from a clean checkout of
`b6c54c7`, reproduced byte-identically) and `libsqlite3.so` `d3d1eac2…` (sqlite3
3.8.0 hook asset, SQLite 3.54.1, hash-verified), with the lockfile and compiled
dependency inventory taken from a non-qualifying measure-only run of that source
under the reference caps. Host, controller, caps, package contract and limits are
unchanged. Earlier receipts keep their original pins.

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

The later terminal-evidence correction preserves terminal status before cgroup
reads,refuses collected-unit defaults and missing final counters,and queries
inactivity before trying to stop an unloaded unit. It preserves the same lifetime,
pressure and deadline controls. Private review verified45host controls and six
synthetic manager/terminal fault cases;no performance qualification follows from
these controls. Registration replaces the expected controller hash only:it does
not install host files,create another request,reuse a consumed request or authorize
another invocation. Private source/raw evidence remain outside the public repo.

The R7 registration follows an independently reviewed actual four-case proof:
normal success, original exit7 with captured counters, normal exit0 without
capture, and exact manager SIGKILL with a TERM-resistant descendant. All106
current-source host controls passed without skips. Descendants were contained
in19.118s; independent original-clock cleanup completed in150.344s of the240s
synthetic-proof bound. [Sanitized registration evidence](../evidence/rc4-cloud-attribution-20261024/reference-controller-r7-proof.json)
publishes hashes and outcomes only. Private controller source and raw host
artifacts remain private; prior failed controls/qualification remain retained.
These synthetic cases validate the controller,not actual benchmark acceptance.

The real workload completes its source/report/child checks,then remains alive
at the explicit work-complete/pre-exit boundary. The manager reads actual live
cgroup counters and publishes a hash-bound ACK; the original worker verifies it
and exits normally. Captured counters do not substitute for original normal exit
or independent post-exit unit/process/cgroup/deadline verification. Missing
capture/ACK,failed/collected/default status or missing cleanup refuses qualification.
Public verification now requires this boundary attestation and original group
absence for compile,generation and every measured attempt. A bounded reap wait
uses the original stage deadline; live/zombie residue is not ignored. A reaped
leader receives no additional group signal; a live unreaped leader must match
its original PID/start/session before owned cleanup.

The controller fingerprints the existing invocation before the driver creates
its fresh run directory,and verifies the created output's exact mount identity
without symlink traversal before completion. Pre-admission blank loaded/dead
status is pending under the original10s admission deadline; a cgroup alone does
not prove a running process. Real failed starts and observed exits still retain
their original status and cannot waive counter requirements.

The existing management route must start the nonce manager with
`systemd-run --wait --pipe --service-type=exec`,the manager settings
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

### Relevant-source identity schemes

Source inventories read literal Git blobs through one `cat-file --batch` process
per identity check,requesting each distinct object ID once even when paths share
content. The verifier checks ordered object IDs,blob type,size,content hash and
exact framing/completeness;duplicate inventory paths or protocol responses fail.
Worktree dirty/untracked,regular-file and literal-byte checks remain unchanged.
This transport does not change either identity scheme or receipt bytes.

The request records its identity scheme inside `relevantSource`,so the nine
controller fields are unchanged. A receipt is always verified under the scheme it
recorded;old receipts are never reinterpreted.

- `relevant-source-v1` (no `scheme` field):every relevant file's literal bytes.
  All receipts issued before this change,including the stable101 owner override,
  are v1 and keep exactly that meaning.
- `relevant-source-v2` (`scheme: relevant-source-v2`,issued by `request` from
  now on):the same files,except that two release-version carriers are pinned
  version-free and marked `normalized`:
  - `pubspec.yaml`:only a single top-level `version: <value>` line
    (`[0-9A-Za-z.+~-]`,no comment) is replaced. Any other byte,dependency,flag,
    comment or a second/malformed version line changes the identity;
  - `packaging/linux/com.reddraggone9.tandemlog.metainfo.xml`:only one
    `<releases>` list made solely of `<release version date type/>` entries
    (stable/development) is dropped. Anything else in the file,or any other
    release markup,changes the identity.

  Neither value reaches the benchmark:`lib/` does not read the version and the
  metainfo is not compiled. A stable rename of an already qualified RC (`version:`
  change plus the matching AppStream release list that
  `test_linux_flatpak_metadata.py` requires) therefore keeps its qualification.
  The verifier still requires the result's pubspec pin/seal to equal the literal
  bytes at the request's own revision. Actual history:RC.5 `be93df2`,stable
  `d494d9b` and `dfb2260` have three v1 identities and one v2 identity.

An official rerun must use the failed request's scheme,because the identities must
be equal.

## Official rerun after non-reproduction

Lee approved this rule on2026-10-26. A repeatable failure is a real performance
problem:profile it in separate diagnostic runs,fix the cause and qualify the
changed source with a fresh request. An isolated failure that diagnostics cannot
reproduce may instead receive **exactly one** official rerun of the unchanged
relevant source. Budgets,limits,coverage and the in-invocation noise retry are
unchanged. A failed rerun counts as repeatable;there is no third qualification
of that identity,except that a [borderline result](#borderline-result-on-already-qualified-source)
of an identity that already passed is not a regression. Never rerun unchanged
source merely to obtain a green result.

Eligibility is enforced by `reference_receipt.py`,not by an ad-hoc exception:

- The prior result must be an enforcing,uninstrumented qualification bound to its
  request and the same relevant source identity,which failed only on timing
  limits (`error` is the timing-limit refusal;every attempt completed with exit0
  and only `passed`/`timing-failed` statuses). Correctness,coverage,execution,
  binding,measure-only,advisory or diagnostic results are not rerunnable.
- A prior request that is itself an official rerun is refused (limit1).
- A recorded diagnostic (`reference-failure-diagnostic-v1`) must name the prior
  request and source identity,contain at least one `role: diagnostic`,
  `qualifying: false` run with its result hash,check **every** prior failing
  label (absolute `size:action` and growth `comparison:scaling:action`) and
  reproduce none. Runs must start after the failed qualification finished;the
  record must precede the rerun request. Profiling and tracing belong only there.

Issue an ordinary fresh request first,then authorize it beside the request:

```bash
python3 tool/performance/reference_receipt.py authorize-rerun \
  --repo "$qualification_source" --request "$rerun_request" \
  --rerun-of-request "$failed_request" --rerun-of-result "$failed_run/gate-result.json" \
  --diagnostic "$diagnostic_record"
```

The request keeps exactly the nine fields the registered controller accepts;an
earlier draft embedded the authorization inside the request and the controller
correctly refused it before admission. `authorize-rerun` writes
`$rerun_request.official-rerun.json`,binding the rerun request hash,the prior
request,prior result hash,prior failing labels and the diagnostic record
(ordinal2). It refuses when the failed request already has such a file:that
failure was itself the official rerun and is repeatable. Seal with
`--rerun-authorization "$rerun_request.official-rerun.json" --prior-result
"$failed_run/gate-result.json"`;the bundle carries `official-rerun.json` and
`prior-gate-result.json`,and the verifier recomputes eligibility. A first
qualification bundle cannot carry a prior result. The local executor remains the
trust boundary for presenting the failure:the original failed run,its logs and
the diagnostic outputs stay retained.

## Disk-stall resample

Lee approved this rule on2026-10-28 21:37 CDT as a standing rule. Farnsworth's
durable appends occasionally stall for tens of milliseconds off-CPU (RC.2 q1:
`dense-food:food.product.merge.undo` 25.494ms against 20ms,17.573ms of it
append,7.483ms CPU). Such a miss measures the disk,not the action.

`run_gate.py` applies it inside the enforcing reference invocation only
(`--reference-request`);hosted,measure-only and diagnostic runs never resample.
After an attempt's three sizes and both comparisons are evaluated, it reads the
per-sample `appendMicroseconds` and `cgroup.usage_usec` the benchmark already
logs,and when every missed label is attributed (see
[the rule](performance-gate.md)) runs `benchmark resample OUTPUT NATIVE MANIFEST
FAMILY` once per attributed label,under the same binary,fixture,limits and
binding checks and the same 600s child bound. The resample log
`disk-stall-resample-ATTEMPT-ORDINAL.log` is sealed in the bundle beside the
attempt logs. The extra child fits within the controller's original deadline; no
controller,request or budget changes.

A resample that misses again is an ordinary failure: the result keeps the usual
timing refusal,its failing labels are the post-resample labels,and the existing
[official rerun](#official-rerun-after-non-reproduction) and borderline rules
apply to it as to any other failure. A label never gets a second resample,
including in an in-invocation noise retry.

`verify`/`seal` recompute attribution from the recorded numbers,check those
numbers against the attempt log,check the replacement samples against the
resample log,and recompute every decision from original plus replacement samples.
Each resample records the hash of the fixture manifest it ran on,which must be
its label's sealed fixture,and its log's completion counts must match that
fixture's contract. Borderline classification,official-rerun labels and owner
overrides all judge the post-resample decision,never the replaced samples,and
borderline bundles carry the resample logs.

## Borderline result on already qualified source

Lee approved this rule on2026-10-27 14:56 CDT and extended it to absolute misses
on2026-10-28. When IDENTICAL relevant source
(same relevant-source identity,under the scheme its requests recorded) already
passed a qualifying check,a timing failure within normal run-to-run variation is
a borderline limit,not a regression:it does not block the release and is queued
for a look at the limit or the scaling behind it. For exactly this case it
replaces the "failed rerun is repeatable" conclusion;the official-rerun rule
above stays for every other failure. Budgets,limits and coverage are unchanged.

`tool/performance/borderline.py` encodes it;`gate_policy.classify_borderline`
is the verdict. `borderline-accepted` requires ALL of:

- `evidence/reference-performance/current/` verifies as an ordinary passing
  qualification of the current relevant source (missing/stale fails);
- the failed request is a different request with the identical recorded
  `relevantSource`,current host profile,an ancestor revision,and was issued
  after that passing result finished;
- the failed result is the original enforcing timing-limit refusal with no
  in-invocation retry,and every pin,seal,import closure,toolchain,fixture
  contract,absolute/growth evaluation,binding,log and failed-workload cleanup
  recomputes from retained bytes (the same checks as the owner override). Any
  correctness,coverage,replay/integrity or execution failure refuses;
- every timing miss,absolute or history-growth,has its median and/or maximum
  at most `BORDERLINE_VARIATION_BAND` (5%) over its unchanged bound. Absolute
  misses use the size-specific action budget;growth misses use the paired
  large-size bound. This includes mixed absolute/growth misses:one miss beyond
  the band makes the whole result an ordinary failure. No timing budget changes.

The band is a declared constant,not a computed tolerance. The q9/q10/q11 runs
measured the same `sync.peerTask.whileFood.storageAdmission` growth at
99.8%/96.3%/101.6% of its bound on identical product code,a5.3-point spread.
Recomputed under this rule,q11 is borderline (101.6%) and q10 is an ordinary
failure (`explicitTask.title.undo` maximum at145.5% of bound). Changing the band
requires Lee's approval,like any limit change.

Seal the failed run with the passing qualification already committed:

```bash
python3 tool/performance/borderline.py seal --repo "$checkout" \
  --request "$failed_request" --run "$failed_run" --cleanup "$failed_cleanup" \
  --output "$checkout/evidence/reference-performance/borderline"
```

An official rerun adds `--rerun-authorization`/`--prior-result`,which are verified
as above. Seal refuses (and leaves no bundle) unless the verdict is
`borderline-accepted`. `borderline.json` records the verdict,both request/result
hashes,unchanged limits,the band,each borderline metric (label,statistic,
measured,bound,ratio) and `followUp:{status:queued,...}`. When the directory
exists,`reference_receipt.py verify` checks it together with the passing
qualification,reports `QUALIFIED_WITH_BORDERLINE_FOLLOW_UP_QUEUED` and emits a CI
warning naming each metric;a borderline bundle that does not verify fails the
check. Queue the follow-up in the release work list. When `current/` is replaced
by a qualification of other source,remove the old borderline bundle in the same
commit.

## Release-owner override — stable 2026.10.7+101 only

The q10 qualification of `dfb2260` failed one task-own-history growth timing;its
single official rerun q11 failed a different one
(`sync.peerTask.whileFood.storageAdmission` large median 27.997ms > bound
27.5675ms). Under the rule above that is a repeatable failure. Lee, as release
owner, accepted `dfb2260` for stable 2026.10.7+101 on 2026-10-27 14:56 CDT
despite it. **The qualification remains failed**;budgets,limits,coverage and
the rerun limit are unchanged,and nothing is relabelled passed.

`evidence/reference-performance/owner-override-stable101/` retains the q11
request,official-rerun authorization,q10 prior result,raw q11 result,logs,
fixture manifests and failed-workload cleanup,plus `override.json`. When that
directory exists,`reference_receipt.py verify` runs `owner_override.py`
instead of the qualification verifier and reports
`OWNER_OVERRIDE_ACCEPTED_NOT_QUALIFIED` with `referencePerformanceQualified:false`
and a CI warning. It refuses unless:

- `pubspec.yaml` is exactly `2026.10.7+101`,`dfb2260` is an ancestor and the
  q11 request's relevant source equals `dfb2260`'s committed identity;
- current relevant source equals that identity except the three reviewed policy
  files,whose exact bytes/modes `override.json` pins (no removals);
- the retained result is bound to the request,in its original failure state
  (`correctnessAccepted:false`,no success flags,timing-limit error) and every
  pin,seal,import,toolchain,fixture contract,absolute evaluation,growth
  evaluation,binding and log is recomputed from retained bytes;all executions
  exited0 with groups absent;retry was ineligible;
- the recomputed failure set and measurements equal exactly the owner-accepted
  label,the q11 rerun authorization recomputes from the retained q10 failure,
  and cleanup differs from success only by the failed-workload capture refusal.

Any other version,product/tool byte,mode,failure,fixture or correctness change
refuses. Future releases need a fresh passing qualification;the override is not
a precedent. It accepts no native-visible,signing,candidate,release or live gate.

`verify` routes to the override only while `pubspec.yaml` is exactly that release;
at any other version the directory is retained history and the ordinary verifier
(plus any borderline bundle) runs. The override stays v1-identity bound. The
borderline rule now covers this kind of case without an owner exception:under
identity v2,q9's pass covers `dfb2260`,and q11 recomputes as borderline.

## Release-owner override — prerelease 2026.10.9-rc.1+104 only

The q4 qualification of `634cd9c` (request `ed8ff0a6`) failed three timing
maxima: dense-food `food.product.edit.undo` (21.763ms > 20ms) and the
food-own-history growth maxima for `food.product.edit.undo` and
`task.complete.checklistConfirm` (54.2ms > 48.0ms). Two measure-only diagnostics
did not reproduce them, so its single official rerun q5 (request `1f0dd03d`) ran
and failed a different label: food-own-history growth maximum for
`food.details.1` (15.363ms > 11.5674ms; median within bound). Under the rerun rule
that is a repeatable failure. Separate profiling attributed every failing sample
to one durable append whose fsync coincided with a ~10ms NVMe preflush+FUA
journal-commit outlier, with normal CPU time; a source-free fsync probe on the
same filesystem showed the same outliers at the same rate. Lee, as release owner,
accepted `634cd9c` for this prerelease only on 2026-10-28 16:14 CDT. **Both
qualifications remain failed**;budgets,limits,coverage and the rerun limit are
unchanged.

`evidence/reference-performance/owner-override-food-rc1/` retains the q5 request,
official-rerun authorization,q4 prior result,raw q5 result,logs,fixture
manifests and failed-workload cleanup,plus `override.json`. It uses the same
verifier as stable101 (`FOOD_RC1_POLICY` in `owner_override.py`),bound to the
request's recorded `relevant-source-v2` identity;the permitted delta is the same
three reviewed policy files plus `.gitattributes`,which only keeps the frozen
`test/fixtures/food-products/` operations literal in Windows checkouts (their
SHA-256 pin failed under autocrlf in CI 40771007898). `verify` routes to it only while `pubspec.yaml` is
exactly `2026.10.9-rc.1+104`. It is not a precedent and accepts no native-visible,
signing,candidate,release or live gate. The I/O-attribution gate rule proposed by
the profiling report is a separate change needing Lee's approval.

## Existing manager payload — no wrapper ownership change

Launch **only inside** the existing manager's bounded unprivileged workload unit,
using its curated environment and the actual Dart SDK binary:

```bash
/usr/bin/python3 "$qualification_source/tool/performance/run_gate.py" \
  --repo "$qualification_source" --dart "$reviewed_dart" \
  --native-library "$reviewed_native" --sqlite-library "$reviewed_sqlite" \
  --expected-limits-sha256 fb8dd13ad2a89bbce0b3e340b4fd3b4270a459684df1dbb87a1a2b6777501f32 \
  --reference-request "$qualification_request" --output "$qualification_run"
```

No `--measure-only`,`--hosted-advisory` or `--diagnose-costs`. Do not set SQLite
LD_PRELOAD on the manager/shell;the driver applies it to actual Dart/AOT children.
The fresh output must not exist. All3shapes retain identical current state and
initial prefixes,their module-specific history growth,all254labels,2warmups/5samples,
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
