# Builds and releases

CI uses standard GitHub-hosted Ubuntu 24.04 and Windows 2022 runners, pinned official actions and Flutter 3.47.5 at a verified source revision. No larger/paid runners or billing changes. Intermediate artifacts expire after five days.

Every executable-change main push and every pull request runs formatting, analysis, the complete domain/storage integrity/convergence/recovery suite and native Linux integration and release startup smoke checks (fresh/warm SQLite), plus Linux release, native Windows release and Android debug builds. Windows also runs domain/storage tests. Fast Linux checks start immediately; platform builds run independently. No integrity tests are removed for previews.

To publish an authorized candidate, dispatch **Experimental prerelease** on main with `v0.1.0-rc.1` (increment for later candidates). It reruns the same full matrix, checks downloaded artifact hashes and the 2 GiB asset limit, then creates the release at that exact workflow commit with `--prerelease --latest=false`. Existing tags/releases must not be overwritten. The publication job alone receives contents-write permission. CI artifacts and releases are public in this public repository.

Candidate tags must match the version in pubspec.yaml. Increase Android build number for each candidate; without a persistent signing key, package updates are not guaranteed. The test APK uses an ephemeral debug certificate; no long-lived key is generated or stored by the workflow. Windows portable bundles are unsigned. Installation and runtime limitations are in [candidate notes](prerelease-notes.md).

Stable releases are not automated yet. Required gates: full integrity/recovery/convergence suite; all target builds; native install/launch and workflow acceptance on Windows and Android; persisted SAF grant and remote replacement/provider tests; measured target startup; Lee's acceptance. Stable signing/distribution and any credentials need action-time authorization. Do not claim native runtime coverage from a cross-build or browser preview.

Before publishing, review architecture boundaries, duplication, stale code/data, docs drift, unresolved debt and migration/recovery behavior; record concrete fixes and remaining risks in status. Test public downloads and verify release metadata/assets after publication.

Linux x64 tarball is a first-class preview artifact with checksum. Native Linux is the primary shared desktop visual QA target; Windows-specific packaging/path/dialog/startup checks remain necessary. See [runtime QA](runtime-qa.md) for the split.

## Documentation-only pushes

Push CI skips commits changing only Markdown or recorded evidence, avoiding three full platform builds for QA notes. Any code, dependency, tooling or workflow change still runs the full matrix. Pull requests and manual CI retain full checks; candidate publication always invokes the full reusable validation workflow regardless of paths. This filter does not alter branch protections or release gates.


## Android signing continuity — decision pending

Current hosted jobs invoke `flutter build apk --debug` on fresh runners, without preserving a keystore; only APK, public certificate details and checksums are artifacts. Local cloud debug signing differs from public rc1, so Android rejects an in-place update. No rc1 private key is retained in the repository/release artifacts or configured cache. Do not infer update compatibility from package name/version alone.

Recommended next step, subject to explicit authorization: generate a dedicated long-lived release-signing keystore on Lee's trusted machine, retain an encrypted backup under Lee's control, and have Lee provision it and its password through GitHub's secret settings. CI should reconstruct it only in a temporary release-job directory, use it only on an authorized main release workflow (never PR jobs), verify the expected public certificate fingerprint, and remove temporary files; do not upload/cache the key or print credentials. No such key has been generated or transmitted. Source changes for that workflow follow the decision separately.

Without rc1's private key, this transition requires reinstalling. First back up and verify the complete external canonical folder, including the manifest and all per-device logs, then reinstall, grant SAF access to that same folder and select the existing user. Local settings, SQLite cache, writer identity and grants are recreated; unsaved drafts are not durable. Preserve the external history rather than starting a new empty folder. Signing requirements: [Android official guide](https://developer.android.com/studio/publish/app-signing).
