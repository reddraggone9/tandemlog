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
history scaling that remains an open performance gate. Inspection finds repeated
all-event decoding and resolver construction per projection; only per-resolution
completion-prefix memoization exists. This is a bounded diagnosis, not a profile
or a completed optimization, and no admission/proof validation is weakened.

Exact signed Android runtime, long-history performance, historical mixed-lineage
policy and release acceptance remain pending. There is no new publication. The historical
isolated proposal logs elsewhere remain unchanged; current accepted ADR0010
supersedes their former pending decision status.
