# Adopted Undo patch and recurring text checkpoint

Unreleased feature branch. All data and UI evidence are synthetic; original
canonical/frozen fixture bytes and user data are unchanged.

- [470 unit/widget cases](unit-widget.txt) pass against the actual adopted Linux
  library; [analysis](analysis.txt) is clean. The [nine proof/store cases](proof-and-store.txt)
  cover the later closed-prefix distinction and delayed third-writer frontier.
- [Dependency gates](dependency-gates.md): 98 unchanged native Python cases,
  four Rust cases, 35 tooling and four notice cases. One official67-file crate,
  one approved source change, original MIT notices; no other package update.
- [Bundled GTK recurring flow](gtk-recurring.txt) passes checkbox completion,
  exactly one inherited child, child title/notes contexts, Save and receipt Undo.
  The three checkpoints were visually inspected at1200×850, Dark,100% text;
  the editor remains coherent and the resulting child stays listed after Undo.
- Adopted and actually bundled library SHA256:
  `5d0a7b1b3e0e6b906e831bed562a45f8db03a2bf4f08c80d9dc0c29a6f169153`.
  This is native Linux Debug evidence, not release performance or Android/Windows.
- Actual two-folder/store workflow plus a third withheld stream verifies early
  child Save, stable lineage, peer inheritance, private draft retention, original
  actor ownership, selective Undo, completion protection, later-parent isolation,
  warm zero canonical reads and full cache loss with identical states/frontiers.
  Missing proof blocks new capture/Save before receipt preparation without
  changing canonical files/outbox; later arrival resumes owner refresh.
- [Historical mixed initialization](legacy-mixed.txt) refuses before receipt
  preparation and preserves canonical bytes/view. No scalar/native rebasing.

## Native whole-title assertion assessment

The broader GTK workflow found a causal whole-title replacement/Undo mismatch:
`Review household supplies` → local `Local pending review` → peer-observed
`Newer synced review` → local Undo displays
`Review household suppliesNewer synced`. The [diagnostic](gtk-causal-undo-failure.txt)
records real projected rows and UI. It is not an identity-commit failure: ordinary
character Undo restores our old deletions while removing original local suffix
identities reused by the peer. Independent actual-native probes establish approved character semantics:
`A → BC → DC → Undo = AD`; independent insertions give `AB → AXB → AXBY → Undo = ABY`.
Both peers converge. A new actual-store regression pins both results. The broad
flow now tests peer-owned append retention; old whole-field LWW protection stays
in historical fixtures. No algorithm/preservation guard is silently changed.
This can yield awkward prose, which the ADR explicitly discloses. The
[corrected bundled GTK aggregate](gtk-final-matrix.txt) passes all three flows.
The [final 35-case focused suite](focused-final.txt) also passes after the
affected-owner optimization; unrelated user arrivals no longer replay every
open inherited field owner.

## Windows checkout correction

Hosted run37253307957 stopped before Windows tests with
`Text engine packaging failed: Unapproved Yrs vendor inventory hash`. A real Git
checkout with `core.autocrlf=true` reproduces the same failure when the vendor
attribute is absent. The exact-byte `.gitattributes` rule fixes that checkout
while retaining all67 strict source hashes. The regression also preserves this
negative control; [all36 tooling cases pass](windows-checkout-tooling.txt).
The source inventory, patch and native algorithm are unchanged. A fresh complete
hosted run is required; the earlier partial run is not platform acceptance.

## Follow-up platform failures

Run37253645489 passed the literal vendor gate. Its Windows unit suite then
reported462 pass/seven fail/two platform skips. Two recurrence failures were a
fixture cleanup race (unawaited close and undisposed native engine); five exact
retry/restart failures exposed literal slash/backslash path comparison in private
native intent recovery. Native file URIs now compare equivalent platform paths,
retaining writer, space, required type, writer/sequence filename and raw receipt
checks. The [focused recovery cases](windows-recovery-focused.txt) pass on the
adopted Linux library. A new wrong-filename case rejects before append, preserving
canonical and private intent bytes; original restart assertions are unchanged.

