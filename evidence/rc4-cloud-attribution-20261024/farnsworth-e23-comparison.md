# Controlled Farnsworth comparison — tested e23 source

Lee approved this comparison. Cloud remains sole product writer and holds product
source at e23 while the local executor finishes isolated Android work. Execute
only after that emulator/app/test load is stopped and cleanup/headroom verified.
No real/synced data, persistent runner, security/power/antivirus change or release.

## Fixed comparison

Three planned complete runs, preserving **every** result. Each uses the unchanged
all232-action harness, all3 history shapes,2warmups/5samples, existing absolute/
paired budgets and6GiB/2CPU/no-swap/128pids. Use `--measure-only`: existing budgets
are still evaluated, but no release acceptance or automatic noise retry occurs.
These are planned observations, not retries until pass. Stop remaining runs on
correctness, source, environment or cleanup failure; timing failures remain data.

Expected total35–55minutes after setup. Bound each run to25minutes plus cleanup;
all three at most80minutes. A timeout is a retained incomplete attempt, not an
excuse to increase limits. No overlapping Android, builds or benchmark jobs.

The harness is Linux-only. Use Farnsworth's existing isolated Linux route; record
whether native Linux, WSL or another VM, kernel/CPU, filesystem type and available
memory. WSL is still virtualized and this is not Windows presentation evidence.
Use its existing Linux filesystem, not a Windows/network/live folder. Do not
flush host page caches or change security/power settings. First-profile cases
remain the harness's defined cold-profile cases, not a claimed cold OS disk.

## Source, tools and identical data

1. Create a new detached measurement worktree at
   `e23f00f9640ee5724f4b646d37bc352ca58dc6f1`; never edit the active checkout.
   Fetch through existing authorized access with credential prompts disabled.
   Read that checkout's instructions; require a clean tracked tree before/after.
2. Use reviewed **Linux x86_64 Flutter3.47.5/Dart3.13.4** and locked packages
   (`flutter pub get --enforce-lockfile` inside the isolated copy). Exact Dart and
   gen_snapshot hashes,117source/tool pins and all fixture contracts are in
   [comparison pins](farnsworth-e23-comparison-pins.json). Match them before work.
3. Reuse the exact Linux native and SQLite libraries from CI40151805818 artifact
   **12583650483**, archive SHA256
   `58a30018449fe9e0f36793ad75d077b6bde9542bd7c7d8fdcaa50f4229be04b6`.
   Both are byte-identical to the enforcing performance job's libraries. Paths/
   hashes are in the pins. This avoids compiler confounding; no Rust build is
   needed. If rebuilding becomes necessary, stop this strict comparison first;
   the provenance compiler was Rust1.99.0 with locked/reviewed sources.
4. Set `TANDEMLOG_TEXT_LIBRARY` to that exact `.so`. The original launcher expects
   the exact SQLite `.so` at the **new copy's** `.dart_tool/lib/libsqlite3.so`;
   stage/verify it there after package setup, touching no old profile or SDK.
   Ensure `flutter` in PATH resolves the reviewed Linux SDK, not a Windows tool.
5. Generate through the unmodified driver. It already creates only public
   synthetic data; there is no private-fixture argument. Hosted and independent
   cloud-local generations have identical canonical hashes and every non-path
   contract field for all3 shapes. Verify each run against the published pins;
   only the manifest's absolute `workspace` path may differ. Never rewrite
   canonical bytes or normalize hash/identity fields to make them match.

## Execute using the existing reviewed launcher

Local executor supplies `comparison_source` (new detached worktree),
`comparison_root` (new private output folder), `comparison_pins` (published JSON)
and `comparison_validator` ([read-only helper](validate_farnsworth_comparison.py)),
after Android cleanup. Keep controls outside the immutable measured tree. Run serially, supervised
by the existing local executor with an80minute outer task bound:

