# Hosted I/O diagnostic, separate from required CI

This diagnostic branch adds no product change to exacte23f00f. Its single push-
triggered workflow traces only fsync/fdatasync metadata while existing sealed
all-action AOT runs once in instrumented measure-only mode. It is not a noise
retry, a replacement result or release acceptance. Original enforcing failures
remain binding; no threshold, timing boundary or correctness gate is relaxed.

Transient systemd bounds are6GiB/2CPU/no-swap/128pids, with1200-second process and
1260-second service bounds,20-second stop escalation and verified group absence.
Trace metadata is limited to64MiB/512regularfiles; partial/failed outcomes retain
original exit status and reports. The30-minute workflow uses read-only GitHub
permissions, reviewed build actions and distribution strace. No kernel setting,
new persistent service, signing input, personal fixture or SQL/write-buffer
capture is involved. This checkout's looser local bounds correctly refuse launch.

Capture includes compilation, fixture generation, actions, replay and cleanup.
Path-based workload hints distinguish setup but do not identify exact timed
samples. Syscall elapsed includes scheduling/ptrace overhead and overlaps; it is
not exclusive kernel service time. Native/provider/SQL API intervals remain the
existing opt-in diagnostics. Instrumented timings cannot establish acceptance.

[Preparation checks](followup-hosted-io-diagnostic-preparation.json) record7new
cleanup/parser/resource/acceptance-separation tests,178toolpasses,real synthetic
fsync parser control and retained worktree-setup failure. The product branch and
its pending exact-source CI remain separate. Push intentionally triggers ONE
new diagnostic; do not also dispatch it or cancel an existing run. No release,
live operation, limit loosening or hardware latency claim is authorized.
