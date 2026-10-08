# Frozen RC4: debug/native QA handoff

Frozen source `e205e650b5614935a73cf5acb96ca9b36fda8e4e`, branch
`preview/shared-history-checklists-final`, source version `2026.10.2-rc.4+46`.
This is a separate combined candidate. Do not replace the parent-owned isolated
historical fix artifact/profile while its A16 retest is running.

## Exact reported artifacts

Full [CI37810677866](https://github.com/reddraggone9/tandemlog/actions/runs/37810677866)
checks exactly e205e65. All three platforms completed successfully: Linux 628 unit and 70 actual native
app flows; Windows 626 unit with two expected Linux-only skips; each desktop
4 Cargo, 107 native worker and 37 tooling cases. Packaged-native/notices, release
packaging and installation smoke/lifecycle gates passed. The [qualified receipt](../evidence/final-preview/ci/receipt.json)
records source, terminal status, counts, artifact metadata and exact decoded-log hashes.

| Binding | Exact reported value |
| --- | --- |
| Android job | `113426406473` |
| Android artifact | `11565436217`, name `android` |
| Android outer ZIP bytes / SHA256 | `80393758` / `e8d7e452db32aecea8de30c12d55053507e9a9d09dbabba415bcca56eae8e831` |
| Hosted APK SHA256 | `41b2321ff24182890696cda172368bf9dad34b6e906c5820b01539fd5b5bb3b2` |
| Hosted debug certificate SHA256 | `898863c455d8013fcc8e66e7816333b00a3e6f532727a55b13d2d4b787e64d7c` |
| Linux job | `113426406147` |
| Linux artifact | `11566475838`, name `linux` |
| Linux outer ZIP bytes / SHA256 | `9003289` / `17707119e22929cbe60ce7621657978415276c6ca64411144952f435220ffa59` |
| Windows job | `113426406538` |
| Windows artifact | `11564614184`, name `windows` |
| Windows outer ZIP bytes / SHA256 | `25761070` / `886733fffac3da20782b56694d187476af129aae5f7683f00ac92a09791413bf` |
| Hosted inner unsigned portable ZIP SHA256 | `b2b0e84b540d99ee8e791d85620c2d7eaa28cc8b68452ca000845c8c3f6c2ea2` |
| Hosted Windows executable SHA256 | `90ec52f1cec5b878e4ffd92f2926c0f46f9cce99da0926bf738648a824e98ae6` |
| Hosted Windows native DLL SHA256 | `b82ab4e91fa91c4ebd20aebfffe5af6e5bca8e037083cb989fcaccdc8219b990` |

Outer ZIP digests/sizes are GitHub artifact metadata; APK/certificate and Windows
payload digests are completed hosted job output. The GitHub connector returned a
resolved Android file reference and Library preparation succeeded, but supported
consumer materialization returned 403. No local archive/APK/member-byte or signature
verification is claimed. Resolve/download independently, verify actual outer and
inner bytes against these separate digests, and verify signer/package/version/code
and the exact installed artifact before runtime acceptance. This debug signer is
different from the isolated fix's debug signer; do not assume an in-place update.
Debug APKs are test-only and are never public release assets.

## Native delta from the isolated fix

The isolated source `d73662a` already contains the shared-history/checklist core
and queued fixes. This combined source adds shared-B tag UI, narrow KGP2.4.20
remediation and version metadata. AGP9.1.0, Gradle9.3.1, native inputs and dependency
locks match their reviewed components. Do not treat earlier artifact hashes or
runtime results as acceptance of the combined payload.

1. Keep the current isolated A16 regression retest intact. After its outcome,
   install this combined candidate only in an independently identified synthetic
   test installation/profile, retaining the failed original and pre-leak checkpoint.
   Never uninstall/replace a live profile or copy private writer identities.
   All participating preview test peers must run the updated reader before
   consuming retained-successor native markers.
2. Recheck historical recompletion, Undo and cold replay/convergence from genuine
   A16 or a fresh complete synthetic sequence. The fix is preventive: never edit,
   truncate or rewrite canonical history to remove an already leaked proof.
3. Exercise editor, bulk Add/Remove and Filter suggestions/chips on Android:
   existing multiword tags, completed-task inventory, exact matches/new tags,
   pending-query Save/Cancel/Discard, real IME composition, touch/keyboard and
   narrow/light/dark/enlarged layouts. Remove/Filter select existing tags only.
4. Test SAF picker/grant/reopen/replacement/refresh, lifecycle and runtime FFI on
   the actual Android package. Retain recurrence/checklist/text/integrity/Undo and
   stable-v3 readability coverage, plus the distinct task-based UX audit required
   in [runtime QA](runtime-qa.md). Keep the approved 6GiB/2CPU/one-AVD lab cap and
   parent storage-path restrictions; no live synced user data.
5. Accept the exact Windows installed payload with manual visual/keyboard/
   assistive-technology checks. The separately scoped Windows debug route uses
   runner source `a249af55d49148db0525abd7f713ee716900353b`, application/test/native
   inputs byte-identical to e205, and selects three tag plus one historical flow.
   [Scoped run 37813474065](https://github.com/reddraggone9/tandemlog/actions/runs/37813474065)
   is pending. Its eventual receipt will be supporting debug evidence, not
   installed-release acceptance or
   runtime loaded-module enumeration. Linux narrow screenshots are not Android.

## Proposed signing and preview promotion sequence

After parent isolated regression acceptance, successful combined gates and scope
confirmation, integrate the reviewed executable candidate into refreshed main.
Keep notes/media on their separate reviewed docs branch; the existing publication
workflow can pin a later docs-only dispatch source without rebuilding an accepted
signed payload. Recheck the main merge diff and build floors first: 45 was the
verified floor when build46 was chosen, but another candidate could consume 46.
Reconfirm stable v2026.10.1 and preview v2026.10.2-rc.3; do not overwrite either.

Use the existing main-only **Build signed candidate** workflow without weakening
source/owner-pin/version/full-matrix/native/installation gates. It will rerun the
complete matrix and produce a non-debuggable owner-signed Android release plus
the exact desktop artifacts. Record the final source, workflow/run, checksum,
signer, package/version/build and payload/notice identity. Accept those exact
signed/installed artifacts on Android and Windows; the debug results above do not
transfer their byte identity. Artifacts expire after five days: if expired, rebuild
and repeat exact-artifact native acceptance.

Before publication obtain a fresh parent quota read; this consumer has no callable
quota tool. Last reported 72% has no precise reading timestamp and does not satisfy
the fresh publication gate. Also confirm final native/manual/UX acceptance and the
independent release-notes/media review against the actual final executable range.
The separate notes branch covers published 5ac35da→e205; any later executable diff
requires another covered-range review. Documentation-only corrections must retain
the accepted notes/media identity and review record.

Only then dispatch **Experimental prerelease** on reviewed main with expected tag
`v2026.10.2-rc.4`, the successful signed-candidate run ID and the actual accepted
APK SHA256. The workflow consumes accepted artifacts without rebuilding, pins
notes to its dispatch commit and publishes prerelease=true/latest=false. No signing
or publication has occurred in this handoff. Stable feature promotion remains
unauthorized.
