# Dependency inventory — 2026-10-04

Observed source: `fa4b166a5fb2ea43fe44cd2c8117cc91993f3921` (HEAD when read). App version `2026.10.2-rc.1+43`. Report only: no dependency resolution, build, test suite, repository update or publication performed for this inventory.

## Direct application dependencies

| Dependency | Declared | Resolved | Purpose |
|---|---|---|---|
| flutter | `sdk: flutter` | Flutter SDK 3.47.5 (lock placeholder 0.0.0) | UI, services and platform integration |
| sqlite3 | `^3.7.0` | 3.7.0 | Rebuildable local SQLite cache; native asset hook |
| ffi | `^2.2.0` | 2.2.0 | Native POSIX/Windows durability calls |
| path_provider | `^2.1.5` | 2.1.6 | Per-user settings/cache directories |
| file_selector | `^1.0.4` | 1.1.0 | Desktop folder selection |
| crypto | `^3.0.6` | 3.0.7 | Canonical SHA-256 event chains and cache/settings identifiers |
| uuid | `^4.5.1` | 4.6.0 | Task/event/device identities |
| url_launcher | `^6.3.2` | 6.3.2 | Open task workspace in OS folder manager |
| timezone | `0.11.1` | 0.11.1 | IANA zone interpretation for schedule/availability; bundled database 2025c |

## Direct development dependencies

| Dependency | Declared | Resolved | Purpose |
|---|---|---|---|
| flutter_test | `sdk: flutter` | Flutter SDK 3.47.5 (lock placeholder 0.0.0) | Widget and unit test harness |
| integration_test | `sdk: flutter` | Flutter SDK 3.47.5 (lock placeholder 0.0.0) | Native workflow tests |
| flutter_lints | `^6.0.0` | 6.0.0 | Static analysis rules |
| fake_async | `^1.3.3` | 1.3.3 | Controlled time in tests |

SDK constraints differ: manifest Dart `>=3.9.0 <4.0.0`; resolved graph Dart `>=3.12.0 <4.0.0`, Flutter `>=3.44.0`. Actual pinned toolchain is Flutter 3.47.5 / Dart 3.13.4. Manifest minimum alone does not describe this resolved build.

## Native dependencies and provenance

- SQLite is **3.53.4**, obtained from the default `sqlite3` 3.7.0 precompiled hook. Existing `build/linux/x64/release/bundle/lib/libsqlite3.so` was queried via `sqlite3_libversion()` and SHA-256 hashed, without rebuilding. Its `0f947ebe629e8d9d02d7f408bef36e056bfc63ea47e02e0d45a7bae454f04ace` matches the package's `lib/src/hook/asset_hashes.dart` x64 Linux entry. This is local existing-bundle evidence, not an attestation for future CI artifacts.
- Hook release tag: `sqlite3-3.7.0`; default download: `https://github.com/simolus3/sqlite3.dart/releases/download/$RELEASE_TAG/$FILENAME`. Package `hook/build.dart` and `lib/src/hook/compile/description.dart` choose/download assets and validate hashes, including cached bytes. No app `hooks.user_defines` override exists. The source-compilation fallback's old `sqlite-amalgamation-3500200.zip` is **not** evidence of the default bundled version.
- Relevant pinned default assets: arm Android `a42fa9d0f5c006d30b000d4904bc497705191c5d7330b178618546004295bb49`; arm64 Android `0c2d3bfc8c87abceb21ed72a4bb49964121c5fe1a8ef3848d83ba907d01b6161`; x64 Android `949965f0eba976f707ae364cdcb42c342b5f0626081f8d7f0378fb7b52848772`; x64 Windows `98b4be674137b85ec111a7a29223e87aa41c3e964d61f73602471ddd7b9c56ce`. SQLCipher/OpenSSL/SQLite3 Multiple Ciphers entries exist upstream but the app does not select them; do not inventory those as shipped app dependencies.
- Native/platform transitive Dart packages are fully listed below. Of particular interest: `hooks` 2.2.0, `code_assets` 1.2.1, `native_toolchain_c` 0.19.3, `jni`/`jni_flutter` 1.0.3, `jni_util` 1.0.0, `objective_c` 9.5.0, and federated file/path/URL implementations. These can introduce executable build hooks or platform build behavior despite not being direct app entries.
- Linux runner CMake directly requires GTK3 via pkg-config; OS libraries and GTK transitives are system/runtime dependencies, not pub lock entries. Windows links the OS runner APIs and depends on the MSVC runtime selected by the actual CMake compiler. Installer verifies that prerequisite and points to Microsoft's redistributable; it does not bundle/download it. Android SAF folder integration is repository Kotlin/Android framework code, not a separate third-party sync library.

