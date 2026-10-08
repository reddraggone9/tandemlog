# Scoped hosted Windows application acceptance

The manual `ci.yml` option `windows_app_flows=true` runs only the existing scoped
Windows application entrypoints. Push/PR/default manual CI still uses the
unchanged full `validate.yml`. The scoped run has its own concurrency group so
it does not cancel a normal CI run for the same branch.

Prepared from `a960c882c06c018a1e721e7459f08dbe4d17bed3` in the isolated branch
`test/windows-native-app-flows`. Application, test, native, dependency and frozen
fixture inputs remain identical to that candidate. After independent review and
an authorized push, dispatch the existing registered CI workflow at the reviewed
branch:

```sh
gh workflow run ci.yml --repo reddraggone9/tandemlog \
  --ref test/windows-native-app-flows -F windows_app_flows=true
```

The reusable workflow checks out the caller's exact source on `windows-2022`
and uses the existing pinned Flutter/text-engine actions (including preinstalled
Python3.11 and Windows/MSVC), followed by locked pub get. It introduces no action,
dependency, version, secret or publication route. Boolean dispatch inputs and
same-commit local reusable workflow calls follow the
[GitHub workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
and [reuse documentation](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows).

`tool/windows_app_flows.py` records Windows host/Python/source and toolchain
diagnostics, then runs six commands separately: checklist workflow2, lifecycle7,
Inbox4, bulk2, field-layout3, and the exact workspace-search aggregate filter1.
Each command uses native `flutter test -d windows --no-pub`, fresh synthetic
profiles and the existing framework test actions. Optional Linux capture variables
are removed. No OS mouse/keyboard automation or manual GUI takeover is added.

Each command's full output, exit, completed/skipped/failed counts and elapsed time
are retained. Passing requires the expected count, zero skipped/failed flows,
exit0 and the completed success banner. Subsequent entrypoints still run after a
failure. A command has a300-second limit; timeout stops only its fresh process
tree. The workflow retains the current40-minute Windows job bound, with32minutes
for the receipt step. Source must equal the dispatched GitHub SHA.

Every scope must also emit a numeric `TANDEMLOG_FIRST_FRAME_MS` plus a numeric
loaded or onboarding readiness marker from the production app. A success banner
without genuine app startup markers fails; all observed values are retained.

After each command, the receipt hashes every generated debug payload file and
requires the app EXE, native text DLL, Flutter DLL, `data/icudtl.dat` and
`data/flutter_assets/kernel_blob.bin`; all five must be nonempty. The dedicated artifact contains only JSON
and logs, including the actual runner/display/startup failure
if one occurs. It never uploads test profiles, canonical histories or executables.
The final receipt passes only when all19 expected flows and payload checks pass.

Native provenance records any `TANDEMLOG_TEXT_LIBRARY` value and its exact hash
or read error. These app/fixture entrypoints call `NativeTextEngine()`; the
current adapter does not read that variable and defaults on Windows to
`tandemlog_text.dll` adjacent to `Platform.resolvedExecutable`. The receipt labels
this source-declared debug-bundle selection separately from an unused environment
value and records the loader source hash. It does not claim runtime loaded-module
enumeration from payload hashes.

Windows execution is pending at preparation: local source/receipt checks do not
establish runner display availability. A future successful run is source-bound
debug native application acceptance, not manual visual/screen-reader acceptance,
execution of the downloaded release executable or Android SAF/IME evidence.
Those exact-artifact and platform gates remain in
[runtime QA](runtime-qa.md) and [checklist native acceptance](checklist-native-acceptance.md).
