# Current-source reference AOT protocol — 034a57d

Prepared 2026-10-25 UTC. **Plan, not an executed measurement or gate change.**
Cloud remains sole product writer. The local executor owns the isolated lab and
corrected external controller. Coordinate completion/cleanup of its read-only
native-gap review before starting. No emulator, app, other build/test workload,
physical device, live data, foreground Windows window or persistent runner.

## Fixed count and meaning

**Exactly three planned serial complete observations**, each using the unmodified
all232-metric harness across all3 history shapes with2warmups/5measured samples.
No retry-until-pass, replacement of slow samples, selective action rerun or
automatic noise retry. Timing failures are retained observations and do not stop
the next preplanned observation. Source/correctness/tool/resource/cleanup failure
stops the remaining batch. An aborted observation is retained; a replacement
requires separate coordination, not an automatic fourth launch.

Use `--measure-only`, without `--diagnose-costs`: evaluate all existing absolute
and both paired limits, but never report release acceptance. Keep the unchanged
limits SHA256 `50a606cb302eb6a769c760188901132fb8b35b153ecc41dde11a17c95b39742e`.
Bound each observation to25minutes plus20seconds termination cleanup; the entire
batch to80minutes. Expected35–55minutes after setup (latest hosted driver took
about8.3minutes for its three measured shapes, plus compile/generation). Do not
extend the deadline or relax a pressure/resource guard to obtain a result.

## Immutable source and bindings

Create a new detached measurement copy at the **product** commit
`034a57dbc7092e242889d23d12e22091fed08b0c`. Keep controls, this document, fresh
[pins](reference-034a57d-pins.json), [validator](validate_reference_comparison.py)
and outputs outside that copy. Documentation successors do not authorize product
drift. The fresh manifest verifies **118** source/tool files against Git objects;
the e23 manifest had117 and must not be reused. Do not modify old e23 evidence.

Use Linux x86_64 Flutter3.47.5/Dart3.13.4 and locked packages. Existing reviewed
SDK/cache may be reused; `flutter pub get --enforce-lockfile` may prepare the new
copy without changing its tracked files. Match Dart and gen_snapshot hashes in
the pins. No dependency update or Rust rebuild is needed.

Reuse CI40167598688's original uninstrumented close artifact **12589500796**,
archive SHA256
`d014d6128a2c4c209108a2cfd8e7576f44a2e9e81734ea96f88938fc54926166`:

- `build/linux/x64/release/bundle/lib/libtandemlog_text.so` SHA256
  `d33124d01cbcc7be76e6bbf421362c44d3d2b8e7f5ce1a1fc5b9ddcd9dd1ad83`;
- `build/linux/x64/release/bundle/lib/libsqlite3.so` SHA256
  `0f947ebe629e8d9d02d7f408bef36e056bfc63ea47e02e0d45a7bae454f04ace`.

These match the hosted performance report's libraries. Verify the archive before
safe extraction and each library after staging. Set `TANDEMLOG_TEXT_LIBRARY` to
the native library; place the exact SQLite library at the measurement copy's
`.dart_tool/lib/libsqlite3.so`. Do not put SQLite in a shell/controller-wide
`LD_PRELOAD`: the driver sets it on the actual Dart/AOT child. The hosted
performance artifact12589850277 (archive hash in pins) retains reports/logs,
**not the AOT executable**. Record each local executable hash; source/tool
equivalence does not establish cross-host executable byte identity.

## Corrected controller interface

Adapt **only bindings/output names** of the existing reviewed pressure controller
and manager route. Do not run `run_ci.sh` as Lee: it derives the workload UID from
its caller. The approved manager launches the direct driver as the existing
unprivileged lab UID/GID1002 after verifying that identity. No sudo policy change
or alternate access route is authorized or necessary. Keep its manager ownership,
outer supervision and unconditional exact-unit cleanup.

Each unique transient workload unit retains:

| Control | Required value |
| --- | --- |
| User/group | existing lab UID/GID1002, verified before launch |
| WorkingDirectory | new immutable034a57d copy |
| MemoryMax / MemorySwapMax | 6G / 0 |
| CPUQuota / TasksMax | 200% / 128 |
| RuntimeMaxSec / TimeoutStopSec | 3300 / 20 |
| KillMode / OOMPolicy | control-group / kill |
| External per-observation / batch deadline | 1500s / 4800s |
| Concurrent observations | 1 |

