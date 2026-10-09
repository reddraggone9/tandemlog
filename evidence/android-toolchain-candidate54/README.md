# Android toolchain candidate54: source audit and hosted provenance

The approved dependency pair is AGP 9.2.1 and Gradle 9.4.1, retaining Kotlin 2.4.20.
PR 4 integrated the reviewed tree at `912a4a28fda84399294ed15717ca181f0140d6eb`.
The compiled candidate source is **`71b841fe9dba1b46e86de6c055ce56df4a978784`**,
version **2026.10.3/build54**. This documentation commit is not another compiled
application. It does not change main, application code, version, workflows or
signing policy.

[Candidate 37987187103](https://github.com/reddraggone9/tandemlog/actions/runs/37987187103)
completed successfully: preflight, Android, Linux, Windows and owner-signed
Android jobs all passed. Push CI 37987154935 also passed at the same source.
The signed job 114021013014 reports successful `assembleRelease` in 264.2 seconds,
certificate/package/version/nondebuggable/universal-ABI verification, packaged
native-library and exact-notices verification, signing-material cleanup and
artifact upload. The unchanged Flutter release configuration enables
minification and application resource shrinking; quiet logs do not enumerate
individual R8 tasks. Hosted success does not establish native device acceptance.

## Exact hosted artifact and limitations

- [android-release / 11645201303](https://github.com/reddraggone9/tandemlog/actions/runs/37987187103/artifacts/11645201303):
  30,370,014 ZIP bytes, expires 2026-10-14T20:58:25Z.
- GitHub-reported ZIP SHA256:
  `c433a70f745a85d5fe4d2303f539705bcebd9befa7f45b545c51138e26e06143`.
  The independently inspected upload log matches this ID, size and digest.
- Owner certificate pin:
  `0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d`.
- Cloud ZIP materialization returned HTTP 403. No downloaded ZIP/APK bytes,
  inner APK hash, ZIP-member verification or local signer re-verification is
  claimed. Metadata and selected signed-log lines (trailing whitespace normalized) are included; full decoded
  logs remain available at the signed job.

Latest parent steering requests **one combined storage-migration plus dependency
release first**, with food deferred. Candidate54 establishes the integrated
toolchain and signed packaging result. **No duplicate build54 native lab run or
standalone dependency publication is requested.** Its seven native checks in
[the handoff](candidate54-handoff.json) are historical references to rebind,
together with migration preservation gates, to the exact combined candidate.
Successful-candidate floor is now 54; the combined candidate must use 55 or higher.
Parent owns its source integration, candidate dispatch, exact artifact/native
acceptance and fresh quota/publication clearance. No release was published here.

## Actual source audit and independent review

[Audit summary](audit-summary.json) distinguishes initial execution gates,
incremental discovered-input gates, observed graphs/payloads after execution,
and post-dispatch Gradle/R8 comparison extensions. It records actual official
source comparisons, not just compatibility documents, tests or version-bump
review: AGP’s 287 changed main-plugin entries; the complete Gradle’s 2,584 changed-path
inventory with 75 downloaded exact files/42 focused paths; R8’s 167 changed entries
and 39 focused changed-file diffs. Execution, network/download/authentication,
signing/archive, native-loader and shrinker paths received focused review.
No confirmed security/product must-fix was found in inspected paths. This is
not exhaustive third-party, C++/optimizer or reproducible-binary certification.

The original independent source, Gradle, R8, integration-version and final
summary/policy/hold review receipts are preserved byte-for-byte. Their pending
candidate wording describes their review time; the final hosted handoff
supersedes that state. [Portable mapping](portable-evidence-map.json) explains
private historical paths and official-source references. Raw upstream source,
APK binaries, private signing material and the entire private log are omitted.
[Prior local evidence](../android-toolchain-maintenance/README.md) contains
selected artifact/class/task graphs and debug/native/test receipts.

The [final independent handoff review](independent-candidate54-handoff-review.json)
approves the hosted run/artifact/log/source bindings after explicitly deferring
build54 native checks to the combined candidate. No must-fix remains. It does
not attest unavailable archive/APK bytes or native acceptance. [SHA256SUMS](SHA256SUMS)
binds the portable package; original receipt input hashes remain unchanged.

[PR 1/2 holds](bot-holds.json) remain unchanged: newer requested versions still
require a supported coordinated Kotlin/Flutter/AGP/Gradle pair, exact upstream
audit and actual candidate/native validation. Auto-rebasing is not acceptance.
[The ongoing policy](ongoing-audit-policy.json) states routine dependency work
and the security/product/storage/signing/unsupported-boundary exceptions needing
decisions. It does not authorize bypassing native or publication gates.