## Build and packaging dependencies

| Component | Current source selection | Pin/provenance and limits |
|---|---|---|
| Flutter | 3.47.5 stable | `.github/actions/setup-flutter/action.yml` clones official `flutter/flutter` tag and checks exact commit `6a19cca56475dbfba1478ee68d7bd0c2ef891da1` |
| Flutter engine | `af7e796e161ae0bb1ff0758c71a7105418bd9ded` | `bin/internal/engine.version` in pinned SDK; observed engine artifact hash `ab598368592da0064197e2bc15c7f5b0a2c6bb1f` |
| Dart / DevTools | 3.13.4 / 2.60.0 | Bundled with pinned Flutter; SDK packages' 0.0.0 lock values are placeholders |
| Gradle wrapper | 9.3.1 `all.zip` | `android/gradle/wrapper/gradle-wrapper.properties`; **no `distributionSha256Sum`**; wrapper JAR SHA-256 `16caeaf66d57a0d1d2087fef6a97efa62de8da69afa5b908f40db35afc4342da` measured locally |
| Android Gradle Plugin | 9.1.0 | `android/settings.gradle.kts`; Google/MavenCentral/Gradle plugin repositories, no committed Gradle dependency lock or verification metadata found |
| Kotlin Android plugin | 2.4.0 | Same settings file; explicit declaration (application uses Flutter Gradle plugin rather than applying Kotlin plugin directly) |
| Flutter Gradle loader/plugin | loader 1.0.0; implementation from SDK | Included build at pinned SDK `packages/flutter_tools/gradle` |
| Android SDK | compile 36 / target 36 / min 24 | Inherited from pinned `FlutterExtension.kt`; app does not hardcode these |
| Android NDK | 28.2.13676358 (r28c) | Inherited from pinned `FlutterExtension.kt`; local SDK source.properties matches |
| Android signing inspection tools | Build-tools 36.0.0 | Workflows/scripts require this exact path; package bytes from SDK/runner not repository hash-pinned |
| Java | CI Temurin major 21; bytecode target 17 | `setup-java` is SHA-pinned but `java-version: '21'` resolves changing patch releases |
| Linux compiler/build | clang, CMake, ninja, pkg-config, GTK3 | Unversioned apt install on `ubuntu-24.04`; CMake minimum 3.13 (Flutter file 3.10) |
| Windows compiler/build | MSVC, CMake, Inno Setup 6 | `windows-2022` image tools; CMake minimum 3.14; script checks installed ISCC major directory, not exact patch; runtime minimum derived from compiler metadata |
| Linux packaging | Flatpak, GNOME Platform/SDK branch 50 | `packaging/linux/build-flatpak.sh`; Flathub branch pinned, OSTree revisions float; image/apt Flatpak not exact-pinned |
| Python / GitHub CLI / shell | Image-provided | Python uses standard library tools; no pip requirements/package manifest found. Publication uses image `gh`, Bash/PowerShell |

The pinned Flutter source provides strong framework selection, but engine/Dart binaries and host build tools still need run-level provenance. Pinning the app's Android signing certificate is identity verification, not a dependency pin, and it was not changed here.