Keep the existing finite log cap, finite manager lifetime, controller tests and
pressure sampling. Use its corrected ARC-aware stable-snapshot preflight: raw
MemAvailable at least2GiB and raw plus min(half conservatively evictable ARC,
6GiB) at least8GiB, respecting ARC minimum. Global swap allocation alone is not
proof of workload pressure. Retain actual workload swap/OOM, disk swapout and
the controller's other genuine-pressure checks; do not improvise a weaker guard.
Record headroom/load/kernel/CPU/filesystem and whether Linux is virtualized.
Use the existing Linux filesystem, no cache flush or host power/security change.

The controller supplies the same clean environment as `run_ci.sh`: the lab
account's existing HOME/PUB_CACHE, reviewed PATH and LANG=C.UTF-8. Launch the
following **inside that bounded unprivileged transient unit**, with absolute
paths chosen by the local executor (this is the payload, not an alternative
unsupervised launcher):

```bash
/usr/bin/python3 "$reference_source/tool/performance/run_gate.py" \
  --repo "$reference_source" \
  --dart "$reviewed_flutter/bin/cache/dart-sdk/bin/dart" \
  --native-library "$reference_native_library" \
  --sqlite-library "$reference_source/.dart_tool/lib/libsqlite3.so" \
  --expected-limits-sha256 50a606cb302eb6a769c760188901132fb8b35b153ecc41dde11a17c95b39742e \
  --output "$reference_case/performance-results" --measure-only
```

Use unique fresh output directories for observations1,2,3. The driver requires
its `performance-results` output not to exist and creates its own owned source
copy. Keep `reference_case` in the outer loop's scope, not only a subshell: the
old published e23 shell sketch had a subshell-variable scoping defect. Use the
already tested corrected controller instead of copying that old sketch.

## Serial verification and receipt

Before the first launch and after **each** observation, run the new read-only
preflight using the reviewed SDK PATH and native-library environment:

```bash
python3 "$reference_validator" preflight "$reference_source" "$reference_pins"
```

After each completed observation, before the next launch:

```bash
python3 "$reference_validator" report \
  "$reference_case/performance-results/gate-result.json" "$reference_pins" \
  --source "$reference_source" > "$reference_case/comparison-validation.json"
```

This re-evaluates every absolute/paired result with the exact source-controlled
policy, verifies all3 shapes232metrics and2/5 sample order, correctness, absence
of retries/rewrites/shims, actual caps,118source pins and unchanged fixture
contracts except the absolute workspace path. The driver must report completed
measurement and final source/tool seals even when timing limits fail.

It also verifies a normalized inventory of **5390** compiled source/dependency
files, the project import closure and compiled-file seals. Only installation-root
paths are renamed. Exactly the two package-configuration byte hashes are reported
separately: the local executor must inspect their resolved package names, language
versions and roots against the reviewed locked SDK/cache and record that any
differences are installation paths only. This is a required manual qualification,
not an automatic exception for arbitrary configuration changes. Every other
relative path/hash and the complete inventory digest must match.

Preserve full reports, manifests, executable hashes, action/resource logs,
controller pressure records, exit/timeout status and every failure. Verify the
exact workload and manager units are stopped/absent, MainPID0, no owned child
processes and no cleanup uncertainty before another observation. The outer
supervisor must perform this on cancellation or deadline as well. An access
denial stops the operation; an uncertain launch requires read-only state checks,
never a duplicate launch.

Return all three receipts, total failures and separate median/max misses. In
particular compare **all five samples**, not only medians, for:

- `converted.food.paired.details.confirmedSave` and `confirmedUndo` across Task
  growth (latest hosted Save median9.984ms >9.3125ms paired bound);
- `task.complete.checklistConfirm` across Food growth (latest hosted maximum
  60.819ms >51.7138ms paired bound);
- the three isolated Task metadata maxima and all cold/warm startup cases.

No local outcome erases hosted failures, changes release gates or establishes
input-to-display latency. Current-source Linux native203-test and normal-close
passes are separate evidence. Full-action hardware Windows responsiveness,
current-source Android/native gaps and eventual candidate/release acceptance
remain separately coordinated and unclaimed.

## Completion report — supplied2026-10-25

Parent/local executor reports all3planned observations complete with0absolute
median/max and0paired median/max misses each,all pins/contracts/correctness/sample/
package checks passed,no timingretry/replacement,and terminal cleanup07:59:11UTC.
[Qualified supplied receipt](reference-034a57d-final-supplied.json). Cloud did not
access raw local artifacts. Hosted5absolute/3paired failures remain retained;
no gate replacement,policy change or hardware/native acceptance is implied.
