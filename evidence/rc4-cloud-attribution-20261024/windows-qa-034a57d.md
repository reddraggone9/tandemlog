# Current-source Windows QA artifact — build only

Prepared2026-10-25 for the parent's local executor and a **later separately
reserved Leela foreground bootstrap**. No foreground/app execution occurred here.
Product remains034a57d;no product/harness edit,release,persistent access,signing
change,live fixture or broad CI rerun. Do not use an ordinary production EXE as
this test entrypoint or substitute an older2507e71QA artifact.

## Exact build and download

One dispatch of the existing read-only40minute build-only workflow:
[40179769562](https://github.com/reddraggone9/tandemlog/actions/runs/40179769562),
job121128132296,PASS09:13:45–09:17:10UTC. A dedicated branch
`qa/windows-widget-034a57d-20261025` points **exactly** at
`034a57dbc7092e242889d23d12e22091fed08b0c`;no docs-successor ambiguity.
The workflow creates isolated source/output/Cargo trees,requires clean tracked
source,analyzes the target,builds release-mode AOT,verifies native payload and
packages QA-only metadata. Its native DLL ABI smoke is the only runtime work;
it never launches the app. All20controller policy tests passed locally and in
the build. No new credentials or publication workflow were needed.

| Binding | Exact value |
| --- | --- |
| Artifact | **12594136006**,`TEST-ONLY-windows-widget-viability-qa` |
| Archive SHA256 | `ab24194addf11faf9bc4e16a2ba59528bef73db22bd4a75722ab4dae7c5eb091` |
| Expires | 2026-10-30 09:17:03UTC |
| `qa-artifact.json` SHA256 | `a6335dd0cc575efbd2b4a8d8603266cd92113a709b5e76180d28014fd238164e` |
| QA target SHA256 | `1a4af30cb2ea9a9d95f49e5de4d3a3ecc434381480574923158efe58e33bba6f` |
| `bundle/tandemlog.exe` SHA256 | `5ae16c5616370ee2c4096d76bc1a7200a8772a0d891a7e01be94b4653dc1a007` |
| `bundle/data/app.so` SHA256 | `696ebca219beca8de8161d4a8065e60309449d405ec755e7005a59108dace147` |
| `bundle/tandemlog_text.dll` SHA256 | `91430a7a5d59be671cc9dde506a8bdf42e059969591dda8f50da8de9ec8d9b33` |
| `bundle/flutter_windows.dll` SHA256 | `8bd7b61eee31aa436edb182db41624d1cd3b2688a7e03622320dbeae067b5251` |

Download through the existing authorized GitHub route,for example the read-only
API endpoint `/repos/reddraggone9/tandemlog/actions/artifacts/12594136006/zip` or
the run's named artifact. Use a fresh isolated destination. Verify the archive
digest **before** safe extraction,reject traversal/reparse/symlink entries,then
verify the manifest and all declared members. Do not mix in the ordinary Windows
artifact12588951520,which binds the same product but has another entrypoint.

[Build/verification receipt](windows-qa-034a57d-build.json),
[original manifest bytes](windows-qa-034a57d-artifact-manifest.json),
[original checksum bytes](windows-qa-034a57d-qa-sha256sums.txt),and
[full per-file source proof](windows-qa-034a57d-source-proof.json).
Original Windows metadata is retained literally under scoped evidence attributes.

## What was independently verified

- Archive digest,manifest hash,complete17-member bundle and all21checksum entries
  (including manifest and3helpers),every size/hash and absence of extras.
- Exact source revision034a57d and all191source pins:70match Git bytes literally;
  121match **only exact LF→CRLF Windows checkout conversion**,with both Git and
  actual Windows byte hashes recorded. No other differences. The initial strict
  raw-Git comparison failure is retained as a verification observation;no artifact
  was rewritten or falsely labelled all-raw-byte-identical. Target and controller
  byte pins match literally. Generated-input hashes are retained as build evidence;
  a complete compiled dependency source closure is not claimed by this packager.
- x64 PE32+native DLL and required4exports statically verified without loading it
  in cloud. Native notices are the exact Windows checkout CRLF form of the Git
  notice,also recorded explicitly. CI's real ABI new/read/cancel smoke passed.
- Bundled helpers match exact source and metadata pins:
  `windows_widget_controller.py`=`fdbf515fc49c3288b63cdddde12c7ab34e2c2587fc9805660e265efbed8e27e7`;
  `.ps1`=`eedba0daffe74c354a85c1e6623cd01b8f66b89086704dbedb651419280626e5`;
  `package_qa.py`=`ad8c2a295a5636d5f268dab76c2a0b10b900dd0f23cae747e9704c5fc692823f`.

## Public fixture remains separately sealed

Target and controller both require the **unchanged** public contract
`ui-fixture-original.json`,SHA256
`74f0c24ce01a26792ff4d8a1730c36b1aacdf6a918b90df8310a79386753aeb1`,
`syntheticOnly=true`,1325baseline physical records and exactly4canonical files.
The target selects **Benchmark historical task3** and preserves its already
enrolled synthetic writer. It copies canonical files into a fresh owned run;
it does not import a private/prebuilt profile or prime the app projection cache.

The artifact does **not** include that external fixture. Cloud verified the
agreement of both source-level contract pins,but has not accessed the local raw
fixture/contract. Before any future launch,the local executor must read-only
verify the existing contract hash and every declared canonical member hash,
inventory/regular-file/reparse checks. Do not substitute the Android3Task/1Food
fixture,a regenerated contract or an edited identity to make the pin pass. An
unavailable/mismatched local fixture is a pending bootstrap preflight blocker,
not permission to rebaseline it. No raw personal fixture is needed or uploaded.

## Rebind the existing local foreground harness,without changing controls

The packaged controller defaults to a **private inactive Desktop**. Its default
child environment does not enable foreground mode. It is not a replacement for
the separately reviewed local foreground launcher/collector,and should not be
run to obtain foreground proof. No desktop switch,input injection or foreground
execution is authorized by this build receipt.

For the parent's next small user reservation,update only the local harness's
reviewed expected **source/run/archive/manifest/payload/helper bindings** to this
receipt. Keep its original artifact immutable and retain the local controller's
own source/hash receipt. Never patch a manifest helper hash to conceal a modified
local controller or disable source/payload checking. Review the proposed local
binding change before the later execution;cloud has not inspected that private
foreground helper and does not claim its controls are verified by this build.

Preserve all established local controls:

- Sharing-safe bounded reads of the target log while Flutter may own its writer;
  complete-LF records only,PID/release/run identity checks and finite log cap.
  Do not replace the approved reader with the packaged default `read_bytes` loop.
- Asynchronous foreground ownership/arm handling,owned window PID/image/start
  identity,continuous foreground checks and cancellation if ownership is lost.
  No broad input/desktop/process access or new service.
- External watchdog and before-resume deadline checks,finite cleanup and exact
  owned Job/process handles. Keep atomic Job assignment before resume,
  kill-on-close,process/memory bounds and final active-process0proof. No name-wide
  kill,foreign Job mutation or unrelated PID cleanup.
- Existing normal resource close plus independent canonical-prefix/reference/
  replay checks after the app has closed. Preserve every failed bootstrap/timeout
  and the final Job/window/process cleanup receipt.

The unchanged target's foreground protocol is specific: env
`TANDEMLOG_WINDOWS_WIDGET_FOREGROUND=1`,fresh owned run/profile/temp root and
`TANDEMLOG_WINDOWS_WIDGET_ARM` inside that root. It waits for the initial run/
foreground marker,then `.ready` with stage`action`,then `.inspected` with stage
`inspection`,checking real foreground ownership at each boundary. Required client
viewport is **1280×860 logical pixels** (±1),not just an outer window rectangle.
These are binding facts for read-only local preparation,not a request to execute
or alter the target/viewport/display policy now.

The shipped inactive controller's own bounds remain150s+20s cleanup,6GiB Job
memory,8active processes;its wrapper has170s wait plus bounded controller/pipe
cleanup. Preserve the separately reviewed foreground controller's existing
bounds;do not infer permission to extend any limit from this artifact's40minute
**build** timeout.

## Deliberately limited result scope

The target installs a **mocked framework text channel**,uses tester taps/text,
measures one Task open,one Title Save and one closed-editor Title Undo with state/
post-frame and engine frame observations. It verifies exactly2atomic records,
matching Save/Undo type,target and operation reference,restored selected-task
semantics,preserved prefixes/nonowner bytes,normal native/profile resource close
and a full post-close audit that writes no canonical bytes.

It does **not** measure real OS input/IME or presented pixels. Foreground ownership
does not turn framework/post-frame timestamps into hardware presentation latency.
Completion,Food,full action inventory,repetitions/history-growth comparisons,
broader peer/failure/native coverage and installer acceptance remain uncovered.
Opt-in cost tracing is diagnostic;leave it off unless separately requested.

This receipt only unblocks preparation of a later bounded foreground bootstrap.
No new foreground reservation,product repair,release gate pass,policy change or
live operation is implied. Hosted enforcing performance remains failed at its
unchanged limits;the separate current-source reference/Android evidence retains
its own qualifications.
