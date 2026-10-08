# Production native CI/build gates

Owned repository edits only:
- .github/actions/setup-text-engine/action.yml (new)
- .github/workflows/validate.yml
- .github/workflows/android-candidate.yml
- tool/bootstrap_text_engine.py (new CI-only bootstrap)
- tool/native_build_gates.py (new offline ABI/package checker)
- tool/test_native_build_gates.py, tool/test_native_alignment_gate.py (new)
- tool/build_text_engine.py (existing ELF verifier adds64-bit RELRO check)
- android/app/build.gradle.kts (parent-authorized single exact NDK line)
No media worktree, app/domain/Rust source, signing/protection/permissions/cost settings or dependency locks changed. Other concurrent root integration-test edits are not owned here. No commit/push/dispatch/publication.

## Test-first evidence

New4 native workflow/payload/bootstrap assertions frozen before implementation; hash recorded frozen-test-sha256.txt, initial red.txt missing helper (ImportError), green.txt4PASS. One supplementary16KiB RELRO-negative contract separately frozen before verifier change; alignment-frozen-sha256.txt and alignment-red.txt (expected assertion failure on previously admitted badRELRO). All current32 tool testsPASS (tool-all.txt), original packaging tests unchanged. Both new test hashes verify unchanged. Pythoncompile and gitdiffcheck pass. All modified YAML parsed with already-installed local safe YAML parser; no parser dependency added to CI/app.

## Bootstrap/input ownership

One local composite, no new third-party action. Fixed official rustup1.29.1 executable URLs under https://static.rust-lang.org/rustup/archive/1.29.1/ and committed SHA256:
Linux x86_64 dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71 (matches existing reviewed local bootstrap);
Windows x86_64 6f4bef66261261fcb43131be8720bab817d403a09edec7455c371974b90bdb7e (official versioned archive digest retrieved normally).
Downloaded manager verified before execution; no pipe-to-shell, no floating installer URL. Dedicated runner temporary Cargo/Rustup homes, no PATH modification by installer, auto-self-update disabled, exact official1.99.0 minimal toolchain. Explicit LinuxGNU/WindowsMSVC std target or all three Android targets (aarch64-linux-android,armv7-linux-androideabi,x86_64-linux-android). cargo fetch --locked occurs in bootstrap before app builds. App helper still requires preinstalled inputs and builds --locked --offline; no notices downloaded by app build. Windows selects preinstalled Python3.11 for tomllib, without new action/package.

Android bootstrap installs exact already-reviewed NDK28.2.13676358 via official sdkmanager before app build. Gradle exact same NDK pin; pinned Flutter source already has minSdk24 and defaultNDK28.2, AGP9.1/Gradle9.3.1 retained. Existing API24 linkers and16KiB LOAD flags unchanged. Official Android16KiB guidance requires64-bit RELRO end alignment and APK zipalignment; added checker covers64-bit RELRO, preservesARMv7 LOAD contract without pretending32-bit16KiB device coverage. APK CLI invokes existing SDK36 zipalign -c -P16 4, inspects every three-ABI Rust ELF/export payload and exact full licenseasset.

## Required native coverage and packaging

Reusable Linux/Windows jobs build production native library with actual platform helper, then execute a real exported ABI create/read/close smoke before setting TANDEMLOG_TEXT_LIBRARY in GITHUB_ENV. Missing/wrong ABI fails, cannot produce native Flutter-test skips from absent env. All subsequent Flutter unit/storage/session tests see required exact library. Native app debug/release hooks retain one canonical engine, library exports/architectures verified by helper. Release desktop bundle payload checker requires actual SO/DLL, executes its ABI, and verifies byte-identical Flutter noticesasset. Existing Linux Flatpak and Windows installed lifecycle gates continue after bundle validation. No removal of previous tests/gates.

