# Isolated native text editor lab

This is a synthetic Yrs/Flutter experiment, not Tandemlog or a data migration.
It has no application API imports, shared-folder access, persistence or signing
secrets. All text and counters reset when the process restarts. Debug builds use
a temporary Android debug signer; they are not a published app/update channel.

## Android handoff

Install the supplied APK without uninstalling or modifying Tandemlog:
`adb install -r text-merge-editor-lab.apk`.
Launch `com.reddraggone9.tandemlog.yrs_editor_lab/.MainActivity`.
Version0.0.0/code1, API24+, ARM64 and x86_64, label Text merge lab.
Enable Show taps for the recording and record device/API/ABI, keyboard/version,
APK SHA256 and certificate fingerprint. The APK verification JSON gives these
artifact facts and the native library strip transformation.

1. Confirm both replicas start as A😀B. Edit A and type a local change: committed
   replicas and Published local batches must stay unchanged until Save.
2. Use a real OS keyboard that emits a nonempty composing range (Latin suggestion
   composition or Japanese if already available). The visible IME/selection
   status comes from the real Flutter controller. Save must be disabled while
   composing. Injected test input or adb input text does not establish OS-IME
   coverage. If the installed keyboard never composes, report that gap.
3. While composing, tap Receive remote prefix. Both committed replicas gain
   REMOTE; the private field, selection and composing range must be retained.
   Commit composition with the actual keyboard. Save once: both replicas retain
   remote and local work, local published count increases by exactly one.
4. Undo then Redo: remote content remains, both replicas converge. Edit again,
   type, receive remote and Cancel: local published count must not increase,
   received content stays. Reopen Edit captures the latest committed baseline.
5. Try emoji, multiline paste, selection replacement, narrow keyboard viewport,
   rotation/resume. No exceptions, clipping that prevents control access or
   surrogate corruption. Process restart intentionally resets this lab.

Return screenshots/video with visible inputs and exact pass/fail/not-run scope.
No user data, credentials, external keyboard install or Tandemlog changes are
needed. Actual Android runtime/OS-IME remain pending until that evidence returns.

## Reproducible automated checks

Frozen matrix/tests: ../evidence/editor-matrix.json, test-first repository commit
e1afed4. Original assertions and final frozen hashes remain unchanged.
With Flutter3.47.5/Dart3.13.4 and a built isolated engine:
`flutter pub get --enforce-lockfile`; `flutter analyze`;
`SPIKE_LIBRARY=/absolute/native/library flutter test`.
Linux: `xvfb-run -a dbus-run-session -- flutter test integration_test/editor_flow_test.dart -d linux`.
The native integration test injects composition and labels that limitation.
Android packaging copies the two official-NDK-built engine libraries into
android/app/src/main/jniLibs then builds a debug APK; the manual isolated workflow
repeats these steps. The main app excludes this separate SDK package from its
analyzer; the lab has its own analyze/test/native workflow gates.
