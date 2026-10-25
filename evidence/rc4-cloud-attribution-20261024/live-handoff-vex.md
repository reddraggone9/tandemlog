# Tandemlog engineering handoff to Vex

**Snapshot: 2026-10-24 22:28 UTC. Pre-cutover; cloud remains the product writer.**
Lee authorized assistance to Vex during the transfer. No cutover has occurred.
This snapshot deliberately includes pending results; update it at final cutover.

## Continuation update —2026-10-25 01:37 UTC

Tested pending successor: canonical quoting allocates a StringBuffer only when an
actual escape is needed, retaining full surrogate validation and byte/hash rules.
Full1510 units PASS6m36s,171 tools PASS,analysis/format clean. Independent3,000
JSON cases plus malformed Unicode/frozen hashes pass; scratch30,000 original
encoder comparisons pass. Same-binary component AOT ~9%/21% faster, not a whole-
action/UI claim. Source-sealed full local AOT passes all3 shapes/232 correctness,
replay/prefix checks and every pin;7 absolute/8 paired failures remain,0 retries.
Food-growth has no local timing failures in this run. Required enforcing and
hardware acceptance remain pending. No current-source performance retry issued.

See `followup-canonical-quote-research.json`, `followup-canonical-quote-local-checks.json`,
`followup-canonical-quote-full-aot.json`, and matched prior hosted cost synthesis
`followup-owned-state-cost-analysis.md` / `followup-owned-state-failure-costs.json`.
Current source and failure evidence are being committed/pushed. CI40148192820 is
still in its bounded native step (deadline~01:53UTC); do not cancel it. Dispatch
ONE fresh exact-source CI after it terminates, calibration=false. A syscall-only
hosted diagnostic is prepared as a scratch plan, not implemented/dispatched:
`/workspace/scratch/rc4-hosted-io-diagnostic-plan.md`. Desktop media/replay complete;
no further polishing is active. Original188.15s capture retained;40.45s deliverable
removes observation pauses at unchanged action speed. All hardware qualifiers,
remaining Android acceptance, quota unknown and Monday13UTC cutoff remain.

## Continuation update —2026-10-25 01:17 UTC

Source remains30f8747 / exact CI5dc4e3e; current docs successor ce70697.
CI40148192820: Windows and Android PASS. Linux units/build/startup/package/install
PASS; native suite active since01:03:10UTC,50-minute cap (~01:53UTC). Performance
terminal FAIL: all3 shapes/232 metrics correctness PASS;60 absolute failures,
2 median misses (Task-growth warm.cacheRestore30.378ms/cap30; Food-growth add.1
43.973ms/cap15);45 paired failures,2 median misses;0 retries. CPU9V74 differs from
prior7763, so no controlled whole-run speed comparison. Verified artifact12582121521
SHA256 `a7cf7e85f10449fb2ff6db81c601a2db1ae2de985cb618865858ddd5d3cc9119`.
See `followup-owned-state-required-ci.json`; complete raw report remains in
`/workspace/scratch/rc4-owned-state-ci-40148192820`.

Actual exact5dc native Linux GTK desktop pointer/keyboard demonstration completed:
Save, dirty Undo/Cancel retains draft and enabled Undo with no canonical append,
Undo/Discard restores3tasks;exact2addedactions,prefixes and independent replay
PASS;normalexit0;all local processes stopped.40.45s video saved privately to
Library. `followup-owned-state-native-demo.json` preserves public-safe proof.
This is software-rendered Linux, not Windows/hardware timing; Android remains
pending. Fresh/warm CI closes exit0,183.519/78.393ms; no core; historical crash
remains unwaived. No production source edits since30f. Scratch-only canonical
quoting research passed30,000 old-oracle checks and improved isolated AOT median
~9% on synthetic envelopes/~21% short fields. No whole-action acceptance claimed.
Quota still unknown; cutoff and ownership constraints unchanged.

## Continuation update —2026-10-25 00:51 UTC

