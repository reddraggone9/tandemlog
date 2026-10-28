# Signed-candidate waiter lifecycle repair (2026-10-28)

## Diagnosis

Candidate 40643585573, source `6b8bb7455ddd9e7e6cf7f36b930687538e127c31`,
completed successfully. The historical one-off Python script never reached its
artifact-download branch. Its last saved run view was 06:53:20Z, still in progress
with five completed jobs. Dispatch claim was written at 06:23:44Z; manual recovery
at 07:30Z downloaded that same run without redispatch. No traceback or terminal
receipt accompanied the stoppage. The script's own wait deadline was 7,200s.

The recovered launch used `cd ... && setsid nohup python3 ... > pipeline.log 2>&1
< /dev/null & sleep 25; ...`. The exec tool returned a managed process handle
(`delta-shell`), polled once and still running. Its default deadline was 1,800s
(installed OpenClaw `resolveExecDefaultTimeoutSec`, no authored timeout override).
Shell detachment did not detach the descendant tree from that executor. The last
heartbeat is within one poll interval of the outer deadline, not the Python
wait deadline. **Launcher ownership/deadline mismatch is the reproduced cause.**
The exact historical OS signal/exit code was not retained and is not asserted.
Other reported occurrences were not individually reconstructed.

A scaled reproduction used the same `setsid nohup ... &` launch with an 8-second
local dummy and a 3-second tool deadline. The tool timed out; the dummy PID was
gone, its completion marker absent, its redirected log empty. Thus neither
`nohup` nor a new POSIX session ensures survival of this executor's cleanup.

## Repair and verification

The shared waiter takes an explicit existing run/source, never dispatches, reports
heartbeat and terminal errors, and atomically promotes all three downloaded
artifacts with byte hashes. The documented launch path transfers ownership to a
bounded user-manager service, retains its terminal result, and excludes duplicate
local writers. Existing publication and native-acceptance gates remain unchanged.

Local automated coverage includes waiting→success→all downloads, idempotent
recovery with byte/source checks, failed/cancelled/timed-out candidates, wrong
provenance, CLI errors/timeouts/malformed JSON, deadline, incomplete/duplicate
artifacts, lock conflicts, signal reporting and managed-launch bounds. Actual
Linux process-lifecycle/read-only artifact recovery results are recorded below;
these are not evidence of a new release or a pending-build end-to-end release run.

- **Local regression checks:** 15 waiter/launcher tests, 14 release-gate tests,
  13 publication-inventory tests and 4 draft-release tests passed (46 total).
  `git diff --check` passed. No app/native/performance qualification was run.
- **Actual Linux lifecycle + existing GitHub artifacts:** launched the shared
  waiter as user-manager unit `tandemlog-candidate-wait-21d734ea41f7a740` for
  completed run 40643585573. Deliberately timed its requesting exec out at 2s.
  After the caller was killed, the independent worker was observed still running
  in `phase=downloading` (PID3442904), then completed successfully ~12s after
  start. Service `SubState=exited`, `MainPID=0`, `Result=success`,
  `ExecMainStatus=0`; all 14 downloaded filenames and SHA-256s matched the
  original release coordinator's manually recovered candidate dist exactly.
- **Managed resume:** stopped only that finished owned unit, relaunched with the
  same identity/output, and verified `reused=true`, successful service exit and
  the same 14 file hashes. Resume supplied no token-file option and required no
  GitHub request. The finished unit was stopped after recording receipts.
- This observed recovery uses a **previously completed** run. Waiting through an
  actual pending signed build is covered by the local state-transition checks,
  not claimed as a newly observed end-to-end release. Historical stable, tags,
  workflows, desktop installs and production data were not changed. No workflow
  was dispatched/redispatched. Credentials were read only by the worker for
  authenticated read/download operations and were not printed or stored in units.

Private coordinator checkpoint and detailed logs/receipts live in the isolated
`~/aux/vex-private/tandemlog-release-wait-fix-20261028` worktree. Next coordinator
must integrate the reviewed dev commit, use the shared launch path, and verify
both terminal service result and download receipt for the next authorized release.