```bash
set -euo pipefail
test "$(git -C "$comparison_source" rev-parse HEAD)" = e23f00f9640ee5724f4b646d37bc352ca58dc6f1
git -C "$comparison_source" diff --exit-code
python3 "$comparison_validator" preflight "$comparison_source" "$comparison_pins"
mkdir -m 700 "$comparison_root"
for comparison_index in 1 2 3; do
  (
    comparison_run_id="local-e23-$(date -u +%Y%m%dT%H%M%S)-$$-$comparison_index"
    comparison_unit="tandemlog-performance-$comparison_run_id-1.service"
    comparison_case="$comparison_root/run-$comparison_index"
    mkdir -m 700 "$comparison_case"
    cleanup_comparison() {
      comparison_status=$?
      trap - EXIT
      sudo -n systemctl stop "$comparison_unit" > "$comparison_case/stop.log" 2>&1 || true
      if ! sudo -n systemctl show "$comparison_unit" --property=LoadState --property=ActiveState --property=MainPID > "$comparison_case/cleanup.txt"; then
        comparison_status=1
      fi
      if ! test "$(sed -n 's/^MainPID=//p' "$comparison_case/cleanup.txt")" = 0; then
        comparison_status=1
      fi
      if ! grep -Eq '^ActiveState=(inactive|failed)$' "$comparison_case/cleanup.txt"; then
        comparison_status=1
      fi
      exit "$comparison_status"
    }
    trap cleanup_comparison EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    cd "$comparison_source"
    timeout --signal=TERM --kill-after=20s 1500s \
      env RUNNER_TEMP="$comparison_case" GITHUB_RUN_ID="$comparison_run_id" GITHUB_RUN_ATTEMPT=1 \
      bash tool/performance/run_ci.sh \
      50a606cb302eb6a769c760188901132fb8b35b153ecc41dde11a17c95b39742e --measure-only \
      > "$comparison_case/launcher.log" 2>&1
  )
  python3 "$comparison_validator" report \
    "$comparison_case/performance-results/gate-result.json" "$comparison_pins" \
    > "$comparison_case/comparison-validation.json"
  python3 "$comparison_validator" preflight "$comparison_source" "$comparison_pins"
done
```

The original launcher creates only a transient owned unit with the unchanged
resource caps and its own cleanup. The additional outer timeout/finally cleanup
above stops the unit even if the client fails; require MainPID0 and inactive or
failed state. Preserve stop/query errors. An authorization denial stops the
operation; do not establish another service/credential/security route. Do not
start another run on uncertain cleanup.

After **each** run, before proceeding, validate `performance-results/gate-result.json`:

- All3 attempts,232metrics per shape,correctness/replay/prefix completion,
  `measurementCompleted=true`, `allPinsMatch=true`, `measureOnly=true`,
  `releaseGateAccepted=false`, `rerunsUsed=0`. No incomplete data called a pass.
- Exact published source/limits/library/SDK hashes and actual resource bounds;
  complete fixture contracts minus only the `workspace` path match the pins.
- Record all per-action median/max/samples, absolute/paired failures, CPU/kernel/
  virtualization/filesystem/headroom and load observations. Preserve full logs,
  manifests, reports and cleanup proofs. Never overwrite an earlier run.

The helper checks these conditions before the next run; it never edits the
measured checkout or reports release acceptance. Retain its output and errors.

## What this can explain

Compare across all three local runs and the retained exact hosted e23 result,
including medians, maximum tails and paired growth separately. Steadier local
results would support a platform-variability hypothesis; different CPUs/OS/storage
still prevent claiming a controlled code speedup. They do not replace the failed
hosted gate or qualify a release. Report resource/load mismatches honestly.

The first syscall capture was incomplete after517per-thread files exceeded512;
its failed artifact and verified service absence are retained. A bounded partial
first512-file read saw9309barriers, longest5.986ms SQLite/3.260ms canonical. It
does **not** tie those syscalls to the original slow samples or separate every
fsync/metadata/await/scheduler/CPU delay. Corrected diagnostic40153325037 remains
independent, with the same bounds. Current cold-profile CPU sampling identifies
physical decode/canonical encoding/hash and semantic validation work; CPU samples
are not an exclusive wall-time partition. No unavoidable tradeoff is established.
