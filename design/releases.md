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
