# Builds and releases

CI uses standard GitHub-hosted Ubuntu 24.04 and Windows 2022 runners, pinned official actions and Flutter 3.47.5 at a verified source revision. No larger/paid runners or billing changes. Intermediate artifacts expire after five days.

Every executable-change main push and every pull request runs formatting, analysis, the complete domain/storage integrity/convergence/recovery suite and native Linux integration and release startup smoke checks (fresh/warm SQLite), plus Linux release, native Windows release and Android debug builds. Windows also runs domain/storage tests. Fast Linux checks start immediately; platform builds run independently. No integrity tests are removed for previews.

To prepare an authorized candidate, dispatch **Build signed candidate** on main. It checks the public signing pin and monotonically increasing Android build number, runs the full Linux/Windows/debug-Android matrix, then produces a universal non-debuggable APK using the owner-provided signing identity. No publishing occurs. Its `android-release` artifact includes APK, checksum, public signature report and source/version/certificate metadata. Download and install this exact APK for native acceptance before publishing.

Then dispatch **Experimental prerelease** with the candidate tag, successful signed-candidate run ID, and the exact APK SHA-256 from completed native installation/launch and required workflow QA. That hash is an explicit operator attestation, not an automated device test. The publication job verifies successful main/workflow provenance, source, version, public signer pin, exact APK hash, complete asset set, checksums, absent tag and size limits. It consumes the already-tested artifacts without rebuilding them and uses `--prerelease --latest=false`. Only publication receives contents-write permission. Android signing secrets never enter that job. Candidate artifacts expire after five days; if expired, rebuild and revalidate the new exact APK. CI artifacts and releases are public in this public repository.

Tags must match the candidate's pubspec version. Build 5 is the first owner-signing candidate, beyond the previously handed-out debug builds 1–4. Version checks cover that floor, published tags and prior successful signed-candidate runs from different commits; same-source retries are allowed before publication. Candidate runs are serialized to avoid version-check races. Increment the build number before handing out a changed candidate. Ordinary local/push/PR debug QA remains possible without signing secrets and is never selected as the public Android release asset. Windows bundles remain unsigned. Installation/runtime limits are in [candidate notes](prerelease-notes.md).

Stable releases are not automated yet. Required gates: full integrity/recovery/convergence suite; all target builds; native install/launch and workflow acceptance on Windows and Android; persisted SAF grant and remote replacement/provider tests; measured target startup; Lee's acceptance. Stable signing/distribution and any credentials need action-time authorization. Do not claim native runtime coverage from a cross-build or browser preview.

Before publishing, review architecture boundaries, duplication, stale code/data, docs drift, unresolved debt and migration/recovery behavior; record concrete fixes and remaining risks in status. Test public downloads and verify release metadata/assets after publication.

Linux x64 tarball is a first-class preview artifact with checksum. Native Linux is the primary shared desktop visual QA target; Windows-specific packaging/path/dialog/startup checks remain necessary. See [runtime QA](runtime-qa.md) for the split.

## Documentation-only pushes

Push CI skips commits changing only Markdown or recorded evidence, avoiding three full platform builds for QA notes. Any code, dependency, tooling or workflow change still runs the full matrix. Pull requests and manual CI retain full checks; the signed candidate build always invokes the full reusable validation workflow regardless of paths, and publication requires that successful run’s exact artifacts. This filter does not alter branch protections or release gates.


## Android signing continuity and owner handoff

Lee authorized a dedicated durable signing key generated/stored under `nibbler` on Farnsworth. The owner provisions GitHub secrets; the cloud agent neither generates nor transmits that private material. The public SHA-256 certificate fingerprint is pinned in `android/signing-certificate.sha256`; until supplied, candidate preflight intentionally fails. Android release builds fail without all signing inputs; there is no generated-key or debug-key fallback.

At [repository Actions secrets](https://github.com/reddraggone9/tandemlog/settings/secrets/actions), choose **New repository secret** for each:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Standard Base64 encoding of the complete binary keystore, preferably one line; not the keystore path or a PEM certificate. |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password. |
| `ANDROID_KEY_ALIAS` | Alias of the signing key inside that keystore. |
| `ANDROID_KEY_PASSWORD` | Password for that key; may equal the store password. |

Owner-only CLI alternative on the trusted machine: `base64 -w 0 /path/to/keystore | gh secret set ANDROID_KEYSTORE_BASE64 --repo reddraggone9/tandemlog`; use interactive `gh secret set NAME --repo reddraggone9/tandemlog` prompts for the other values. Do not place passwords in shell command arguments/history or send private material through chat/Library. Keep an owner-controlled encrypted backup. Send only the public certificate SHA-256 digest (64 hex digits, without colons) for the repository pin. [GitHub's secret setup guide](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) documents the UI and binary encoding convention.

Only the main-gated manually dispatched signing job references these secrets, scoped to its build step. It decodes the keystore under runner temporary storage with restrictive permissions, disables persistent Gradle daemons, verifies the APK signer/package/version/non-debuggable flag/phone and emulator ABIs, and removes temporary material on success/failure/cancellation. It does not upload/cache the key or write key.properties. The workflow grants read-only repository access; no signing secrets are passed to PR/debug validation. Repository secrets themselves are not platform-restricted to this workflow: GitHub environment protection would be a separate owner-approved hardening decision, not something configured here.

Public rc1 used a fresh hosted debug identity that was not retained. Local debug APKs use another certificate, and the durable owner key introduces a one-time reinstall transition. Back up and verify the complete external canonical folder (manifest plus all per-device JSONL logs), uninstall/install, grant SAF access to that same folder and select the existing user. Local settings, SQLite cache, writer identity and grants are recreated; unsaved drafts are not durable. Never delete the shared history to resolve a signature mismatch. Once transitioned, future APKs signed with the pinned key and increasing build numbers support the normal update path, subject to native install/upgrade verification. [Android signing guide](https://developer.android.com/studio/publish/app-signing).
