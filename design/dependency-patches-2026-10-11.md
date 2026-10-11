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
  Both selected official merge commits report a valid verified GitHub signature.
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

Current npm registry advisory queries (`npm audit --omit=dev`, lock-only, no
install/scripts) report existing residual findings in both old and proposed
locks. Download has17 affected package nodes (14high/1critical/2moderate);
upload has17 (13high/4moderate). Old/new advisory URL sets, severities and
affected implementation versions are identical. In particular, the download
bundle retains fast-xml-parser5.3.4, upload retains parser5.4.1/builder1.0.0,
and both retain undici6.23.0/lodash4.17.23. These patches do not remediate those
inherited advisories. Registry counts include affected dependency ancestry,
not17 independently proven exploitable app vulnerabilities. No newly introduced
advisory is identified by this comparison. Runtime input exposure is limited by
fixed trusted repository filenames/globs and existing GitHub/Azure API/blob
destinations, but this is not proof every inherited library path is unreachable.
Maintain separate build-dependency debt: owner dependency maintainer; impact
potential runner denial-of-service/library exposure; exit official reviewed
action bundles with fixed affected dependencies and repeated cross-run/native
gates; revisit next Actions patch or earlier if input exposure/advisory changes.

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
Producer run[38159734007](https://github.com/reddraggone9/tandemlog/actions/runs/38159734007)
uploads a408-byte synthetic ZIP with the new upload action. Consumer
[38159774647](https://github.com/reddraggone9/tandemlog/actions/runs/38159774647)
passes the new download action with a different explicit run-id, github-token,
and digest-mismatch:error. ZIP SHA256
`90d044015b6090f9d3bd959c1cddd795e9906ba0d4921c3d5f76b87424709d68` matches
the service digest. Exact extracted set and bytes pass independently:
`dependency smoke café 東京.txt`46bytes/SHA256
`56b4f9b18877709a912cf6f1cd80242acf82c80658689ae7dc3e520d024b4947`;
`provenance.json`56bytes/SHA256
`d410129eabad091cb11780b65ce97e52f855596717f6afe283fdee65bc544e1f`.
The original producer's native job failed before testing because its isolated
workflow omitted the existing Rust bootstrap; the actual artifact job succeeded.
The consumer run itself is wholly green. No real release artifact is downloaded.
The production adoption branch retains the real release workflows and changes
only the reviewed SHA pins in them. Never merge the temporary smoke workflow.

The final corrected synthetic fixture is at smoke source
`d11ca1d617703f4c294620692f4f5d6bd06e94f0`, run
[38160920589](https://github.com/reddraggone9/tandemlog/actions/runs/38160920589).
That complete run is green: one rejected-launch unit test and both native GTK
processes pass, including exact Unicode/spaces dispatch and the real missing
manager Settings warning/disabled button with retained initialized file bytes.
Runs38160544187/38160610363 passed Settings availability/warning/disabled-button
assertions, then failed the fixture's directory-set assertion: opening a fresh
synthetic workspace deliberately initialized its space manifest/user log.
The correction freezes all initialized file bytes before Settings navigation
and requires exactly that set and those bytes afterward. The retained sentinel
is still checked against its original bytes. This accounts for expected setup;
it does not permit folder-opening or failure recovery to mutate canonical logs.

The native folder smoke exercises production FolderActions through the actual
Linux GTK plugin. An isolated synthetic desktop handler receives one exact
path containing spaces, café and 東京; the missing-handler process removes all
desktop app discovery. Both check retained file bytes and directory contents.
This bounds native Linux URI/launch behavior, not manual Windows/physical-device
or visual acceptance of a replacement signed release.

The first built native run[38159886801](https://github.com/reddraggone9/tandemlog/actions/runs/38159886801)
passes opening but rejects an overstrong fixture assumption: with no handler,
capability detection is false while GTK still returns successful dispatch if
launch is called directly. The app's actual Settings capability guard disables
the action in this state. The corrected native test checks that guard/warning;
a separate method-channel unit test verifies the adapter's false-launch response
and recovery message. Both pass in the final run. Neither introduces a production change. The initial
failed expectation is preserved, not represented as a green native run. Two
subsequent isolated attempts stopped at fixture formatting before native tests;
the local pinned Dart formatter now explicitly uses the app language version3.9
to match pub's package configuration. These are fixture preparation failures,
not evidence of a url_launcher patch regression.

Inherited desktop reliability limit: a manager disappearing after capability
detection may still be reported as a successful dispatch by GTK. No guarantee
of the external manager displaying a window is added here. Owner desktop
integration maintainer; revisit on the next folder-action/native launcher change;
exit a reviewed stronger observable contract or accepted bounded limitation.

Actual extracted executable bundle tests pass on download and both upload/merge
bundles: five attempts, exactly120s allowed waiting,121s fail-before-sleep,
positive/invalid/date/array header behavior,8s fallback, orchestration sanitization
and idempotence, BigInt precision/noisy-string round-trip and UTF-8 basename
sanitization. [Source and evidence](../evidence/dependency-patches-2026-10-11/)
record exact bundle hashes, npm advisory comparisons and original failures.

Full PR CI[38159861434](https://github.com/reddraggone9/tandemlog/actions/runs/38159861434)
uses prepared dependency source `77b0c5fa71c58c39eeaf8c9045be00a3246dbcc4`,
based on main `e6ba275`. Android and Windows jobs are green; Linux format,
analysis, app unit tests, native admission/worker contracts and release-tool
tests passed before the full native suite. The final terminal result is recorded
below when available. Later evidence/fixture changes do not change production
inputs, dependency resolution or release workflow semantics. A `[skip ci]`
evidence commit preserves this already running matrix; final exact-head full
checks remain required after the coordinator's RC source settles and this
proposal is rebased. This draft has no integration or release acceptance.

The completed Android and Windows CI archives were independently downloaded
through the existing connector and verified against service ZIP digests, exact
file sets, ZIP CRC and internal payload SHA256 files. Android artifact11710485446
is a test-only debug APK, not an owner-signed release. Windows artifact11710380360
contains the unsigned installer and portable ZIP. The retained Windows unit
artifact11710100488 also matches its service digest and reports1014 passes,
two skips and zero failures with a successful final summary. The
[artifact receipt](../evidence/dependency-patches-2026-10-11/current-ci-artifact-verification.json)
binds IDs, source/run, filenames, sizes and hashes without temporary download
credentials. No installation or release acceptance is inferred from archive
verification.