## GitHub Actions dependencies

| Action | Exact committed pin | Version annotation in repository | Purpose |
|---|---|---|---|
| actions/checkout | `3d3c42e5aac5ba805825da76410c181273ba90b1` | v7.0.1 | Source checkout |
| actions/upload-artifact | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` | v7.0.1 | Validation/candidate artifact retention |
| actions/download-artifact | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` | No tag annotation found; commit is exact current version | Fetch exact candidate payload for promotion |
| actions/setup-java | `de7274f081f381c8f8158605e0321c36c376e2e6` | v6.0.1 | Android Java installation |

Local setup-Flutter action and reusable validate workflow resolve with repository source; they are not independent third-party action versions. Action tag annotations above are local documentation, not separately verified tag attestations.

## Installed local host snapshot (not CI image identity)

Observed under `/workspace/toolchains/env.sh`: Clang 19.1.7, CMake 3.31.6, ninja 1.12.1, pkg-config 1.8.1, GTK3 3.24.49, Python 3.12.14, OpenJDK 21.0.12.1+1-1-deb13u1-Debian. Android cmdline-tools 22.0, platform-tools 37.0.1, emulator 37.1.11, Android-36 platform revision 2, build-tools 36.0.0, NDK 28.2.13676358. Flutter/Dart match the CI source pin. Flatpak was not on this shell PATH; Windows tools cannot be sampled from Linux. These installed versions are a local snapshot; no repository manifest pins their host package bytes. CI's Ubuntu 24.04 and Windows 2022 labels float as GitHub updates images; apt-selected package versions and Windows preinstalled patches float too.

## Update automation and coverage

Before this maintenance change, no committed Dependabot, Renovate or equivalent updater existed. The bounded configuration below is now committed; first bot execution/Gradle recognition remains unverified. Repository-level security alert/settings state is not inferred from source inspection.

Implemented initial configuration in `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: pub
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 3
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 2
  - package-ecosystem: gradle
    directory: /android
    schedule:
      interval: monthly
    open-pull-requests-limit: 2
```

Keep individual PRs initially: no automatic merge and no cross-package grouping that conceals a hook/native payload change. Existing CI validates candidates; a bot suggestion is not release acceptance. Verify the first pub PR resolves using the pinned Flutter SDK and updates the checked-in app lockfile deterministically. Verify the Gradle updater actually recognizes `settings.gradle.kts` plugin declarations and handles wrapper updates; documented support is broader than proof for this project's dynamic Flutter include-build. Wrapper updates can execute Gradle and need the same untrusted-PR boundary as other build code.

Dependabot documents `pub`, `github-actions`, and `gradle` support. It understands SHA-pinned repository actions and ignores local action references; therefore it will **not** update the custom shell-cloned Flutter tag/commit. It also does not cover this repository's apt selections, hosted runner image patch inventory, Java major-only patch selection, SDK/NDK values inherited inside Flutter, Flathub branch revisions, or native SQLite payloads independently of their parent pub package. Track those via a compact periodic manual tooling/native review, not invented Dependabot ecosystems. Flutter SDK changes need a coordinated tag+verified commit change plus review of inherited Android defaults.

## Required per-version review

