# Builds and releases

CI uses standard GitHub-hosted Ubuntu 24.04 and Windows 2022 runners, pinned official actions and Flutter 3.47.5 at a verified source revision. No larger/paid runners or billing changes. Intermediate artifacts expire after five days.

Every executable-change main push and every pull request runs formatting, analysis, the complete domain/storage integrity/convergence/recovery suite and native Linux integration and release startup smoke checks (fresh/warm SQLite), plus Linux release, native Windows release and Android debug builds. Windows also runs domain/storage tests. Fast Linux checks start immediately; platform builds run independently. No integrity tests are removed for previews.

To prepare an authorized candidate, dispatch **Build signed candidate** on main. It checks the public signing pin and monotonically increasing Android build number, runs the full Linux/Windows/debug-Android matrix, then produces a universal non-debuggable APK using the owner-provided signing identity. No publishing occurs. Its `android-release` artifact includes APK, checksum, public signature report and source/version/certificate metadata. Download and install this exact APK for native acceptance before publishing.

Then dispatch **Experimental prerelease** with the candidate tag, successful signed-candidate run ID, and the exact APK SHA-256 from completed native installation/launch and required workflow QA. That hash is an explicit operator attestation, not an automated device test. The publication job verifies successful main/workflow provenance, source, version, public signer pin, exact APK hash, complete asset set, checksums, absent tag and size limits. It consumes the already-tested artifacts without rebuilding them and uses `--prerelease --latest=false`. Only publication receives contents-write permission. Android signing secrets never enter that job. Candidate artifacts expire after five days; if expired, rebuild and revalidate the new exact APK. CI artifacts and releases are public in this public repository.

Tags must match the candidate's pubspec version. Build 5 is the first owner-signing candidate, beyond the previously handed-out debug builds 1–4. Version checks cover that floor, published tags and prior successful signed-candidate runs from different commits; same-source retries are allowed before publication. Candidate runs are serialized to avoid version-check races. Increment the build number before handing out a changed candidate. Ordinary local/push/PR debug QA remains possible without signing secrets and is never selected as the public Android release asset. Installation/runtime guidance is in [packaging](../packaging/README.md).

Stable releases are not automated yet. Required gates: full integrity/recovery/convergence suite; all target builds; native install/launch and workflow acceptance on Windows and Android; persisted SAF grant and remote replacement/provider tests; measured target startup; Lee's acceptance. Stable signing/distribution and any credentials need action-time authorization. Do not claim native runtime coverage from a cross-build or browser preview.

Before publishing, review architecture boundaries, duplication, stale code/data, docs drift, unresolved debt and migration/recovery behavior; record concrete fixes and remaining risks in status. Test public downloads and verify release metadata/assets after publication.

RC4 replaces loose desktop archives with a Linux x64 Flatpak bundle and per-user Windows setup EXE, each with checksum and required installed lifecycle report. The exact candidate must install, launch, replace, uninstall without data loss, and reinstall before publication. Native Linux remains the primary shared desktop visual QA target; Windows-specific packaging/path/dialog/startup checks remain necessary. [Packaging commands and prerequisites](../packaging/README.md) explain runtime/folder access, including the separately installed C++ runtime. See [runtime QA](runtime-qa.md) for the split.

## Public downloads and internal evidence

From RC7, publish only versioned installers: `tandemlog-<version>-android.apk`, `tandemlog-<version>-windows-x64-setup.exe`, and `tandemlog-<version>-linux-x64.flatpak`. Derive `<version>` from the validated candidate source; copy exact accepted bytes after all existing gates rather than rebuild. Signer behavior is unchanged. [Installation guidance](../packaging/README.md) holds prerequisites; signing status is explained once in installation-warning troubleshooting. Release notes describe changes and release-specific compatibility, not a repeated verification transcript. GitHub supplies automatic source ZIP/tarball links; upload no extra source archive. Historical release assets remain unchanged.

| Existing candidate file | Purpose / current consumer | Public from RC7 |
| --- | --- | --- |
| APK / setup EXE / Flatpak | User installation; candidate native QA | Yes, versioned names |
| Three platform SHA256SUMS files | Publication verifies accepted bytes | No, retained inside candidate artifacts |
| Android signature report and release metadata | Signer, package, version, source and exact accepted APK gates | No, retained inside candidate artifacts |
| Linux startup report | Measured release startup evidence | No, retained inside candidate artifacts |
| Linux and Windows install-smoke reports | Required installed lifecycle gates | No, retained inside candidate artifacts |

No app updater or current known integration consumes the diagnostic JSON/checksum assets as public release metadata. Obtainium selects the APK via GitHub's assets/prerelease API; no Tandemlog-specific public JSON manifest is configured. The audit covers repository consumers and known setup, not unknown third-party tools. Internal candidate filenames remain stable so checksum/install gates and native handoffs keep using the original accepted artifacts; only the final public copies gain the validated version. Preserve complete gate results in CI and repository evidence. Do not remove checks or historical downloads to reduce the public list.

## Documentation-only pushes

Push CI skips commits changing only Markdown or recorded evidence, avoiding three full platform builds for QA notes. Any code, dependency, tooling or workflow change still runs the full matrix. Pull requests and manual CI retain full checks; the signed candidate build always invokes the full reusable validation workflow regardless of paths, and publication requires that successful run’s exact artifacts. This filter does not alter branch protections or release gates.


## Android signing continuity and owner handoff