Android stopped at the strict64-bit RELRO16KiB gate. The linker now specifies
both max-page-size and common-page-size16KiB, including the latter explicitly
rather than relying on Rust target defaults. This follows the
[official Android guidance](https://developer.android.com/guide/practices/page-sizes#compile_your_app_using_16_kb_elf_alignment).
LOAD/RELRO gates, approved NDK/version and67 source hashes are unchanged. Full
three-ABI packaging and native installed Android acceptance remain required.

## Complete native workflow correction

Hosted run37254495743 passes Windows unit/native/installer gates and Android
three-ABI debug packaging. Linux passes unit, Rust and frozen native gates,
then reports50 native workflows passing and one obsolete expectation failing.
That old test still expected all native recurring completion to be blocked,
before Lee approved successor union. The positive inherited-child workflow
passes. The obsolete guard fixture now creates a real historical scalar child,
activates its parent and verifies mixed-lineage recompletion fails before append.
[Actual bundled GTK execution passes](gtk-mixed-historical.txt), with canonical
bytes, empty outbox and both existing task rows preserved. No application logic
or release gate is weakened.

[Final hosted rerun37257156550](https://github.com/reddraggone9/tandemlog/actions/runs/37257156550)
at `fd9f6678c1fcf91c9734d071f82da35fd3490ccb` passes all targets:472 Linux
app tests,470 Windows tests/two platform skips,51 native GTK workflows,
98 frozen native cases/four Rust cases/36 tooling cases, Android three-ABI
debug payload/signature verification, and Windows/Flatpak installed lifecycle
checks. No app logic changed after `cdbc56b`; the remaining diff is test/evidence.

The Linux artifact11323811587 passes API SHA256, ZIP CRC and internal checksums.
Its [unaltered startup artifact](hosted-linux-startup.json) reports ten synthetic
tasks:642ms fresh cache/510ms warm process-to-loaded-frame, first frame330/264ms,
zero warm canonical reads. The native release callback does not prove physical
presentation or first-input latency; OS page caches are not flushed. This scalar
task startup workload is distinct from the recurrence-lineage AOT probe below.

The intermediate debug Android artifact is
[11321533518](https://github.com/reddraggone9/tandemlog/actions/runs/37254495743/artifacts/11321533518)
at application source`cdbc56b9a53412591afbe0f71c0578d220abb3b9`. ZIP CRC/API
SHA256 and all three actual native payloads/notices pass local verification.
APK SHA256`1a073a0f8bdf91378c20dcb5050026fd31381ed3b8292e38851939749e1983aa`.
Its temporary Android Debug signer is
`863fe1068327311e9befaea24c41ce19e8e2c38518570ce9cfcbbf7e5a101199`;
package is unchanged, code45/version2026.10.2-rc.3, and it is explicitly a fresh
synthetic-workspace test artifact, not an owner-signed update or publication.

## Desktop demonstration

A separate paced [actual GTK demonstration run](gtk-demonstration.txt) passes
the same completion → child edit → confirmed Save → Undo workflow with readable
synthetic content. The inspected21.6-second,1200×850 Dark/100% recording has a
visible pointer and is delivered separately through Library. The video is native Linux Debug, not
Android, a sync-provider demonstration or release startup measurement.

## Bounded AOT lineage cost

The [raw storage measurement](lineage-aot-cost.json) uses a private Dart AOT
executable importing production TaskStore and the actual adopted Linux native
library. It creates one synthetic native-text daily task, completes 80 successive
occurrences without editing children, then opens the cache warm and rebuilds only
its isolated SQLite database. Writer/guards and canonical files are retained.
The exact production sqlite3 package's host library is preloaded for this private
executable's native-asset lookup; application packaging is not changed.

| Operation | Single workload result |
| --- | ---: |
| First completion | 17.827ms |
| Eightieth completion | 316.287ms |
| Warm TaskStore open | 4.063ms, zero canonical log reads |
| Rebuild 81-task/82-event cache | 3406.699ms, one canonical log read |

Rebuilt/warm states are identical and canonical files remain unchanged. OS page
caches are not flushed. These are domain/storage timings, not Flutter UI startup,
physical presentation, first input or Android measurements. They demonstrate
the original history scaling diagnosis before the optimization below. The baseline repeatedly decodes all events and constructs resolvers per
projection, with only per-resolution completion-prefix memoization. This is a bounded diagnosis, not a profile
or a completed optimization, and no admission/proof validation is weakened.

Exact signed Android runtime, long-history performance, historical mixed-lineage
policy and release acceptance remain pending. There is no new publication. The historical
isolated proposal logs elsewhere remain unchanged; current accepted ADR0010
supersedes their former pending decision status.


## Bounded performance optimization

The [source fingerprints](performance-source-files.json), [method](performance-method.json)
and [reproducible private-fixture driver](measure_lineage.dart) identify this
optimization separately from the historical source inventory above. No frozen
canonical/native fixture is regenerated. The final raw label `working-stage12`
is the production code in those fingerprints; the commit containing this report
provides the actual source. Baselines use exact1eb8336 and the same AOT driver
workload. UUID/actor bytes vary between fresh synthetic runs. These are single
sequential samples, not a statistical distribution or UI startup claim.

| Workload | Last completion, baseline → final | SQLite rebuild, baseline → final | Final warm open |
| --- | ---: | ---: | ---: |
| 80 completions, unchanged text |306.578 →22.542ms |3365.063 →197.782ms |3.635ms /0 log reads |
| 20 completions, title/notes edited each time |384.821 →26.732ms |856.097 →121.855ms |3.421ms /0 log reads |
| 80 completions, title/notes edited each time |final60.469ms |final932.279ms |3.551ms /0 log reads |
| 320 completions, unchanged text |final44.779ms |final907.881ms |4.506ms /0 log reads |
| 320 completions, title/notes edited each time |final236.885ms |final11832.500ms |4.223ms /0 log reads |

See raw [baseline unchanged80](performance-baseline-unedited-80.json),
[baseline edited20](performance-baseline-edited-20.json), final
[unchanged80](performance-unedited-80.json), [edited20](performance-edited-20.json),
[edited80](performance-edited-80.json), [unchanged320](performance-unedited-320.json)
and [edited320](performance-edited-320.json). Each final rebuild starts a fresh
native-engine owner with an empty inspection memo, after deleting only the
fixture SQLite/WAL/SHM. Shared canonical bytes, private writer/guards and loaded
OS/library pages remain. Warm/rebuilt task snapshots match; all canonical files
remain byte-identical within each run. Fresh engine creation is outside the
rebuild stopwatch, so this is not end-to-end cold-process startup.

| Final workload | Canonical files | SQLite logical pages | Native state BLOBs | Frontier JSON | Whole-process peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Edited80 /81tasks |278816B |1380352B |222764B |279460B |35348480B |
| Unchanged320 /321tasks |see raw report |see raw report |see raw report |see raw report |62689280B |
| Edited320 /321tasks |2227476B |12197888B |3412375B |4413460B |96354304B |

SQLite size is page_count×page_size, not a sum including every transient WAL or
side file. RSS includes Dart, SQLite, the native engine and probe; it does not
isolate memo overhead or model retained UI Undo owners. Baseline unchanged80
peak RSS is48082944B and edited20 is48332800B; final edited20 is17543168B.
The accounted memo limits are conservative payload limits, not total heap caps.

The bounded memos avoid repeated canonical decoding, actor hashing, stateless
native inspection and inherited packet replay; shared immutable packet accounting
prevents early eviction amplification. SQLite candidates must match the
independent resolver's exact final hash/text, otherwise original replay resumes.
One transaction shares its admitted record set across affected projections.
Global order uses the already-selected creation stamp. All admission, observed
prefix, actor ownership, canonical receipt and Undo semantics remain in force;
there is no canonical or cache-schema change. See [ADR0010](../../../design/decisions/0010-collaborative-text-adoption.md).

The original unchanged80 regression is substantially reduced. **Long edited
lineages remain a release-performance limitation:**321tasks take11.83s to rebuild
from scratch and their last completion takes237ms. Inspection memo exhaustion
and full affected-field/history work still preclude a constant-latency claim for
arbitrary history. No preview/main adoption is authorized by these numbers alone.
The next investigation should profile incremental history/proof indexing and
historical field materialization against measured allocation/FFI costs, preserving
original packets, concurrent successor union and Undo. Do not compact/rewrite
canonical history to conceal the cost.

### Reproducing this environment's storage probe

Build the approved native library normally, run `flutter pub get --enforce-lockfile`,
then compile the driver with the repository package configuration:

```sh
dart compile exe --packages=.dart_tool/package_config.json \
  -DPROBE_SOURCE=reviewed-revision evidence/production-text/recurring/measure_lineage.dart \
  -o /tmp/tandemlog-lineage-probe
TANDEMLOG_TEXT_LIBRARY=/absolute/path/libtandemlog_text.so \
LD_PRELOAD=/absolute/path/to/pinned/sqlite3/native-asset/libsqlite3.so \
PROBE_EDITS=yes PROBE_GENERATIONS=80 PROBE_REPORT=/tmp/lineage-report.json \
  /tmp/tandemlog-lineage-probe
```

LD_PRELOAD is only this standalone Linux AOT native-asset lookup workaround.
The Flutter app packaging is unchanged. The driver always creates/deletes its own
fresh temporary workspace; it never accepts a live workspace path. Its generation
loop stops after90seconds or a2second individual completion, then reports the
actual count and verifies warm/cold reconstruction. Successful final320 samples
completed all320; earlier capped intermediate runs are retained privately.