Cloud remains sole product writer; no cutover occurred. Stop-write cutoff is
2026-10-26 08:00 America/Chicago /13:00 UTC, or earlier actual exhaustion/access
loss. Account quota remains unknown; no supported status endpoint is exposed.

Tested product source: `30f874789933f749f11dfe6319aaf74799365d7f`. Current exact-source
[CI40148192820](https://github.com/reddraggone9/tandemlog/actions/runs/40148192820)
was dispatched once at2026-10-25 00:49:28UTC, calibration=false, on
`5dc4e3e398e63e7956312ddff258ac88b6465649`, an evidence-only successor with identical
application/test/tool/workflow inputs. The rejected patch is losslessly gzipped
because its blank unified-diff context markers tripped whitespace checks;
original bytes/SHA are preserved. Do not dispatch a same-branch duplicate while
this run is active. No other local build/test/profile command remains active.

The product repair adds NativeTextState.fromBytes: an owned immutable byte copy,
the same hard representational bounds/errors, and canonical Base64 generation
once. Seven SQL checkpoint sites no longer encode/decode/re-encode self-generated
strings. String inputs still use original strict parsing. All native pending,
limits, actor/context/ownership, byte/hash/receipt, queue, transaction, peer/tail
and rejected-Save continued-typing checks remain. No native ABI, persistence,
dependency, signing or performance-limit changes. Full1508 units pass6m38s;
analysis clean;395 files format0 changes. Same-binary constructor AOT is~2.9x
faster across256/1024/16384 bytes, not a whole-action/UI claim. Full local AOT
correctness/replay/prefix/seals pass all3 shapes/232 metrics;10 absolute and9
paired failures remain,0 retries. This is not enforcing or hardware acceptance.

Previous exacta71 [CI40143666264](https://github.com/reddraggone9/tandemlog/actions/runs/40143666264)
finished2026-10-25 00:34:11UTC. Linux/Windows/Android PASS, including all203 native
Linux cases in40m52s. The previously reproduced Session Undo/Discard failure now
passes the complete native suite. Overall CI FAILS performance:54 absolute
failures (42 median misses), both paired-growth comparisons PASS,0 eligible
retries. CPU EPYC7763 differs from baseline9V45; no controlled code speed or
regression comparison is claimed. Artifact12579904094 SHA256
`96a8ff41dcc9c37246dd1433476aec64eb6ccc3eda04aa8a787dc48744cfffa0`
is verified at `/workspace/scratch/rc4-food-id-ci-40143666264-refreshed`.
Its first prepared download link expired00:04:50UTC and returned403/0bytes;
one refresh after explicit expiry proof succeeded. No access blocker remains.

Botha71 normal-close processes exit0,927.927/76.767ms, no core. The intermittent
SIGSEGV remains UNWAIVED with no identifying stack. The CI post-fault collector
stays in place; clean runs do not diagnose it. Linux native log:
`/workspace/scratch/rc4-food-id-native-ci-40143666264/job.log`, SHA256
`5a38b4b0453156e5a1431681b790d1a293cb0d5a66f82d3aad50785336899fae`.
Close/bundle artifact12580365191 SHA256
`4ea74ff5c61fe293250e95fbb6cbbe9938a26cb07699d6b0d03ff137870ffdd8`,
verified at `/workspace/scratch/rc4-food-id-close-ci-40143666264`.

Availability memo/projection research was rejected after mixed matched timings.
The full uncommitted memo patch,6 tests and failed AOT (13 absolute/20 paired)
are preserved as evidence and are NOT product source. Do not reapply them as an
accepted repair. See `followup-readiness-rejected-experiments.json` and
`rejected-readiness-memo.patch.gz`. Current source retains neither variant.

Start with `followup-owned-state-analysis.md`, `followup-owned-state-codec.json`,
`followup-owned-state-full-aot.json`, `followup-owned-state-local-checks.json`,
and `followup-food-id-required-ci-terminal.json`. Current resumable cloud state
is `/workspace/scratch/rc4-cloud-checkpoint.json`. Configuration locations remain
`configuration-locations-vex.md`. No secrets or personal fixtures are published.

Remaining: finish the current enforcing run, investigate retained performance
misses within unchanged limits, retain any genuine close-crash stack, and finish
native UI/video/device acceptance. Cloud/Xvfb timing is not hardware Windows
presentation. Windows foreground remains held; coordinate native/device work
through the parent, with no new persistent access/services. No release/live
cutover or budget loosening is authorized. The22:28 snapshot below is historical.

## Checkout and conventions

- Repository/origin, fetch and push: `https://github.com/reddraggone9/tandemlog.git`.
- Development branch: `fix/rc4-task-latency-20261022`.
- Cloud checkout: `/workspace/tandemlog`. Product/code commit and verified remote head before this documentation: **`8005430e10be7b2af614565754779639301101f0`**. Working tree was clean; no uncommitted product patch remains.
- Read `AGENTS.md`, `design/README.md`, `design/status.md`, `design/task-latency-repair.md`, `design/performance-gate.md`, `design/runtime-qa.md`, and `design/releases.md`. Reinspect Farnsworth's local instructions/skills; no additional `.agents` skill was present in this cloud checkout/workspace.
- Flutter/Dart + SQLite disposable projections + canonical provider-independent JSON histories. Preserve normalized/v3 durable meaning, native ownership, shared profile queue, transactions, fresh peer observations, exact receipts and tail cleanup. Rejected Save must preserve continued typing. No bypass of correctness guards to improve timings.
- Normal development pushes are authorized. No release, live migration/cutover, personal fixture upload, signing change, paid runner/protection change, destructive history rewrite, or budget loosening is authorized here. Only Lee may approve looser performance limits. Before major features/releases obtain fresh quota: the 17:21 UTC banked reset is trusted history, but actual current quota remains **unverified**; no quota endpoint was exposed.

## Source transferred and repaired

Base: `2507e7161be822b0f8a4d7d57a46bbfcc19e5d83`. Farnsworth's source-only transfer was received and all five supplied blob hashes verified (`handoff-receipt.json`). Its local commit `efe24c400d6240784cd95425fa25a50a7a34caac` was not pushed; do not cherry-pick it onto the cloud branch and duplicate the changes. Preserve any Farnsworth local changes/refs before selecting the published branch.

Important pushed commits:

| Commit | Result |
|---|---|
| `c213ea98fce5cf8d43eddd2ab4144a001907ed47` | Immutable Task ID/effect-key representation reuse; earlier snapshot memo/sort repairs already included. |
| `c602178bc428625b92c11301ce83f5d0d57ab68e` | Sparse core allocation/hash accounting corrected; same 512MiB allocation bound and 60s debugger bound. |
| `6a0acddba036727b0b1c2519260dbb86295342f1` | Identical Task proof digest via direct UTF-8 JSON encoding, avoiding an intermediate string; actual-CI post-fault close capture. |
| `8005430e10be7b2af614565754779639301101f0` | Temporary placed-ID Set removes quadratic membership scans in pure order reconstruction; deferred moves, seed selection and fallback order unchanged. |

Earlier repairs keep the same live ordered/visible SQL query for Task tokens and reuse serialization only after exact row/order equality (4096 rows/4MiB bound). Unchanged Task sets skip redundant sorting only after exact canonical-set proof. No admission/freshness authority was cached. Opt-in diagnostics are error-transparent API wall intervals. Pinned SQLite3.7.0 omits `sqlite3_trace_v2`; the unsupported native statement callback was removed. Do not label wrapper API counts as engine statement/trigger counts or reintroduce that callback blindly.

## Active run and completed validation

**Latest completed run (no active local or CI command remains):** [CI40134281681](https://github.com/reddraggone9/tandemlog/actions/runs/40134281681), exact source **`6a0acdd`**, calibration=false. Linux job **`120992374942`** ran:

```sh
xvfb-run -a dbus-run-session -- flutter test integration_test/task_flow_test.dart -d linux --reporter expanded --timeout 120s
```

Native step started **21:41:00 UTC**, with a **50-minute bound** (approximately22:31 deadline). A previous passing203-case run took45m30s, so elapsed time alone is not a stall diagnosis. Available GitHub logs are final-only; live per-test progress is unavailable through the exposed API. Windows and Android passed. Linux already passed units/native/tools/build, actual startup/normal close, packaging and install/replace/uninstall. Its final native result is **202 passed/1 failed in40m24s**: `session Undo survives notices, protects drafts and preserves newer synced edits` could not find the Discard widget when tapping at `integration_test/task_flow_test.dart:4177`. Cause is not diagnosed; do not label it a harmless test flake. See `followup-native-session-undo-failure.json` and the full retained log `/workspace/scratch/rc4-proof-native-ci-40134281681/job.log`. This observed failure is not SIGSEGV.

The AOT job **`120992374813`** completed: all three shapes pass correctness/232 metrics, but **202 absolute checks and123 paired checks fail**, with **zero eligible retries**. The AMD EPYC9V74 host differs from earlier hosts; do not claim controlled whole-run improvement/regression. Preserve the failed results; no unchanged gate retry is authorized by the noise policy.

For **current8005430**: full local **1504 units pass in6m31s**,21 focused regressions,171 tools, clean analysis,394 files formatted with0 changes. Both existing checklist families on all three sealed shapes pass frozen-source correctness, full replay and canonical-prefix checks. A10,000-case scratch ordering differential and a committed1000-case old-oracle regression pass. **Fresh exact-commit CI for8005430 has not been dispatched**, while the older native result and handoff coordination were pending. No active local shell/build/test session, pending push, new automation or persistent service remains. Old completed session IDs are not running work.

## Performance and Linux close issues

Budgets remain SHA256 `50a606cb302eb6a769c760188901132fb8b35b153ecc41dde11a17c95b39742e`, with full action/first-use/Task-growth/Food-growth coverage and unchanged retry policy.

The6a hosted warm-total medians225.121/378.885/464.693ms and proof medians48.256/72.763/58.263ms fit their respective median budgets; a warm maximum and cold-start checks still fail. Numerous action tails remain: read-only editor open216.208ms with4.762ms bracketed CPU; one combined append interval385.644ms. Combined append is not fsync-only service time, CPU brackets are not exclusive partitions, and aggregate external pressure does not prove every slow sample's cause.

Local syscall control traced only fsync/fdatasync (no SQL/write buffers), passed all three correctness/replay checks, and observed123 calls: maximum4.954ms (SQLite WAL), canonical-log maximum1.794ms. It did not reproduce hosted tails. Syscall wall includes scheduling/tracing. Native-I/O versus scheduling attribution remains unresolved; no unavoidable product tradeoff is established. A separate hosted syscall diagnostic was proposed, **but no workflow/script was implemented or dispatched** before the handoff request.

Earlier exact CI runs [40124976992](https://github.com/reddraggone9/tandemlog/actions/runs/40124976992) and [40129495617](https://github.com/reddraggone9/tandemlog/actions/runs/40129495617) failed normal Linux close with SIGSEGV. Full-prefix original-source capture [40130625113](https://github.com/reddraggone9/tandemlog/actions/runs/40130625113) reproduced it, but its first collector rejected sparse logical size before GDB; that raw core was not uploaded and the ephemeral runner is gone. No identifying stack exists. Corrected [40132695520](https://github.com/reddraggone9/tandemlog/actions/runs/40132695520) closed cleanly/no core, as did actual6a CI (fresh2077ms/close178.425ms; warm262ms/close79.319ms with witness reuse). Clean controls do **not** clear the intermittent crash. No speculative engine-lifetime workaround or SDK update was applied. Capture admits harness-certified PIDs, restores the kernel setting, preserves failure exit status, and excludes raw memory cores from artifacts.

## Evidence and environment routes

Committed index: `evidence/rc4-cloud-attribution-20261024/README.md`. Start with `followup-order-analysis.md`, `followup-proof-enforcing-result.json`, `followup-required-ci-clean-close.json`, `followup-order-local-checks.json`, and `followup-order-checklist-validation.json`.

Raw retained cloud routes:

- `/workspace/scratch/rc4-cloud-checkpoint.json` (resumable state).
- `/workspace/scratch/rc4-proof-performance-ci-40134281681/` (full failed report/logs/ZIP).
- `/workspace/scratch/rc4-proof-close-ci-40134281681/` (exact6a test-only bundle ZIP/receipts).
- `/workspace/scratch/rc4-full-prefix-ci-40130625113/` and `/workspace/scratch/rc4-sparse-core-ci-40132695520/` (failed collector and corrected clean control).
- `/workspace/toolchains/logs/rc4-order-membership-*.log`; `/workspace/scratch/rc4-order-checklist-validation*`; `/workspace/scratch/rc4-kernel-io-syscalls.txt`.

Current6a CI artifacts (expire October29; verify SHA256, retain via existing authorized route): performance12576273439 / `84258e9eabef7d962df6653342274e1aed3d69e7f0d944540973417b54385793`; close12576173355 / `3bb30e2e577c7a672cd4cf48bbe816593388b43e48b1c47ab9bf767a396e497d`; Windows12575964195 / `56ff1a89d77f8e0f845e948c15f76e026726b564d833ee418e62021839ae1493`; Android12575748517 / `70c1ad926bf360053b21776b6aff27589dae0f011e77bad5d5386dfc3d1686f5`. These are6a artifacts, **not8005430 builds**. Do not reuse an unproven leftover local bundle as the latest build.

Cloud commands source `/workspace/toolchains/env.sh` (Flutter3.47.5/Dart3.13.4, Rust1.99.0, official unprivileged Linux development tools). Native library: `/workspace/toolchains/native-unit/libtandemlog_text.so`. Use the committed standalone drivers/actual Dart SDK binary; preloading local SQLite into a shell `/usr/bin/env` wrapper can fail on unresolved libm symbols. GDB is isolated under `/workspace/toolchains/debugger`; strace is installed. No product dependency versions changed. Rebuild platform-specific native payloads on Farnsworth; Linux `.so` files are not Windows payloads.

## Native acceptance, next RC and clean cutover

Cloud/Xvfb software framework-post-frame timings are **not hardware presentation latency**. Existing Linux nine-path diagnostics pass replay/restoration but include intervals above100ms. Windows's earlier32ms open/61ms Save/58ms Undo sample is framework-only and not all-action acceptance. Full native Windows action coverage, real timing/growth and remaining Linux UI acceptance remain open. Farnsworth access was restored by Lee; cloud did not use it. Leela foreground permission remains held. Coordinate exact native/device tasks through the parent; infer no new persistent access or foreground permission.

Before any RC/release: triage/fix the native Session Undo/Discard failure without weakening its guarantees, current exact-source required CI including uninstrumented AOT limits, full action/growth/native validation, recorded exact-artifact acceptance, and applicable release/UX/dependency/signing gates. Physical writer mapping, private frozen real-copy replay and live adoption remain separate coordinated prerequisites. No release or live conversion is implied.

Proposed cutover: the bounded6a native run is finished and its failure is retained. Push this updated snapshot; parent and Vex verify the published checkpoint and agree an explicit UTC cutover. Cloud then stops Tandemlog product writes/pushes and workflow dispatch/monitoring ownership transfers to Vex, with read-only assistance as coordinated. Until that announcement cloud remains sole product writer; Vex may inspect, but must not edit concurrently. After cutover preserve Farnsworth's local work, select the published development branch, verify tooling and dispatch/adopt **one** fresh exact-source CI (calibration=false), avoiding duplicate runs:

```sh
gh workflow run ci.yml --ref fix/rc4-task-latency-20261022 -f calibrate_performance=false --repo reddraggone9/tandemlog
```

One direct CLI job-log blob download returned HTTP403 and was not retried; the successful earlier GitHub-app response was already available and has been retained. No authorization blocker remains for this handoff, and no push outcome is uncertain. Pending blockers are technical timing/native evidence and the explicitly held foreground validation. No limit-loosening decision has been requested or granted.