Lee authorized a dedicated durable signing key generated/stored under `nibbler` on Farnsworth. The owner provisions GitHub secrets; the cloud agent neither generates nor transmits that private material. The public SHA-256 certificate fingerprint is pinned in `android/signing-certificate.sha256`; the supplied fingerprint is now pinned, and the owner-provisioned inputs successfully signed candidate run `36762053783`. Android release builds fail without all signing inputs; there is no generated-key or debug-key fallback.

At [repository Actions secrets](https://github.com/reddraggone9/tandemlog/settings/secrets/actions), choose **New repository secret** for each:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Standard Base64 encoding of the complete binary keystore, preferably one line; not the keystore path or a PEM certificate. |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password. |
| `ANDROID_KEY_ALIAS` | Alias of the signing key inside that keystore. |
| `ANDROID_KEY_PASSWORD` | Password for that key; may equal the store password. |

Owner-only CLI alternative on the trusted machine: `base64 -w 0 /path/to/keystore | gh secret set ANDROID_KEYSTORE_BASE64 --repo reddraggone9/tandemlog`; use interactive `gh secret set NAME --repo reddraggone9/tandemlog` prompts for the other values. Do not place passwords in shell command arguments/history or send private material through chat/Library. Keep an owner-controlled encrypted backup. The supplied public certificate SHA-256 is pinned; the generated PKCS12 key alias is `tandemlog-release`. Only public fingerprints (64 hex digits without colons) belong in the repository. [GitHub's secret setup guide](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) documents the UI and binary encoding convention.

Only the main-gated manually dispatched signing job references these secrets, scoped to its build step. It decodes the keystore under runner temporary storage with restrictive permissions, disables persistent Gradle daemons, verifies the APK signer/package/version/non-debuggable flag/phone and emulator ABIs, and removes temporary material on success/failure/cancellation. It does not upload/cache the key or write key.properties. The workflow grants read-only repository access; no signing secrets are passed to PR/debug validation. Repository secrets themselves are not platform-restricted to this workflow: GitHub environment protection would be a separate owner-approved hardening decision, not something configured here.

Public rc1 used a fresh hosted debug identity that was not retained. Local debug APKs use another certificate, and the durable owner key introduces a one-time reinstall transition. Back up and verify the complete external canonical folder (manifest plus all per-device JSONL logs), uninstall/install, grant SAF access to that same folder and select the existing user. Local settings, SQLite cache, writer identity and grants are recreated; unsaved drafts are not durable. Never delete the shared history to resolve a signature mismatch. Once transitioned, future APKs signed with the pinned key and increasing build numbers support the normal update path, subject to native install/upgrade verification. [Android signing guide](https://developer.android.com/studio/publish/app-signing).

## Markdown authority and final cutover

Throughout prereleases, Lee continues editing the Markdown todo list as the authoritative record. Every app rehearsal uses a clearly identified COPY. The default canonical folder path and Syncthing share are permanent; only their test contents are disposable. A passing snapshot is not the final import; do not treat test-app changes as authoritative or silently merge them back. Private source text, hashes, backups and diffs stay outside the public repository.

Immediately before official 0.1.0, coordinate a separate cutover with Lee:

1. Obtain explicit agreement to pause Markdown edits and relevant app/sync writes for the chosen window, and confirm the existing permanent destination and every participating device. Keep its path and share configuration.
2. Snapshot and back up the latest Markdown source AND the existing test destination before any separately authorized cleanup. Verify the copies; retain recovery paths. Disposable does not authorize deletion by itself.
3. Import a fresh copy of that latest source into a new staging destination. Record the private snapshot hash, and verify the authoritative source still has the same hash before and after import. If it changed, stop and repeat from a newly agreed snapshot; never mix versions.
4. Repeat independent field/order/recurrence comparison, canonical serializer reparse, production-store reopen and representative native app/sync checks. Review limitations and any differences with Lee.
5. Obtain final destination/cutover acceptance, then, with all participating apps closed and sync coordinated, perform the explicitly authorized replacement/reinitialization of test canonical CONTENTS at the same permanent path. Preserve the Syncthing folder/share configuration. Prevent stale test logs on other devices from being reintroduced: reset/reconcile each replica to the validated new manifest and log set before resuming apps; keep offline devices out until they are reconciled. Reinitialize private cache/writer/selection state as needed for the new data-space identity without syncing those private files. Verify the new canonical manifest/log set on every participating device, hand over the validated data, and clarify that Tandemlog becomes authoritative. Keep backups until Lee approves their disposition. Resume device use only after the coordinated handoff.

No current prerelease, formatting diff or rehearsal authorizes live import, source deletion, test-folder deletion, stable publication or cutover. Stable release gates still apply in addition to this migration checklist.

One-off Markdown rehearsal/import/export tooling and its dedicated tests live only in the private standalone package, pinned to application APIs. They are not shipped desktop utilities or maintained release features. Keep generic app domain/storage/recurrence regression coverage in app CI. Provide refreshed native desktop and Android feature demos after the owner receives formatting guidance; migration-tool work does not replace those demos.

## Published experimental RC4

[v0.1.0-rc.4](https://github.com/reddraggone9/tandemlog/releases/tag/v0.1.0-rc.4) uses exact accepted source `ded2eebc10eb1670658995cbc0c06b4676a5c583`, signed candidate 36906871648, Android code 24. Publication 36915456832 reused all 11 original assets without rebuilding after native API30 acceptance. Public downloads/signing/tag/checksums are verified; prerelease=true/latest=false. RC3 is preserved. [Verification](../evidence/rc4-public-release-verification.json), [runtime limits](runtime-qa.md) and [packaging prerequisites](../packaging/README.md). Stable 0.1.0 and production cutover remain separate decisions.
