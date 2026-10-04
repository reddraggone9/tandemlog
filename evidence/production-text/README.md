# Unreleased production text checkpoint

All data/screenshots here are synthetic. Production app source is on
`experiment/text-activation-policy`; this is engineering evidence, not a release
acceptance receipt. Actual integrated Linux library SHA-256:
`892d5048fc30c615fd672a6d6e9a8000ca8fdf6723271e54317356debf9bc6b3`.

Verified locally with Flutter 3.47.5/Dart 3.13.4 and locked Yrs 0.28.0/Rust 1.99.0:

- 447 unit/widget tests with `TANDEMLOG_TEXT_LIBRARY` pointing to that SO,
  clean analysis and formatting, including the two local recurring-completion
  guard cases. Their related actual-library suite separately passes 41. The
  earlier 445-case aggregate log is retained as prior evidence.
- The actual GTK app flow in `integration_test/text_workflow_test.dart` passes:
  offline native capture/edit before legacy setup, peer changes during a private
  draft, merged Save, selective session Undo retaining peer work, legacy setup,
  narrow editor and restart persistence. Xvfb/Openbox, 1200px Light/100% and
  390px Dark/200%; five screenshots visually inspected. The previously clipped
  setup instruction now wraps below notes. Composition is injected, not an OS
  keyboard test. Debug timings in this log are not release cold-start results.
- Four offline exact-license tests and four packaging contract tests pass.
  Notice assets are in the actual Linux bundle; Windows/Android packaging and
  native installed lifecycle are not verified by this check.
- 98 Python native cases and two Rust cases passed on the same SO. Native
  admission/resource measurements, original failures and corrected fixture
  assumptions are retained in the nested HANDOFF files. Those subprocess
  measurements are not UI frame, Android-memory or end-to-end startup evidence.
- Current native Android arm64-v8a, x86_64 and armeabi-v7a release libraries
  cross-build offline with locked Cargo, Rust 1.99.0 and NDK 28.2/API 24;
  required exports and 16 KiB ELF alignment pass. Exact digests are in
  `android-engine-build.json`. Official standard-library targets were installed
  after an empty/stale target directory caused an explicit compiler failure;
  no alternate repository or network-policy workaround was used. This is not
  an APK packaging, installation or native Android runtime check.

The first native UI finder failure assumed Save leaves the editor open; the
assertion was corrected to the existing close-on-Save behavior. The first
combined test command had one incorrect filename; its log is retained alongside
the corrected passing command. The original historical benchmark remains
unchanged; later measurements live in this directory.

Pending: successor text agreement for concurrent recurring completion, complete
existing native workflow adaptation/aggregate, mandatory real-engine hosted CI,
Android APK packaging, installed native Windows and
exact signed Android acceptance, release performance and independent final
notes/media review. The current local recurrence guard rejects before receipt or
append and changes no historical replay. No new production release or main push
has occurred. Frozen stable v3 fixtures and canonical history are unchanged.
