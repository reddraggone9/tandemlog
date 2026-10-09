# Coordinated Android toolchain maintenance — 2026-10-09

Status: isolated evaluation; no merge or release acceptance. Baseline is
`d93b6329c91559051d46915fc7a8114d17565cb8`, whose application remains stable
2026.10.2/build53 from `687163b1f9c95fe8dee1dffa0775ee7fe4cd3884`.
The executable proposal at `43d49d9b027aad099a7aa8e3e77ba4c01ab2b3ce` changes
AGP 9.1.0 → 9.2.1 and Gradle 9.3.1 → 9.4.1 together, adding the official
distribution SHA-256. Kotlin 2.4.20 and Flutter/pub/Cargo/SDK/NDK selections
are retained.

## Compatibility and held bot proposals

[PR #1](https://github.com/reddraggone9/tandemlog/pull/1) proposes AGP 9.4.1;
[PR #2](https://github.com/reddraggone9/tandemlog/pull/2) proposes Gradle 9.8.0.
Both remain outside Kotlin 2.4.20's published fully supported matrix
(AGP through 9.3.1, Gradle through 9.7.0). This is a support boundary, not
proof that every newer combination fails. AGP 9.4 also requires Gradle 9.6,
so applying #1 alone to the existing wrapper is incompatible.

The smaller pair uses AGP 9.2's minimum/default Gradle 9.4.1. It retains
Build Tools 36.0.0, NDK 28.2.13676358, compile/target SDK36 and JVM17/JDK21.
AGP 9.2.1 fixes the R8 `RecordTag` class-access issue. Choosing AGP 9.3.1
would increase the change and introduce its new optimization DSL. Later 9.3
patch notes list D8/R8 defects, including a slowdown in D8 9.2.14, which this
proposal also embeds. The smaller step does not establish immunity to those
issues; native runtime and release gates remain necessary.
Gradle 9.4.1 fixes its initial 9.4.0 Kotlin variant/capability regression.

Gradle's embedded Kotlin changes 2.2.21 → 2.3.0. The pinned Flutter included
build consequently selects another Kotlin compiler/plugin scope despite its
unchanged explicit 2.2.20/2.0.0 requests. Main KGP 2.4.20's matrix does not
establish whole-build support: the independently selected 2.3.0 scope is
outside that KGP version's fully supported Gradle range, even though Gradle
deliberately embeds it. Effective resolution and actual compilation must be
measured. Flutter's version suggestion constants also do not promise broader
Flutter compatibility.

Official sources checked on 2026-10-09:
[Kotlin matrix](https://kotlinlang.org/docs/gradle-configure-project.html),
[AGP 9.2 notes](https://developer.android.com/build/releases/agp-9-2-0-release-notes),
[AGP 9.3 notes](https://developer.android.com/build/releases/agp-9-3-0-release-notes),
[AGP 9.4 notes](https://developer.android.com/build/releases/agp-9-4-0-release-notes),
[Gradle 9.4.1 notes](https://docs.gradle.org/9.4.1/release-notes.html),
[Gradle upgrade guide](https://docs.gradle.org/9.4.0/userguide/upgrading_version_9.html),
[official distribution checksum](https://services.gradle.org/distributions/gradle-9.4.1-all.zip.sha256).

## Source, bootstrap and native review

[Evidence](../evidence/android-toolchain-maintenance/) binds exact downloaded
metadata/source/binary identities and independent focused source review.
The verified 238,160,795-byte Gradle all-ZIP has SHA-256
`708d2c6ecc97ca9a11838ef64a6c2301151b8dd10387e22dc1a12c30557cab5b`.
The retained Flutter-generated wrapper JAR is unchanged at
`16caeaf66d57a0d1d2087fef6a97efa62de8da69afa5b908f40db35afc4342da`;
independent bytecode inspection confirms it checks the checksum before unzip.
A scratch wrong-checksum control rejects the exact distribution before execution.

Review covered AGP/Google transitive source changes, JNI merge/producer wiring,
Cxx process execution, SDK download boundaries, signing/archive libraries,
R8 keep rules, Kotlin compiler/BTA/classloader/reporting paths and Gradle
bootstrap/native loaders. Signing/archive downloader source is substantially
unchanged; zipflinger only exposes an existing entry attribute getter.
AGP's builder embeds R8 9.2.14 at revision
`b159b01e1cdc38c1106be42aeebfb7f44397dad1`; its official source archive was
inspected. Aapt2 selects Google Maven 9.2.1-15009934, with Linux executable
SHA-256 `e4dff6060827a3e401bce376e47916f2f93a89602af54973ffd3fdfc2528be3f`.
Gradle's bundled native libraries are inventoried. All 20 Kotlin 2.3.0 compiler
native resources match the previous reviewed 2.4.20 bytes.

The guard also stopped at deferred lint 32.2.1 annotation-extraction inputs.
Their exact Google Maven closure was reviewed before retrying. IntelliJ's
changed ZIP reader becomes explicitly read-only, the repackaged compiler
changes analysis/API code, and UAST source is unchanged. All 34 bundled
IntelliJ native resources and loader/service bytecode match the 32.1.0
baseline; non-Google dependency requests are unchanged. Selected lint inputs
do not establish that every lint/compiler path executes. The version-only
filter also catches unchanged kxml2 2.3.0; its exact Maven identity and parser
bootstrap were checked before adding its hash, without relaxing the filter.

This is a focused execution-boundary review, not an exhaustive upstream audit.
Fresh private caches, disabled FUS/reporting/scans/remote caches, no owner
signing/publication credentials, locked native inputs and selected-artifact
hash checks constrain local execution. The observer is private evaluation
instrumentation, not a committed production dependency verification policy.
It records loaded plugins after evaluation; source review authorizes plugin
execution, while subsequent resolution guards protect compilation consumers.
The private guard matches filename/hash pairs for explicitly filtered changed
versions; it does not enforce every dependency or bind repository/group
provenance. Independent review also inspects the recorded actual coordinates.

## Validation and remaining gates

Locked Dart resolution leaves the package graph unchanged. Formatting and
analysis pass; all 647 production-native-backed Flutter tests, four Rust tests,
107 native contract tests and 50 packaging/release helper tests pass
(no skips). Native contract tests regenerate a synthetic
performance receipt; that generated file is retained privately and restored
in the repository.

Android debug packaging and its immediate warm repeat pass. Both exact APKs
are 164,971,263 bytes with SHA-256
`1c375fc768f1d958f497519aa1570fb2957596584a1254e908628f0e3bc2bea9`
and identical 13 native payload entries. Both pass signature verification,
required native ABIs, exact notices, ELF machines/exports and 16 KiB ELF/ZIP
alignment gates. These use an ephemeral private debug signer, not the owner
release signer. The `cold` receipt is the first successful application package
after private bootstrap/setup/guard retries, not a pristine empty-cache proof.

Effective selected graphs contain 246 app tasks across 60 implementation
classes, plus the eight-task Flutter included build. Independent review finds
no KAPT, Kotlin Native, JS/Node/browser or ABI-plugin activation. Independent
final code, documentation, effective-artifact and package review finds no
must-fix. Hosted all-platform CI remains a separate submission gate.

Local setup uses a private Java21 module-launcher overlay because this cloud
JDK lacks javac, jar, jlink, javap and jmod launchers. Explicit Java proxy
configuration, SDK35 for the unchanged JNI package, SDK36, Build Tools36
and exact NDK28.2 are host accommodations; repository selections are unchanged.

Release shrinking and exact Android runtime/ABI/SAF workflow acceptance remain
separate gates. AGP 9.2 changes R8 wildcard keep-attribute semantics, so debug
packaging cannot establish release shrinking behavior. The existing release
signing guard is retained; no stable-version bump, live-data access, merge,
release, or native-lab operation belongs to this preparation.

Owner: Android toolchain maintainers. Revisit after newer Kotlin/Flutter
support matrices cover the held bot versions, and after exact platform gates.