Reusable Androiddebug and signedAndroidcandidate both use composite/bootstrap then actual appbuild and packaged APK payload/notice gate. Candidate runs reusablechecks first. Stable/prerelease workflows have no appbuild path: they still consume exact candidate artifacts without rebuilding, so no bootstrap added to publication. Native checks must run in the candidate producing those artifacts, not mutate accepted artifacts later.

Terminal verification: required productionLinux ABI loadPASS against current prepared SO; all3 existing Android library ELF metadata (including64-bit RELRO)PASS;4 locked-notice testsPASS. No local full appbuild or hostedWindows/native DLL/lifecycle run claimed in this delegated gate. Root owns current Android APK local build/runtime/native suites. Primary official16KiB reference: https://developer.android.com/guide/practices/page-sizes . SDK/library static checks are not Android16KiB runtime acceptance. Shared target never rebuilt by this agent, no target race.

Remaining gates: root review/commit and authorized execution of production branch CI, native hostedWindows DLL/unit/build/install/lifecycle success; local/current Android APK full three-ABI+notices+zipalign check, actual Android/device and release workflow acceptance; Linux actual packaged app/storage/UI acceptance; preserve canonical outboxes/drafts through native failures. No signed45/main dispatch authorized/performed by this agent. Cross-build never called runtime coverage.

## Parent-expanded AGP9.1 generated-directory fix

Root actual Android APK build stopped before compilation because AGP9.1 explicitly rejects Directory Providers in legacy sourceSets.jniLibs. Source Gradle line now binds concrete textEngineJni.get().asFile; preBuild continues explicitly depending on buildTextEngine, whose outputs.dir and --output-dir point to the same generated build directory. No SourceSet provider-disable workaround, generated JNI files in repository, new plugin/dependency or task framework.

New structural fixture frozen before this fix: tool/test_android_native_hook.py, android-hook-frozen-sha256.txt, android-hook-red.txt. Test checks concreteFile binding, preBuild producer ordering, matching outputdirectory and absence of android.sourceset.disallowProvider=false escape. Fixture nowPASS unchanged. Installed Gradle9.3.1/AGP9.1 actual offline :app:mergeDebugNativeLibs --dry-run BUILD SUCCESSFUL5sec. Required buildTextEngine appears before preBuild and mergeDebugNativeLibs in graph (lines122/124/169); log android-hook-dryrun-fixed.txt. This proves configuration/task ordering only, not successful APK/native compilation or runtime. Parent notified ready to retry actual APK; no sharednative build running.

## Parent-requested maintainability cleanup before commit

Expanded semicolon-compressed statements into conventional readable Python in the two new helper scripts and three new test files; removed the actual unreachable `if False` expression in test_native_build_gates.py. No API/expectation/control-flow changes. Original pre-format copies and hashes preserved under pre-format/; initial frozen hashes and red evidence remain preserved. Formatted test source bytes have changed deliberately, so current formatted files are NOT claimed to match original freeze hashes. format-delta.json records old/new SHA256 and normalized-AST equivalence (normalizes import ordering/grouping and the explicitly removed dead branch; all executable logic/constants/test assertions match).

Post-format32 tool testsPASS (format-tool-all.txt),4 notice testsPASS (format-notices.txt); Python compilation and owned-file gitdiffcheck clean. Parent reports actual local AndroidAPK and Linux payload SUCCESS in /tmp/production-text-android-payload-gate.txt and its Linux counterpart, including3ABI/export/ELF/zipalign/notices; this updates prior build-pending status but is parent evidence, not a new runtime claim by this agent. HostedWindows execution remains pending. No commits or broad additional tests/builds executed.

Final owned file list: .github/actions/setup-text-engine/action.yml; .github/workflows/validate.yml; .github/workflows/android-candidate.yml; android/app/build.gradle.kts; tool/bootstrap_text_engine.py; tool/native_build_gates.py; tool/build_text_engine.py; tool/test_native_build_gates.py; tool/test_native_alignment_gate.py; tool/test_android_native_hook.py.
