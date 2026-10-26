# ADR0033 — controlled reference performance, mandatory hosted correctness

Status: **accepted by Lee2026-10-25; implementation/qualification in progress**.
Supersedes ADR0032's gate placement only. Its budgets,action/history coverage,
correctness,source/fixture seals and bounded noise-retry policy remain unchanged.

## Context and decision

The identical AOT executable/source/dependencies/fixtures/caps produced179absolute
and105paired misses on one hosted run versus5/3on another. Three fixed current-source
Farnsworth observations were reported0/0;they were measure-only evidence,not an
enforcing pass. Cross-operation median scales and maximum tails do not support
one reliable hardware multiplier. See the [retained normalization analysis](../../evidence/rc4-cloud-attribution-20261024/hosted-normalization-analysis.md).

Lee approved the clarified separation: hosted correctness/build/replay/integrity/
source/fixture/completeness remain mandatory; raw hosted timings are advisory;
unchanged absolute **and both history-growth** budgets qualify on controlled
Farnsworth. No hardware multipliers or time normalization. Lee's approval was:
“Sounds reasonable. Please continue forward like that, then.”

The hosted AOT job still runs every registered case/shape and rejects structural,
correctness,binding,resource and incomplete results. It records every timing miss
without retrying for green. It is not blanket continue-on-error. A separate required
reference-receipt check fails closed when source-bound qualification is missing,
stale,mismatched,incomplete,incorrect or over either absolute/growth limit.

The reference uses the existing bounded one-shot manager route,not a persistent
GitHub runner/service,listener,new credential or changed host security setting.
Policy approval alone grants no such infrastructure permission. Its registered
hardware/kernel/Python/filesystem,controller,toolchain/native/SQLite/dependency
and resource receipts are explicit. Material drift requires reviewed registration,
never a multiplier or automatic recalibration.

## Evidence and authority boundary

Qualification is a fresh uninstrumented enforcing run for the exact relevant
source identity;measure-only or old hosted failures cannot be re-labelled. Source
identity covers all tracked inputs except design/evidence and root README/AGENTS,
including runtime/build/gate/test/native/assets/configuration. Receipt-only/docs
successors may preserve that identity;code/configuration changes invalidate it.

The existing authorized local executor remains the explicit execution/cleanup
trust boundary. A source-controlled request,raw result/log/fixture manifests,
final binary/fixture export proof and actual manager cleanup receipt are reviewed
before committing the qualification bundle. The hosted verifier checks their
bindings and independently recomputes every action/growth result;it does not
pretend cryptography proves that a physical host executed a benchmark. A random
uploaded `passed:true` file is not sufficient. No new signing key is introduced.

This transition is **prospective**. CI40167598688's5/3and all earlier failed/aborted
attempts keep their original status. Earlier reference0/0samples remain diagnostic.
Hosted timings,reference storage/application latency,native framework observations
and OS-input/presentation acceptance remain different evidence. No release or
live adoption is authorized by this decision.

## Implementation and review triggers

Reuse `run_gate.py`,activated limits and production harness. Add explicit hosted
advisory mode,strict source-bound reference receipts and a read-only hosted verifier.
Keep every platform/correctness job and original raw attempt retention. Missing
host registration or qualification blocks the reference check. See the
[operating protocol](../performance-reference-qualification.md).

Revisit on material host/toolchain/dependency/source change,repeated qualified
misses,coverage change or measured cost demonstrating a genuine product tradeoff.
Only Lee may approve looser existing limits. Native full-action acceptance and
all signing/candidate/editorial/release/live gates remain separate.

## Amendment 2026-10-26 — official rerun after non-reproduction

Accepted by Lee 2026-10-26 17:00. A repeatable qualification failure is a real
problem: profile it only in separate diagnostic runs, fix the cause and qualify
the changed source. An isolated failure that diagnostics cannot reproduce may
receive exactly one official rerun of the unchanged relevant source.
`reference_receipt.py` refuses the rerun request unless the prior result is an
enforcing timing-only failure of the same identity, the prior request is not
itself a rerun, and a recorded `role: diagnostic`, `qualifying: false` record
covers every prior failing label, reproduces none and falls between the failure
and the rerun request. The request itself stays in the registered controller's
field contract; a request-bound authorization file beside it, and the prior failed
result, enter the bundle and the hosted verifier recomputes eligibility. Budgets and limits are unchanged; the original
failure and diagnostics stay retained. Alternatives rejected: unlimited reruns
(retry-until-green), and requiring a source change for every unreproducible spike
(forces meaningless churn). Revisit if official reruns become frequent, which
would indicate a host-control problem rather than isolated noise. Details:
[operating protocol](../performance-reference-qualification.md#official-rerun-after-non-reproduction).
