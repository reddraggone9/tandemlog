# Kotlin and Android build dependency audit — 2026-10-08

Scope: read-only inspection of baseline `eb68b46259f745e86ec9f41c144d473f19d0fb0f`, official metadata/source and current GitHub PR receipts. No dependency resolution, installation, build, upgrade, merge or publication occurred. The candidate and other worktrees remain unchanged. [Observed upstream inputs](../evidence/dependency-audit/upstream-observations.json) retain exact metadata identities; these hashes are observations, not publisher-signature verification.

## Recommendation

Prepare a separate **Kotlin Gradle plugin 2.4.0 → 2.4.20** evaluation while keeping AGP 9.1.0 and Gradle 9.3.1. This is the narrow stable version containing the verified security fix and lies within Kotlin's published compatibility matrix. Kotlin 2.4.10 does not fix this issue. Neither existing dependency PR supplies this remediation. The recommendation selects the evaluation scope; it does not approve executing the complete new artifact graph or declare all older Kotlin tooling removed.

Defer independent merges of [AGP PR #1](https://github.com/reddraggone9/tandemlog/pull/1) and [Gradle PR #2](https://github.com/reddraggone9/tandemlog/pull/2). A broader tooling update needs one coordinated proposal with exact versions, source/artifact review and Android acceptance.

## Current selections and trust boundaries

| Component | Baseline selection | Relevant distinction |
| --- | --- | --- |
| App Kotlin Android plugin | 2.4.0 in `android/settings.gradle.kts` | `apply false` is not evidence that it is unused: pinned Flutter code applies `kotlin-android` to Android projects when built-in Kotlin is disabled. |
| AGP | 9.1.0 | Google POM also declares KGP/stdlib 2.2.10; declarations do not establish final conflict resolution. |
| Wrapper distribution | Gradle 9.3.1 `all.zip` | No `distributionSha256Sum`; only wrapper properties are tracked. The older inventory's locally measured wrapper JAR is not a committed binary pin in this fresh checkout. |
| Flutter | 3.47.5, commit `6a19cca56475dbfba1478ee68d7bd0c2ef891da1` | Included Gradle build independently declares Kotlin JVM 2.2.20 and KGP implementation 2.0.0. A root settings edit does not rewrite those SDK declarations. |
| Android plugin subprojects | file_selector/url_launcher declare KGP 2.3.0; jni/jni_flutter use Android library plugins; path_provider is a Dart/JNI plugin | Inspected existing packages match the committed pub lock. Final build/plugin classloader selections remain unmeasured. |
| Java / native packaging | CI Temurin 21, JVM bytecode 17; explicit app NDK 28.2.13676358 | App `preBuild` runs repository `tool/build_text_engine.py`, with locked offline Rust inputs and all three Android ABIs. These inputs are unchanged by the proposed Kotlin-only edit. |

`android.builtInKotlin=false` and `android.newDsl=false` remain enabled opt-outs. Enabling AGP built-in Kotlin or migrating the Flutter DSL is separate work. No Gradle dependency locks/verification metadata are committed. No remote build-cache configuration or KAPT/annotation-processor configuration was found in the app, pinned Flutter Gradle build or inspected current Android plugin build files. This static search does not prove a resolved task graph.

## Verified security claim and exposure

[CVE-2026-53914 / GHSA-r937-wjx7-w2jp](https://github.com/advisories/GHSA-r937-wjx7-w2jp) affects `org.jetbrains.kotlin:kotlin-gradle-plugin` before 2.4.20-Beta1. JetBrains' [fixed issues](https://www.jetbrains.com/privacy-security/issues-fixed/) public data identifies stable 2.4.20 as the fix. This is a build-tool vulnerability, not a Kotlin stdlib runtime vulnerability or a canonical task-log parser issue.

The exact [upstream fix `bf51df665b458fda7c3eaf436c4d88dc119d7ec6`](https://github.com/JetBrains/kotlin/commit/bf51df665b458fda7c3eaf436c4d88dc119d7ec6) replaces unrestricted KAPT incremental-cache deserialization with permitted-class checks, rejects proxy classes, checks the expected cache type and discards rejected private build cache files. Its negative tests ensure a supplied object's deserialization callback is never invoked. GitHub ancestry inspection confirms this fix is an ancestor of stable 2.4.20, tag commit `890ac1d94fdb80eb85f0eeb5be5e4352df987b2f`.

The declared 2.4.0 dependency is in the affected range. Exploitation of this specific path has not been demonstrated in Tandemlog: the inspected configuration does not enable KAPT. Older Kotlin declarations in Flutter's included build and AGP/plugin metadata must be accounted for before claiming complete dependency remediation. Do not infer that stdlib 2.2.10 or every older compiler component executes the affected KAPT path simply from its version.

GitHub's repository alerts endpoint explicitly returned **“Dependabot alerts are disabled for this repository”** (HTTP 403). That is a monitoring gap, not a clean security scan. The public advisory API still returns this KGP advisory. Repository settings were not changed.

## Open PRs and compatibility

| Option | Exact read-only observation | Assessment |
| --- | --- | --- |
| PR #1, head `0cd4f59b60fcb7c617217a28d0855deaf6dd9dae` | One-line AGP 9.1.0 → 9.4.1; Android CI failed in [run 37211297807](https://github.com/reddraggone9/tandemlog/actions/runs/37211297807), Linux/Windows passed. | AGP 9.4 requires Gradle **9.6.0 minimum**; current 9.3.1 is below it. Downloading the failed job log returned HTTP 403, so the actual failure cause was not confirmed. AGP source version-admission code was inspected independently. |
| PR #2, head `f4306d3cda003455650894966119cb5079c51c6b` | One-line wrapper URL 9.3.1 → 9.8.0; all three old CI checks passed in [run 37211317640](https://github.com/reddraggone9/tandemlog/actions/runs/37211317640). | Does not update KGP. Gradle 9.8 exceeds the fully supported ceiling of both KGP 2.4.0/2.4.10 (9.5) and 2.4.20 (9.7). Passing that older build is evidence of that run, not complete compatibility or security review. |
| Narrow remediation | KGP 2.4.20 + existing AGP 9.1.0 / Gradle 9.3.1 | Within published KGP range: Gradle 7.6.3–9.7.0, AGP 8.5.2–9.3.1. Exact graph, provenance and build/runtime gates remain pending. |
| Coordinated latest PR targets | AGP 9.4.1 + Gradle 9.8.0 + fixed KGP | Satisfies AGP's Gradle minimum but exceeds KGP 2.4.20's published fully supported ranges. Requires explicit compatibility investigation; neither bot PR alone establishes a suitable combination. |

The two PRs target current main base `104e0914572f43c4d1f25e232792ec33e2b0a5e2`; their October 4 checks precede the current feature candidate. Kotlin permits newer Gradle/AGP versions with possible unsupported features/deprecations; exceeding the matrix is not proof of inevitable failure. If broader maintenance is needed, choose a version intersection first rather than treating the latest bot versions as mandatory. [KGP matrix](https://kotlinlang.org/docs/gradle-configure-project.html), [AGP 9.4 requirements](https://developer.android.com/build/releases/agp-9-4-0-release-notes), [Kotlin bytecode/D8/R8 requirements](https://developer.android.com/build/kotlin-support).

## Artifact, transitive and execution review

Official Maven Central KGP POM/module metadata was compared for 2.4.0 and 2.4.20. The eight direct POM dependency names/scopes remain the same, with aligned Kotlin versions updated; module metadata additionally retains its plugins BOM and Gradle 8.13 variant. Compiler and KAPT artifacts are task-selected beyond this POM surface. Thus this is not a verified complete resolved graph.

Official Google AGP 9.1.0/9.4.1 POMs and source archives were read without loading classes. AGP-owned builder/API/artifact components change together, Android tools 32.1.0 → 32.4.1, and aapt2 metadata 9.1.0-14792394 → 9.4.1-15978811. The listed non-AGP dependency versions, including KGP/stdlib 2.2.10, remain unchanged at this POM layer. Native AAPT2 tool payloads, final R8/D8 selections and all downstream binaries have not been verified. The source archives' version admission code rejects Gradle below `SdkConstants.GRADLE_LATEST_VERSION`; the public minimum independently rules out PR #1 alone.

Gradle 9.8's [distribution catalog](https://github.com/gradle/gradle/blob/v9.8.0/gradle/dependency-management/distribution.versions.toml) selects embedded Kotlin 2.4.10. A wrapper update therefore does not itself remediate this KGP advisory. The upstream compare contains 7,276 commits and GitHub's file response is capped at 300; it was not an exhaustive source review. KGP 2.4.0 → 2.4.20 likewise has a truncated 300-file compare. The identified fix was reviewed completely; the entire new release graph was not approved for execution.

Before any wrapper change, bind the exact distribution to its official checksum and verify the generated wrapper JAR against Flutter/Gradle provenance. The observed official Gradle 9.8.0 **all ZIP** checksum is `46ac66d47f30f3dacfdf306e0b714a91a34fb94a22ba0a744b280933f47bc0cf`; the ZIP itself was not downloaded. Do not use the checksum for `bin.zip`. [Wrapper verification](https://docs.gradle.org/current/userguide/gradle_wrapper.html). Kotlin's [publisher signing key](https://kotlinlang.org/docs/security.html) and signatures should be checked for the exact selected artifacts; this audit did not perform signature verification.

## Gates for a later authorized evaluation

1. Freeze a minimal settings-only Kotlin proposal. Inventory the complete app/subproject and Flutter included-build plugin/compiler/KAPT/runtime graphs and selected variant hashes. Review changed JVM Gradle/compiler build paths and artifact download behavior before execution; keep JS/Wasm/native compiler experiments disabled. Verify Maven signatures/content identities. Explain any older selected KGP and whether KAPT is enabled before asserting closure of the advisory.
2. Evaluate with an isolated private Gradle home, synthetic profile/folder, reviewed pinned Flutter/JDK/SDK/NDK/Rust inputs and no signing/publication secrets. Record cold and warm debug builds and affected Kotlin/SAF compilation tests. Confirm the effective R8/D8 versions meet Kotlin 2.4 requirements; native text libraries/SQLite and required APK ABI/alignment/notices gates must still pass.
3. Run exact native Android synthetic workflows: SAF duplicate-name/permission errors, delayed append/restart, text/checklist Save and Undo, recurrence/peer replay, IME and actual UI acceptance. Frozen v3 hashes/IDs/clocks/fixtures must remain unchanged. Release/signing acceptance remains a separate coordinator-owned gate.

Audit owner: dependency maintainers/coordinator. No merge-ready update is produced here. The narrow remediation is the preferred next proposal; full artifact/signature/graph review, effective KAPT exposure and native execution evidence are the remaining blockers to adopting it.