1. Record old/new resolved versions, package content hashes and source repository/tag/commit. Read maintainer release notes and source diff for the exact versions, not only latest docs. Inspect all transitive lock changes; explain removals/additions and increased SDK floors.
2. Before executing a changed dependency in CI/local tools, review new/changed `hook/build.dart`, `hook/link.dart`, native sources/build scripts, plugin Gradle/CMake/CocoaPods logic, download URLs, expected hashes, selected assets and native exports. Package hashes protect selected archive identity; they do not establish trustworthy behavior. Hooks execute during compilation; action/build code can execute too.
3. For sqlite3 changes, identify bundled SQLite's real `sqlite3_libversion()`, validate target asset hashes against package hook data, inspect engine compile flags/extension choices/ABI and upstream SQLite notes; preserve schema/cache recovery and canonical replay behavior. For crypto/uuid changes, retain frozen hash/identity fixtures. For timezone changes, compare bundled IANA version and DST/ambiguous-wall-time tests before accepting changed temporal interpretation.
4. Use an isolated branch/worktree, the pinned toolchain, synthetic copied data and no publication credentials for update evaluation. Review source/hook changes first; retain only required read permissions. Don't run untrusted dependency PR code in a privileged promotion job or expose owner signing credentials. Existing release policies still control signing/publication.
5. Resolve deliberately, review lock diffs, then verify with `flutter pub get --enforce-lockfile` on a clean cache/worktree; fail rather than silently refreshing a content hash during candidate validation. Validation and signed-candidate workflows now enforce the committed lockfile; a local enforced-lockfile resolution passes with unchanged package graph. Run relevant domain/cache/widget tests, and native target/build/installer checks when changed native/tooling code warrants them. Reuse existing release gates for an actual candidate; no suite reruns were needed merely to inventory.
6. Record accepted version, provenance, relevant evidence, remaining target gaps, reviewer and revisit trigger. Update automation may open PRs; humans decide acceptance and stable release.

