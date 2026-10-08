# Final integration plan — 2026-10-08

Status: preparation only. The current combined candidate stays frozen throughout
local Android acceptance. No merge, build, publication or autocomplete adoption
is performed by this plan. Lee approved a persistent 6 GiB emulator cap with
2 CPU, no host swap and one AVD; the local task owns headroom checks and the
narrow configuration change.

## Frozen acceptance target

| Binding | Exact value |
| --- | --- |
| Candidate branch | `preview/checklists-queued-fixes` |
| Frozen head | `a960c882c06c018a1e721e7459f08dbe4d17bed3` |
| Compiled application/test source | `17ae5e5619bbd890a9778ffe39b1c94156086bb3` |
| Successful full CI | [37747198468](https://github.com/reddraggone9/tandemlog/actions/runs/37747198468) |
| Android artifact ID | `11536038281` (`android`) |
| Android archive bytes | `80369328` |
| Android archive SHA256 | `be3e8c5faeb72dd5a290f7519ed398d6f7cccaa1003ace84bb5b561cd655cf4f` |
| Actual APK bytes / SHA256 | `164893808` / `ac31725fd24dae37798091b00a192d5f0d5e3ea1c991d503ddc8aa2d9b87be91` |
| Debug signer SHA256 | `ce6957a5935f04f30e1d6273e9aad82d87f58000333423c4a6bd6555e8c65677` |
| Package / version / code | `com.reddraggone9.tandemlog` / `2026.10.2-rc.3` / `45` |
| Windows artifact ID / archive SHA256 | `11536113401` / `e4aad43623e899d944c93d365d501815e5697eef7693699b9c04792d3c32926c` |
| Linux artifact ID / archive SHA256 | `11537062777` / `08ed6bbbb6d767453d448c9cc8882855de550817cec9ef77203a8359e1eb19c9` |

Fresh remote and local reads confirm the frozen head. Its delta from compiled
source 17ae5e5 is evidence-only; application, tests, native code, dependency and
platform/build inputs are unchanged. The archive digest above identifies the
ZIP, not its APK member. Both archive and APK bytes were materialized and verified;
the APK matches its hosted checksum/signature report and passes static packaged
native and signature checks. The local task must match its own installed APK to
that exact hash before recording runtime acceptance. See the
[final-source receipt](queued-fixes-final-ci-receipt.json) and
[affected-flow handoff](queued-fixes-native-acceptance.md). The frozen candidate's
own README contains historical pending statuses; the separately updated receipts
record terminal CI and hosted Windows results without changing the candidate.

## Integration sequence after this acceptance run

1. Finish the exact 17ae5e5 APK's Android acceptance and retain its checksum,
   signer, device/API/AVD, resource settings, startup/runtime ABI, workflow and
   SAF/lifecycle/IME observations. Keep every profile and canonical folder
   synthetic. Record failures before changing source; any necessary fix belongs
   on a new isolated branch and invalidates acceptance for the changed artifact.
2. Keep the original candidate and its accepted artifact immutable. Prepare a
   separate integration branch after acceptance. Reviewed Kotlin head
   `1b8f0cc5c6eeb302519231d7269ee37a529e36d0` already descends directly from
   a960c88; its merge base with that candidate is exactly a960c88. Preserve this
   reviewed ancestry and evidence instead of stacking the old save-delta,
   cache-only or autocomplete experiments. Compare the then-current main before
   proposing a merge, and review any intervening source or resolved conflicts.
3. Include the narrow Kotlin update: main Android KGP 2.4.0 to 2.4.20, retaining
   AGP 9.1.0, Gradle 9.3.1, Flutter/pub/Cargo/native inputs and durable v3 meanings.
   Its [reviewed report](https://github.com/reddraggone9/tandemlog/blob/1b8f0cc5c6eeb302519231d7269ee37a529e36d0/design/kotlin-2.4.20-remediation.md)
   binds full CI 37753131078 to ac20d4e and cold/warm full CI 37755702541 to
   45eb9e8. Both passed every platform; independent actual graph/artifact review
   has no must-fix. Eleven observed 2.4.20 binaries fit the 23-entry reviewed
   inventory; 259 selected tasks span 64 implementation classes, all observed
   classes Android/JVM. Flutter's separate
   included-build Kotlin remains 2.2.21. The evaluation observer is branch-scoped;
   moving source to a new branch does not automatically rerun its cold/warm step.
4. Resolve Android runtime acceptance for Kotlin as well. Existing verified
   45eb9e8 debug APK SHA256
   `d8a1dd334bec9ce21139c4ddd25b114e723f463ae3ca7904e58c8d15d723182c`
   can supply focused follow-up evidence if its application/build inputs match
   the proposed integration. Verify its separate debug signer and fixture
   isolation first; do not assume an in-place update from the 17ae5e5 debug APK.
   Exercise startup/native FFI, SAF grant/reopen/refresh, Kotlin-backed picker
   callbacks and the affected task/text/checklist flows. Passing the original
   Kotlin-2.4.0 APK does not accept this changed Kotlin-2.4.20 artifact.
5. Once integration scope is fixed, obtain the parent's fresh quota read before
   a publication or major new start. Choose a valid new preview version and
   monotonic build using fresh published-tag and successful-candidate floors;
   the internal `2026.10.2-rc.3+45` QA APK is not a new public release. Prepare
   the exact merge/version change for independent code, compatibility/security
   and UX review. Use existing all-platform signed-candidate gates for the actual
   changed source; do not repeat completed suites merely to refresh status.
6. Build the owner-signed candidate through the established main-only workflow
   after integration is authorized and reviewed. Verify source/version/signers,
   native libraries/notices and every artifact checksum. Complete native
   acceptance on that exact non-debuggable Android APK and the exact installed
   Windows release payload. Earlier debug tests and source equality supply
   supporting evidence; they do not substitute for final-artifact acceptance.
7. Independently review concise release notes and real dark-theme Before/After
   media against the actual release commit range. Publish the authorized preview
   only after all gates pass, consuming those accepted artifacts without a
   rebuild. Stable feature promotion still requires Lee's explicit acceptance.

## Separate choice and remaining work

Autocomplete A/B previews are delivered and neither is adopted. If Lee chooses
an option, handle that implementation as separately scoped work with fresh quota,
tests-first checks and independent native/IME/accessibility review. It changes
the candidate and needs its own artifact acceptance; do not silently fold it into
the frozen run or call trial media final production evidence.

Remaining external gates are the current local Android acceptance, the focused
Kotlin Android runtime follow-up, installed Windows/manual visual/assistive
technology acceptance, and final signed-artifact/release-note/media review. The
parent owns those decisions and device/resource configuration. Live synced user
data remains outside this plan.
