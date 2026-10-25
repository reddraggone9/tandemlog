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

## First bounded failure and collector correction

Run40151843422 at16d8f4b failed after820.881s when per-thread strace output
reached517files against512. Trace data was only1690835bytes; execution stopped,
original childexit-9 was retained and the owned unit cleanup was verified. This
is an executed diagnostic failure, not an authorization denial or app acceptance.
Base-history correctness passed; all-shape completion did not. Original archive
and logs remain pinned in [failure receipt](hosted-io-first-failure.json). A
strictly partial first512-file analysis sees9309barriers,0unparsed,maximum5.986ms
(SQLite) and3.260ms canonical; do not assign these to exact uninstrumented samples.

Correction uses one interleaved strace file (-f) plus supported --seccomp-bpf
filtering. The parser joins unfinished/resumed calls by PID and preserves original
start time; orphan or over128pending calls fail closed. All bounds remain exactly
unchanged, including512files/64MiB,20min process and resource caps.180tool tests
pass, including interleaving/pending-bound cases; a real two-child BPF control
produces1file/2barriers/0unparsed and stops all owned children. A new push runs
ONE corrected diagnostic after the prior run's terminal failure. No product
source or enforcing gate is modified.