Primary reference checks (2026-10-04): [Dependabot ecosystem support](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories), [Dependabot configuration](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference), [Dart lockfiles and enforced content hashes](https://dart.dev/tools/pub/packages), [Dart hooks](https://dart.dev/tools/hooks). Source inspection establishes current project versions; docs establish automation and execution semantics.

## Complete resolved Dart graph and archive provenance

All hosted entries below are `https://pub.dev` package archives with their committed SHA-256. SDK entries come from the pinned Flutter SDK. This appendix distinguishes direct/dev/transitive without presenting transitive packages as direct app requirements.

| Package | Resolved | Role | Archive SHA-256 / SDK source |
|---|---|---|---|

| args | 2.7.0 | transitive | `d0481093c50b1da8910eb0bb301626d4d8eb7284aa739614d2b394ee09e3ea04` |
| async | 2.13.1 | transitive | `e2eb0491ba5ddb6177742d2da23904574082139b07c1e33b8503b9f46f3e1a37` |
| boolean_selector | 2.1.2 | transitive | `8aab1771e1243a5063b8b0ff68042d67334e3feab9e95b9490f9a6ebf73b42ea` |
| characters | 1.4.1 | transitive | `faf38497bda5ead2a8c7615f4f7939df04333478bf32e4173fcb06d428b5716b` |
| clock | 1.1.3 | transitive | `e51d50bca3217c9a9fa2b41a30e4a38971133f5f9ec7a3d57bae095007f1d28e` |
| code_assets | 1.2.1 | transitive | `bf394f466ba9205f1812a0433b392d6af280f155f56651eda7c18cc32ed493b8` |
| collection | 1.19.1 | transitive | `2f5709ae4d3d59dd8f7cd309b4e023046b57d8a6c82130785d2b0e5868084e76` |
| cross_file | 0.3.5+5 | transitive | `f141ea4f277af142a0356955707f6556f37b03947d39d55585981a06ca437bd6` |
| crypto | 3.0.7 | direct main | `c8ea0233063ba03258fbcf2ca4d6dadfefe14f02fab57702265467a19f27fadf` |
| fake_async | 1.3.3 | direct dev | `5368f224a74523e8d2e7399ea1638b37aecfca824a3cc4dfdf77bf1fa905ac44` |
| ffi | 2.2.0 | direct main | `6d7fd89431262d8f3125e81b50d3847a091d846eafcd4fdb88dd06f36d705a45` |
| file | 7.0.1 | transitive | `a3b4f84adafef897088c160faf7dfffb7696046cb13ae90b508c2cbc95d3b8d4` |
| file_selector | 1.1.0 | direct main | `bd15e43e9268db636b53eeaca9f56324d1622af30e5c34d6e267649758c84d9a` |
| file_selector_android | 0.5.2+11 | transitive | `d670cd0ce77a2e785b18d8b4d0a8d6a222d6a813ec9b7ddf2790a1b4fb6fa92c` |
| file_selector_ios | 0.5.3+6 | transitive | `97269e5307a0ab813b1fa2430bada0a96e0afb74848417f8676f64ba5de0051c` |
| file_selector_linux | 0.9.4+1 | transitive | `da76400e7872ce7637ffdce12749ec24169c25f6195c28372208e65a24bcd2ab` |
| file_selector_macos | 0.9.5+1 | transitive | `d57c62362766b5e7ae739448650b66c6aab7a68ba7ecc65e04018652645ae0f4` |
| file_selector_platform_interface | 2.7.0 | transitive | `35e0bd61ebcdb91a3505813b055b09b79dfdc7d0aee9c09a7ba59ae4bb13dc85` |
| file_selector_web | 0.9.5 | transitive | `73181fbc5257776d8ecaa6a94ab3c8e920ad143b9132a6d984a9271dfc6928d3` |
| file_selector_windows | 0.9.3+6 | transitive | `fbefc5fb92c6d3cbe8d284a2cd971b593bb07d2cd6da8557b81a862250b4acec` |
| fixnum | 1.1.1 | transitive | `b6dc7065e46c974bc7c5f143080a6764ec7a4be6da1285ececdc37be96de53be` |
| flutter | 0.0.0 | direct main | `Flutter SDK 3.47.5` |
| flutter_driver | 0.0.0 | transitive | `Flutter SDK 3.47.5` |
| flutter_lints | 6.0.0 | direct dev | `3105dc8492f6183fb076ccf1f351ac3d60564bff92e20bfc4af9cc1651f4e7e1` |
| flutter_test | 0.0.0 | direct dev | `Flutter SDK 3.47.5` |
| flutter_web_plugins | 0.0.0 | transitive | `Flutter SDK 3.47.5` |
| fuchsia_remote_debug_protocol | 0.0.0 | transitive | `Flutter SDK 3.47.5` |
| glob | 2.2.0 | transitive | `218aeb56050c714f62a3182775320dfa04602b55074873e24e31bbd39bda96fb` |
| hooks | 2.2.0 | transitive | `eaac480a35ec0814146c2c48d96aaa829e0e44a7662c88ae84c9edf4bc35651f` |
| http | 1.6.0 | transitive | `87721a4a50b19c7f1d49001e51409bddc46303966ce89a65af4f4e6004896412` |
| http_parser | 4.1.2 | transitive | `178d74305e7866013777bab2c3d8726205dc5a4dd935297175b19a23a2e66571` |
| integration_test | 0.0.0 | direct dev | `Flutter SDK 3.47.5` |
| jni | 1.0.3 | transitive | `f038e58b4dc2c9037f50e233175086337e0b305e356d28211bf55f21c504cbd3` |
| jni_flutter | 1.0.3 | transitive | `b2310cdd4c18c65c081ab141a41efa94aa26c65431803703ece51996f174f351` |
| jni_util | 1.0.0 | transitive | `1ba86da04a5f2bf18fde2edb235587e70c5b0fc5bd4ba955f46b00942c3fc35f` |
| leak_tracker | 11.0.2 | transitive | `33e2e26bdd85a0112ec15400c8cbffea70d0f9c3407491f672a2fad47915e2de` |
| leak_tracker_flutter_testing | 3.0.10 | transitive | `1dbc140bb5a23c75ea9c4811222756104fbcd1a27173f0c34ca01e16bea473c1` |
| leak_tracker_testing | 3.0.2 | transitive | `8d5a2d49f4a66b49744b23b018848400d23e54caf9463f4eb20df3eb8acb2eb1` |
| lints | 6.1.0 | transitive | `12f842a479589fea194fe5c5a3095abc7be0c1f2ddfa9a0e76aed1dbd26a87df` |
| logging | 1.3.0 | transitive | `c8245ada5f1717ed44271ed1c26b8ce85ca3228fd2ffdb75468ab01979309d61` |
| matcher | 0.12.20 | transitive | `31bd099b47c10cd1aeb55146a2d46ce0277630ecef3f7dae54ad7873f36696cd` |
| material_color_utilities | 0.13.0 | transitive | `9c337007e82b1889149c82ed242ed1cb24a66044e30979c44912381e9be4c48b` |
| meta | 1.19.0 | transitive | `307249ce4ff29d58a18e97f6345f539382eb9c9c29ecda628900f31de0443dd9` |
| native_toolchain_c | 0.19.3 | transitive | `a1c26117c48cebe5677b0cf0e33a980a79a7c5577effc86f52e5a0d309cdcb60` |
| objective_c | 9.5.0 | transitive | `b7fb95a6d9a4f009edd63dc5ac69f07420b23a16161c6dd8660290b59c602e8e` |
| package_config | 3.0.0 | transitive | `ffcf4cf3d6c0b74ac43708d9f56625506e8a68aa935abe9d267a7330f320eb5d` |
| path | 1.9.1 | transitive | `75cca69d1490965be98c73ceaea117e8a04dd21217b37b292c9ddbec0d955bc5` |
| path_provider | 2.1.6 | direct main | `a7f4874f987173da295a61c181b8ee71dab59b332a486b391babf26a1b884825` |
| path_provider_android | 2.3.1 | transitive | `69cbd515a62b94d32a7944f086b2f82b4ac40a1d45bebfc00813a430ab2dabcd` |
| path_provider_foundation | 2.6.0 | transitive | `2a376b7d6392d80cd3705782d2caa734ca4727776db0b6ec36ef3f1855197699` |
| path_provider_linux | 2.2.2 | transitive | `58c2005f147315b11e9b4a7bc889cd5203e250cba8e3f012dae259b4972b5c16` |
| path_provider_platform_interface | 2.1.3 | transitive | `484838772624c3a4b94f1e44a3e19897fee738f2d5c4ce448443b0417f7c9dda` |
| path_provider_windows | 2.3.0 | transitive | `bd6f00dbd873bfb70d0761682da2b3a2c2fccc2b9e84c495821639601d81afe7` |
| platform | 3.2.0 | transitive | `a36d119c13416516a7b5913fbe8af8531e11633d784c550b2125f76c758524ec` |
| plugin_platform_interface | 2.1.8 | transitive | `4820fbfdb9478b1ebae27888254d445073732dae3d6ea81f0b7e06d5dedc3f02` |
| process | 5.0.6 | transitive | `4242ba3508d37e01808bdf71ad1d5bb93a8d671bf2e7450e6b1b353fb0808891` |
| pub_semver | 2.2.1 | transitive | `261236774e8b1d69cfc6b9eabbc96c40f25e7a2d6b171f3385d4f65d5734fb24` |
| record_use | 1.1.1 | transitive | `1cb8564af8d43b464294411db9217f5ec04891c6f22ee2c32d73ae05e88a6bd2` |
| sky_engine | 0.0.0 | transitive | `Flutter SDK 3.47.5` |
| source_span | 1.10.2 | transitive | `56a02f1f4cd1a2d96303c0144c93bd6d909eea6bee6bf5a0e0b685edbd4c47ab` |
| sqlite3 | 3.7.0 | direct main | `cc62d72dbf16bb1f6ae8954b238016de1473e53df060ed0c332eed0a41dd1848` |
| stack_trace | 1.12.2 | transitive | `277654b3034d17ac6f9f1cb5595db011b1d5d41e8806866db28e0abaa101c490` |
| stream_channel | 2.1.4 | transitive | `969e04c80b8bcdf826f8f16579c7b14d780458bd97f56d107d3950fdbeef059d` |
| string_scanner | 1.4.1 | transitive | `921cd31725b72fe181906c6a94d987c78e3b98c2e205b397ea399d4054872b43` |
| sync_http | 0.3.1 | transitive | `7f0cd72eca000d2e026bcd6f990b81d0ca06022ef4e32fb257b30d3d1014a961` |
| term_glyph | 1.2.2 | transitive | `7f554798625ea768a7518313e58f83891c7f5024f88e46e7182a4558850a4b8e` |
| test_api | 0.7.12 | transitive | `2a122cbe059f8b610d3a5415f42e255b6c17b1f21eee1d960f31080237fb4f11` |
| timezone | 0.11.1 | direct main | `981d1020d6ef8fe1e7b3de5054e5b25579ae7c403d7734adc508ffc47668e9cb` |
| typed_data | 1.4.0 | transitive | `f9049c039ebfeb4cf7a7104a675823cd72dba8297f264b6637062516699fa006` |
| url_launcher | 6.3.2 | direct main | `f6a7e5c4835bb4e3026a04793a4199ca2d14c739ec378fdfe23fc8075d0439f8` |
| url_launcher_android | 6.3.33 | transitive | `611e87fb320b70d1dd721dc46af89c98aceccea9b31fde49e084591414e0c610` |
| url_launcher_ios | 6.4.2 | transitive | `8faa1aab294f1ab4040b43660c887b0418d5fa4f0cffef76a484e6aa1092eb4a` |
| url_launcher_linux | 3.2.3 | transitive | `10f86fef4c2c43563fa6c211ff9cf757adf4d3ab762c56bd430664a947d70cd0` |
| url_launcher_macos | 3.2.6 | transitive | `5e835a3b869c2d70325349c81c5a45c28e20791265b67b2669da6b08c5cd5201` |
| url_launcher_platform_interface | 2.3.2 | transitive | `552f8a1e663569be95a8190206a38187b531910283c3e982193e4f2733f01029` |
| url_launcher_web | 2.4.3 | transitive | `85c81589622fbc87c1c683aaea164d3604a7777495a79d91e39ffcdec39ddb34` |
| url_launcher_windows | 3.1.6 | transitive | `6c5ad3f22cd4c38e089b81963b3cd7bb83b111b2df5dce008bb066162f42e429` |
| uuid | 4.6.0 | direct main | `9b129329f58692f6e6578329498a8fe9fbe98f090beb764ffbb8ee2eadd01dcd` |
| vector_math | 2.4.0 | transitive | `1d774bbdf6b72a0b12122fc1560c9c2d2a67db5a4a4cc2bd8a5c990ab20e3188` |
| vm_service | 15.3.0 | transitive | `5f37239c4851efcef929cea7824e76df7f2f0970aef85d66bbc430afa40e72f0` |
| web | 1.1.1 | transitive | `868d88a33d8a87b18ffc05f9f030ba328ffefba92d6c127917a2ba740f9cfe4a` |
| webdriver | 3.2.0 | transitive | `28b82ec894fed45dd71c23ba62d1af973ed97dd59a4f5790a4d38b0b13e5657e` |
| xdg_directories | 1.1.0 | transitive | `7a3f37b05d989967cdddcbb571f1ea834867ae2faa29725fd085180e0883aa15` |
| yaml | 3.1.4 | transitive | `f67cdd8e07d3c6329146aaef1ba043542b3134c12489f553ca9a7435d1068aea` |

Inventory anchor hashes: `pubspec.lock` SHA-256 `15c472203a380705001c26a759d0e47c255ad0ebfb86d8cec80f4560a28852c8`; setup-Flutter action SHA-256 `d0b94d3f1eea9e4cc260eeabe008df39ef2aab9290fd29fb895481dca5896c22`.
