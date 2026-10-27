# Nonsecret configuration and coordination supplement

Snapshot2026-10-24; locations/identifiers only. No credential, certificate-pin or signing values are included.

## CI, runners and build inputs

- General dispatch and branch concurrency: `.github/workflows/ci.yml`. The `ci-${github.ref}` concurrency group cancels an older in-progress run when a new run for the same branch starts. Check/adopt the existing run before dispatching another.
- Required jobs, runner selection, timeouts, artifact retention and fixed performance resource bounds: `.github/workflows/validate.yml`, especially `jobs.{linux,windows,android,performance}`. The bounded performance launcher is `tool/performance/run_ci.sh`; policy/limits/coverage are under `tool/performance/` and `design/performance-gate.md`.
- Reviewed SDK/toolchain installation: `.github/actions/setup-flutter/action.yml`, `.github/actions/setup-text-engine/action.yml`, `tool/bootstrap_text_engine.py`, `tool/build_text_engine.py`. Native payload/ABI checks: `tool/native_build_gates.py`. Locked dependency and provenance records: `pubspec.lock`, `native/text_engine/Cargo.lock`, `design/dependencies.md`.
- Android repository policy: `tool/gradle_repository_policy.py`; Gradle application configuration: `android/app/build.gradle.kts`. Installation/package checks: `packaging/linux/`, `packaging/windows/`.
- Diagnostic-only close capture: `.github/workflows/rc4-linux-close-diagnostic.yml`, `tool/collect_linux_core_stacks.py`. Actual repair-branch CI also enables post-fault capture in `validate.yml`'s Linux startup step. Raw memory cores are excluded from artifacts.
- Separate Windows QA build/controller/package inputs: `.github/workflows/windows-widget-qa.yml`, `integration_test/windows_release_widget_viability.dart`, `tool/windows_widget_qa/`. This build does not authorize foreground execution or establish full-action acceptance.

## Signing and publication locations (held)

- Candidate/signing orchestration: `.github/workflows/android-candidate.yml`; key handling/build cleanup: `tool/build_android_release.sh`; nonsecret verification: `tool/android_release.py`.
- Repository Actions secret identifiers referenced by the candidate workflow: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Their values belong in GitHub repository Actions secrets, never a handoff, repository file, command argument, log or artifact.
- Temporary signing material location: `$RUNNER_TEMP/tandemlog-signing/release.keystore`; the build script/workflow owns cleanup. The owner public certificate-pin **location** is `android/signing-certificate.sha256`; no pin value is reproduced here.
- Publication entrypoints: `.github/workflows/prerelease.yml`, `.github/workflows/stable.yml`; source/artifact/notes gates: `tool/candidate_source.py`, `tool/publish_gate.py`, `tool/release_assets.py`, `design/releases.md`. These workflows are outside the authorized repair; do not dispatch or alter signing inputs.

## Essential live facts outside static repository policy

- Lee/Vex postponed cutover. Cloud remains the sole product writer. The stop-write cutoff is **2026-10-26 08:00 America/Chicago /13:00 UTC**, or earlier on actual quota exhaustion/access loss. Finish a safe checkpoint, preserve failures, push eligible tested work, stop owned processes and report; do not continue writing past that cutoff. Ownership still requires an explicit coordinated handoff.
- Current quota is unknown. Supported-tool discovery exposes no quota status; the earlier banked reset is not a current percentage. Major gated feature/publication work remains held under the existing approval rules.
- Fresh exact-source CI **40139838647** was dispatched once on **732ddac905bc67410731b7ef3f1c42eaf77701b8**, whose executable inputs match8005430; calibration=false. Its outcome is pending at this supplement's creation.
- Native Session Undo/Discard failure was reproduced locally before edits. A new deterministic host regression demonstrates that clearing `closingEditor` without rebuilding can leave the rendered Undo button disabled after Cancel. The repair and native recheck are in progress; no assertion, guard, budget or canonical meaning has been relaxed.
- Parent owns updates to the private Farnsworth `HANDOFF.md` and the separate Monday/Thursday reviews and email-watch transfer. This engineering task has not modified or duplicated those schedules/watches. No new persistent access/service has been established.
- Direct CLI download of one completed job's temporary blob previously returned403 and was not retried. The successful GitHub-app response obtained earlier was saved at `/workspace/scratch/rc4-proof-native-ci-40134281681/job.log`; use retained evidence rather than routing around a denial. No push or signing authorization is implied by a diagnostic read.
