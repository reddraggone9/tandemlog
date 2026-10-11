# Bounded dependency patches — 2026-10-11

Status: reviewed isolated adoption proposal; integration and publication held for
the release coordinator. Based on current main `e6ba275` after the RC3 fixture
correction. RC3 candidate `38156985011` remains bound to
`3c162347105bbd01f55ef09652d29c397d013e01`, build65. No candidate is rebuilt,
cancelled, signed or published by this audit. Held AGP #1 and Gradle #2 are outside
scope. No production workspace or import is used.

## Exact inputs and executable review

- Dependabot #5 head `5a1aefdd577ae862117b369067397e8716ce249f`:
  [download-artifact 8.0.1 → 8.0.2](https://github.com/actions/download-artifact/compare/3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c...9000827ccba6bdab643e8b6fd33ac0654aef8333).
  New immutable pin `9000827ccba6bdab643e8b6fd33ac0654aef8333` matches official
  v8.0.2. Reviewed complete committed `dist/index.js` delta, lock/manifest,
  action definition and license changes. `src` and `action.yml` do not change;
  Node24 selection remains. Bundled `@actions/artifact` 6.2.1→6.3.1,
  core3.0.0→3.0.1, github9.0.0→9.1.1, http-client4.0.0→4.0.1,
  Azure storage-blob12.30.0→12.31.0/storage-common12.2.0→12.3.0,
  Octokit endpoint11.0.2→11.0.3/request10.0.7→10.0.8/retry8.0.3→8.1.0,
  and new json-with-bigint3.5.3 are covered by the actual executable delta.
  Large integer JSON/URI handling preserves API integer precision; retry fixes
  correct the GraphQL request call and retry helper binding. The Azure delta in
  this bundle is version metadata and equivalent assertion parentheses; its
  service version remains `2026-02-06`.
- Dependabot #6 head `1d8f4e2ad9e4bd11cf18b47e88478a3968c5a459`:
  [upload-artifact 7.0.1 → 7.0.2](https://github.com/actions/upload-artifact/compare/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a...cf430e030ddbb5b0abf93d22962f4752f3646cd9).
  New immutable pin `cf430e030ddbb5b0abf93d22962f4752f3646cd9` matches official
  v7.0.2. Reviewed both `dist/upload/index.js` and `dist/merge/index.js` deltas,
  lock/manifest, action definition and licenses; source/action definition stay
  unchanged. Artifact6.2.0→6.3.1, core/github/http-client versions match the
  download update above. Its external response filename parsing now prefers
  RFC5987 UTF-8 `filename*`, falls back to plain `filename`, and keeps
  `path.basename` sanitization. This helper is bundled even though the app only
  uses the upload entrypoint. Quota error copy no longer promises recalculation
  in6–12hours.
- Both action bundles use five artifact API attempts, an8s base retry interval,
  and at most120s cumulative retry **waiting**. Positive integer429
  `Retry-After` seconds are accepted; HTTP-date, zero and malformed values fall
  back to exponential jitter. Oversized waits fail before sleeping. This is not
  a120s wall-clock timeout for the whole action or its network requests.
  `ACTIONS_ORCHESTRATION_ID` is trimmed/sanitized into an Octokit User-Agent
  suffix for the existing GitHub API; no new destination, token scope or app
  data upload is introduced by the delta. No changed runtime package declares
  `hasInstallScript`; Actions execute committed JS, not npm install/build hooks.
- Dependabot #7 head `27073ff47910fc50f051039666348335e98f00e1`:
  url_launcher6.3.2→6.3.3. Downloaded both official pub archives and matched
  SHA256 to their respective locks:
  old `f6a7e5c4835bb4e3026a04793a4199ca2d14c739ec378fdfe23fc8075d0439f8`,
  new `e8cc955c97e06df9879140a1fe301f3d493f01b7c62dec7f46834be31d7e9fda`.
  Reviewed library, manifest, tests and packaged example/platform changes.
  `supportsCloseForLaunchMode` now calls `supportsCloseForMode`; app folder
  navigation uses `canLaunchUrl`/`launchUrl`, with no invocation of the changed
  close-support query. Other shipped library changes are formatting, copyright
  and equivalent local typing; packaged example platform modernization is not
  app build input. No new hook/native binary is added. All federated native
  implementation versions and hashes remain unchanged in the app lock.

## SDK and product implications

url_launcher6.3.3 raises its own floor to Dart3.11/Flutter3.41. The current graph
already requires Dart3.12/Flutter3.44; pinned Flutter3.47.5/Dart3.13.4 meets both.
Root manifest `>=3.9.0` has already been weaker than the resolved graph and is
retained for this bounded patch. It is not a promise this lock builds on3.9.
If the product intends to support older development SDKs, that is a separate
toolchain/graph decision, not a reason to silently relax the lock or change this
release candidate. No user-facing feature or durable-data change is identified.

All action references remain immutable. Release permissions, trusted-main
admission, signing cleanup, app version, owner pin, Android tooling and release
notes remain unchanged apart from the requested action SHA replacements.

## Verification

Local release/tool checks:74 tests pass with one existing platform skip.
Local exact artifact fixture filenames, bytes and SHA256 checks pass. Native
application checks run on hosted runners because this fresh audit environment
does not have Flutter, GTK or Rust installed. Ordinary PR CI has no cross-run
download step, so it cannot establish promotion-path acceptance alone.

The temporary `audit/dependency-smoke-20261011` branch substitutes a read-only
synthetic workflow for the registered prerelease workflow **on that branch
only**. It retains existing contents:read/actions:read scopes, contains no
publication/signing jobs or secrets, and has a separate concurrency group.
Producer/consumer run IDs and final native/CI outcomes are recorded when complete.
The production adoption branch retains the real release workflows and changes
only the reviewed SHA pins in them. Never merge the temporary smoke workflow.

The native folder smoke exercises production FolderActions through the actual
Linux GTK plugin. An isolated synthetic desktop handler receives one exact
path containing spaces, café and 東京; the missing-handler process removes all
desktop app discovery. Both check retained file bytes and directory contents.
This bounds native Linux URI/launch behavior, not manual Windows/physical-device
or visual acceptance of a replacement signed release.
