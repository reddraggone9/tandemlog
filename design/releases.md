# Builds and releases

How a Tandemlog release is made today. This file holds the procedure and its rules only. What each past release contained and how it went is in that release's `evidence/` folder and in [release history](archive/release-history.md); do not add per-release sections here.

## Who decides what

- **Lee decides:** promoting an RC to stable; any live data migration or cutover; replacing or rotating the Android signing key; paid runners; branch-protection changes; history rewrites; loosening a performance budget.
- **The maintainer (currently Vex) decides without asking:** pushing development branches, running CI, signing candidates with the existing key, and publishing an RC as an experimental prerelease once the candidate has passed every check below. Lee tries the RC and gives feedback; stable follows only after he reports no problems (Lee, 2026-10-26).
- Standing exception (Lee, 2026-10-04): a reviewed stable update that changes no user-facing behavior may be published after every gate without a fresh acceptance. Record why behavior is unchanged in the candidate receipt before setting `lee_accepted`.

## Rules that shape a release

- **Scope freezes at validation (Lee, 2026-10-26).** Once an RC is in validation it proceeds with minimal changes unless Lee says otherwise or there is a real blocker. New fixes go on their own branch and into the next release; if none is open, start one and take it to a published RC without waiting for Lee.
- **Release branches stay linear: rebase, never merge.** `main` requires linear history with no bypass, and the reference-performance verifier requires the qualified commit to be an ancestor of HEAD. A merge commit in an RC branch forces a flatten and a fresh qualification.
- **A format change ships in one release (Lee, 2026-10-27).** New clients read all old history; an older install that meets something new stops with the Update screen and every device gets updated. Never split a feature into a reader release and a writer release.
- **A format-changing RC gets an isolated trial.** Anything that makes going back to the last stable hard is tried on a separate workspace and profile with a copy of the data, never on the live synced folder (see [RC handoff](#6-hand-the-rc-to-lee)).
- **CI runs once per commit under test.** Batch work before dispatching. Never redispatch unchanged source to get a green result. One `rerun --failed` is allowed, without asking, for a diagnosed infrastructure failure (runner download error, slow-runner timeout); keep the original failure in the evidence. A deterministic app, test or packaging failure needs a source fix and a fresh run.
- **Reference performance** follows [the gate rule](performance-gate.md#the-gate-rule-lee-2026-10-31): one sample per action, an automatic same-invocation rerun of misses, and a failure only when the same label misses twice. There are no manual timing reruns, noise evidence or owner overrides in the current rule. A repeatable miss is profiled and fixed; a budget is loosened only by Lee.

## The release, step by step

### 1. Before the candidate

- Every new or non-trivially changed screen, row or dialog has had its UX pass (brief before building, independent screenshot review after; see `AGENTS.md` and [UX principles](ux-principles.md)), and Lee has seen review captures of UI changes.
- New or materially changed actions are in the performance inventory with budgets, correctness assertions and history-growth coverage where relevant ([maintenance contract](performance-gate.md#maintaining-action-coverage)). A slow first implementation is not its own baseline.
- The release source has a passing controlled-reference qualification ([protocol](performance-reference-qualification.md)). New qualifications use identity v3 (Lee 11-12): only the benchmark's compiled Dart import/export/part closure, `tool/performance/`, `pubspec.lock` and the native engine (`native/`) void them. Tests, platform packaging, workflows and unrelated app code do not. Budgets are unchanged. Old receipts retain their recorded scheme. Run `python3 tool/performance/reference_receipt.py verify --repo .` before reusing a qualification. Qualify last, after every other CI job is green (`reference-performance` alone will be red), then commit the receipt and dispatch the candidate.
- Architecture, duplication, stale code, docs drift and migration/recovery behavior have been reviewed for the changes in this release; fixes or remaining risks are recorded in the release's evidence README.
- `pubspec.yaml` carries the release version and a new, higher build number, and the Flatpak metainfo has the release entry. When a stable replaces its RC, **replace** the same-base `-rc.N` entries in the metainfo instead of adding the stable above them: strict AppStream ordering can treat the stable name as older than its RCs (this failed stable 2026.10.9's first candidate).
- `design/prerelease-notes.md` (RC) or `design/stable-notes.md` (stable) is written for this release and has passed the [notes review](#release-notes-and-media).

### 2. Build the signed candidate

Dispatch **Build signed candidate** (`android-candidate.yml`) on `main`, once. It checks the signing pin and that the Android build number is higher than every published tag and every earlier successful candidate from a different commit, runs the full validation matrix (the same reusable workflow as CI), then builds a universal non-debuggable APK with the owner key. It publishes nothing. Candidate runs are serialized. Artifacts (`linux`, `windows`, `android-release`) expire after five days; if they expire, rebuild and re-accept.

Wait for it with the shared waiter described [below](#waiting-for-an-already-dispatched-signed-candidate) instead of a hand-written polling loop.

### 3. Accept the exact artifacts

Acceptance is of the downloaded candidate bytes, not of a local build:

- **Android:** install the exact APK over the previous stable (and over the previous RC when one exists) on the retained synthetic emulator labs; check that the install identity, folder grant and history survive, exercise the changed workflows, cold-reopen, and confirm the canonical logs only grew.
- **Linux:** install the exact Flatpak over the previous version in the isolated GTK lab; same checks, plus a clean normal exit.
- **Windows:** the candidate workflow installs, launches, replaces, uninstalls and reinstalls the setup EXE on a hosted runner and verifies the portable ZIP's inventory. No release step drives the Windows GUI; Lee's own trial on his Windows PC is the only Windows GUI coverage. Say so in the receipt rather than claiming more.
- Emulators and labs use synthetic data. A cross-build, a browser preview or a debug build is not native evidence.

Record what was and was not covered in `evidence/<prerelease|stable>-<version>/README.md` with the machine-readable receipts beside it.

### 4. Publish the RC

Dispatch **Experimental prerelease** (`prerelease.yml`) on `main` with the tag, the successful candidate run ID and the SHA-256 of the APK that passed step 3 (an operator attestation, not an automated device test). The job re-verifies provenance, source, version, signer pin, APK hash, the complete asset set and checksums, then publishes the already-tested artifacts without rebuilding, as `--prerelease --latest=false`. The job takes its gate scripts and `design/prerelease-notes.md` from the dispatch commit on `main`, and source and artifacts from the candidate, so a notes-only fix can land on `main` after the candidate. Only the publication job has contents-write permission; signing secrets never enter it.

The public assets are the three versioned installers plus the Windows portable ZIP. Releases are immutable once published and reject later uploads, so all four must be attached before publication (Lee, 2026-10-28).

**Private-draft path.** When the candidate's workflow files differ from `main`'s, the Actions token cannot create the release. Create a private draft for the exact tag and candidate commit with the maintainer's own GitHub credential, pass its numeric ID as `draft_release_id`, let the workflow attach and verify the assets, then finalize the draft with the same credential after checking source and digests. The same gates run; nothing is clobbered.

### 5. Verify the public release

Anonymously download every asset and compare hash and size with the accepted candidate; verify the public APK's signer against `android/signing-certificate.sha256`, its version and non-debuggable flag; check tag, target commit, notes, images and the prerelease/Latest flags. Record the result in the release's evidence folder.

### 6. Hand the RC to Lee

Every RC comes with a ready-to-use isolated installation, not only a download link (Lee, 2026-11-07). Choose his Android phone or his Windows PC by what changed, availability and setup effort; honor a device he names. No fresh permission is needed for this step.

- Keep the stable installation, its settings and its data untouched.
- **Android:** build the exact accepted RC source in release mode with a distinct application ID and a clear test label. Record source, the packaging-only changes, signer and hash, and tell Lee it is a test variant, not the byte-identical published APK.
- **Windows:** use the accepted portable ZIP with a separate profile and shortcut (the installer shares stable's AppId, so it cannot sit beside stable).
- Bind the test install only to a private, non-synced copy of realistic data, never the live workspace.
- Verify version, coexistence, the isolated binding and a usable launch. Report a locked or unavailable device as a blocker instead of skipping the step.
- Tell him the app or shortcut name and what first use will ask for.

Send short notes and review media with the handoff. This trial does not replace step 3 and does not authorize stable.

### 7. Promote to stable

After Lee accepts the RC:

1. Change only the version/build in `pubspec.yaml`, the metainfo release entry, `design/stable-notes.md` (the reviewed RC notes body, unless something changed) and, if needed, the README (below). Verify the reference qualification still matches; do not requalify a version-only change.
2. Build a signed candidate for the stable name (step 2) and run scripted hash, signing and upgrade checks on its exact artifacts from the RC and previous stable. A version-only promotion needs no new reviewer agents or manual lab walkthroughs (Lee, 2026-11-12). Do not relabel or rebuild RC artifacts inside publication.
3. Publish as Latest. **The reusable private-draft tools** below replace unused `stable.yml`: run the same `candidate_source.py`, `publish_gate.py` and `release_assets.py` gates from the candidate source, create a private draft with all four assets, verify it, then finalize it as Latest. No artifact is rebuilt during publication.
4. Verify the public release (step 5), including that earlier releases and tags are unchanged.
5. Review the README against the released workflows and update it for meaningful user-visible capabilities. Keep it about what the app does, with a short accurate folder-sync explanation and install links.

A stable is finished for its users when their installed copies have it; the maintainer tracks that outside this repository.

### 8. Records

One record per release: `evidence/<prerelease|stable>-<version>/README.md` plus its receipts. Update the "Released" line in [status](status.md). Failed candidates and failed qualifications stay in the evidence with their original attribution; do not overwrite or relabel them.

## CI

Standard GitHub-hosted Ubuntu 24.04 and Windows 2022 runners, pinned official actions, Flutter 3.47.5 at a verified source revision. No larger or paid runners. Intermediate artifacts expire after five days. CI artifacts and releases are public.

Every executable-change push to `main`, every pull request and every manual run does formatting, analysis, the complete domain/storage integrity/convergence/recovery suite, native Linux integration and release-startup smoke checks (fresh and warm SQLite), and Linux release, Windows release and Android debug builds. Windows also runs the domain/storage tests. No integrity test is removed for previews.

Manual runs: `gh workflow run ci.yml --ref <branch> -f calibrate_performance=false`.

The native Linux workflow suite (`integration_test/task_flow_test.dart -d linux`) runs as four parallel `linux-workflows` shards. Sharding only parallelizes: each shard gets a contiguous, disjoint slice of the declared cases, and `linux-workflows-union` ([`tool/verify_test_shards.py`](../tool/verify_test_shards.py)) fails unless every shard finished green, sizes match, no case ran twice, slices are in declaration order and every registration site ran. Adding cases needs no change; changing the shard count means editing the matrix, `--total-shards` and the union file list together (a tooling test checks they agree).

**`reference-performance` is red on development branches by design.** That job only verifies that a controlled-reference receipt and a native cold-start result (1.0 s median to the first task list on the reference host; Lee, 2026-11-03) exist for the exact relevant source, and both are produced when a release is prepared. On a branch or pull request whose source has no receipt yet, a failure of that job alone is expected and says nothing about the change; judge the run by its other jobs. On a release candidate it must pass.

Hosted timing is advisory; hosted correctness is mandatory. Absolute and history-growth budgets are enforced only on the controlled reference host ([ADR0033](decisions/0033-controlled-reference-performance.md)).

**Linux quit-time abort.** Until 2026.11.1 the Linux job's normal-exit check (`verify_linux_disposal.py`) occasionally saw an abort at quit (`FlutterEngineRemoveView` kInvalidArguments, then `g_mutex_clear`); the renderer-lifetime fix in 2026.11.1 (`0b9aaf1`, `e930f31`) addressed it. If an abort at quit shows up again, collect core stacks ([`tool/collect_linux_core_stacks.py`](../tool/collect_linux_core_stacks.py)); do not redispatch to clear it.

**Documentation-only pushes** (only Markdown or `evidence/` changed) skip push CI. Pull requests, manual runs and the signed candidate always run the full matrix, and publication requires that candidate run's exact artifacts.

Android builds install the [reviewed repository routing policy](decisions/0020-build-dependency-repository-routing.md) into a fresh job-temporary Gradle home before resolution; owner signing byte-verifies that policy before materializing the keystore. Local owner builds run `python3 tool/gradle_repository_policy.py install` with the same `GRADLE_USER_HOME` as the build, on a trusted unshared host. A changed toolchain or repository graph needs a policy review; do not bypass a routing failure.

## Versions

[CalVer](decisions/0008-calver-and-release-promotion.md): `year.month.patch`, unpadded month, optional `-rc.N`, and a separate build number that only ever increases. The tag must match the candidate's display version. A stable needs its own build number, higher than its RC's. The parser rejects Windows resource components above 65535 before compilation. Same-source candidate retries are allowed before publication; increment the build number before handing out a changed candidate. Ordinary local, push and PR debug builds need no signing secrets and are never selected as the public Android asset.

## Public downloads and candidate files

Public names: `tandemlog-<version>-android.apk`, `tandemlog-<version>-windows-x64-setup.exe`, `tandemlog-<version>-linux-x64.flatpak`, `tandemlog-<version>-windows-x64-portable.zip`. `<version>` comes from the validated candidate source; the bytes are the accepted candidate's, copied, never rebuilt. GitHub supplies the source archives. Historical release assets are never changed.

| Candidate file | Used for | Public |
| --- | --- | --- |
| APK / setup EXE / Flatpak | Installation; native acceptance | Yes, versioned names |
| Windows portable ZIP | Side-by-side RC trial; no-install desktop use | Yes, versioned name |
| Three platform `SHA256SUMS` files | Publication verifies accepted bytes | No, kept in candidate artifacts |
| Android signature report and release metadata | Signer, package, version, source and exact-APK gates | No |
| Linux startup report | Release startup evidence | No |
| Linux and Windows install-smoke reports | Installed-lifecycle gates | No |
| Portable ZIP checksum and member-hash provenance | Publication validates the ZIP and its members | No |

The publication policy accepts the portable ZIP only as the exact three-file set (archive, checksum, provenance); partial sets, unknown extras and unsafe members fail. Internal candidate filenames stay stable so the gates keep using the original artifacts; only the public copies gain the version. Nothing consumes the diagnostic JSON or checksum files as public metadata (Obtainium selects the APK through GitHub's release API). Do not remove checks or historical downloads to shorten the public list.

Installation and runtime guidance: [packaging](../packaging/README.md).

## Release notes and media

- Notes say what changed for the user: changes, fixes and improvements since the previous release of the same kind. One change per bullet (Lee missed a second change joined to another by a semicolon). No expected behavior, preservation assurances, testing statements or signing boilerplate; those belong in evidence.
- Do not warn about routine cross-device updates, even when the release adds event types: the app's Update screen explains that. Keep compatibility notes for exceptional, actionable requirements (a manual migration, an unsupported upgrade path, a risk the app cannot explain), state the action, and do not carry older warnings forward.
- The Windows portable ZIP needs no mention.
- Images: one tightly cropped, labeled Before/After per change by default, only where it explains something prose does not. Real app, matching synthetic data, theme, viewport and text scale; Dark theme unless the change is about Light. Canvas close to the app background with enough contrast to show the crop edge; centered Before/After labels only; descriptive alt text. Images live in the repository and are linked at an exact commit; they are not release assets. Record source revisions, raw captures and the crop recipe in the evidence.
- **Notes review (asked for by Lee; goal: notes that are complete and free of detail users do not need).** Before any publication a separate reviewer (not the author) gets the draft notes and media, these rules, and the exact covered commit range and diff. They check that meaningful user-visible changes are covered accurately, that implementation and testing detail is gone, that images are real, readable and free of private data. The author fixes findings and the reviewer rechecks material revisions. Record the outcome with the candidate evidence. A stable whose notes body is byte-identical to its single RC's reviewed notes has had its review; a stable that combines several RCs or changes the text is reviewed again.
- Editing these rules or a draft does not change already published notes.

## Waiting for an already-dispatched signed candidate

Use the shared read-only `tool/wait_signed_candidate.py` instead of copying a
release-specific dispatch/wait script. Dispatch authorization/one-attempt claims
remain separate: this tool accepts an **existing run ID**, never dispatches a
workflow, never reruns a job, and never publishes. Pin the full candidate source
SHA (not today's main). It fails closed on wrong repository, workflow, event,
branch, source, unsuccessful conclusion, CLI error, timeout or incomplete download.
No automatic retries hide a failure; fix authentication/network issues and resume
**the same run ID**, not a new build.

For long waits on the Linux engineering host, launch through the user systemd
manager so the worker's lifecycle is independent of the requesting shell/tool:

```sh
python3 tool/start_candidate_wait.py \
  --run-id EXISTING_RUN_ID --source FULL_CANDIDATE_SHA \
  --output /absolute/private/evidence/candidate-RUN_ID
```

The command prints its deterministic unit name and inspection command. It returns
after manager activation, **not** after download success. Do not append `&`,
`nohup` or `setsid`; those do not escape an executor's descendant cleanup/deadline.
Use an absolute output directory outside the checkout. Requires a running Linux
user manager, `gh` in its PATH and an authenticated `gh` credential store. On the
engineering host, the existing private credential can instead be read by the worker:
append `--token-file /home/lee/.config/vex-github/token --direct-network`. This
passes only a file path, not a token value, to systemd. `--direct-network` removes
inherited proxy variables; use it only where direct GitHub access is intended.
Never put credential values in command arguments, logs or unit properties. The
foreground waiter uses the same flags and can use inherited `GH_TOKEN`/`GH_HOST`
where appropriate, but manager launches do not inherit the caller's shell env.

Inspect **both** the receipt and service result (substitute the printed unit):

```sh
systemctl --user show UNIT -p ActiveState -p SubState -p Result -p ExecMainStatus
cat /absolute/private/evidence/candidate-RUN_ID/wait-status.json
tail /absolute/private/evidence/candidate-RUN_ID/wait.log
```

Success requires `phase=success`, the requested run/source/repository, a complete
`candidate-download/download-receipt.json`, and service `SubState=exited`,
`Result=success`, `ExecMainStatus=0`. While running, systemd's `Result=success` and
`ExecMainStatus=0` **are not completion evidence**. Each poll rewrites the status
heartbeat even with no GitHub status change. A stale nonterminal heartbeat or a
failed/missing unit is a failure/unknown, never silent success. Unit results are
retained (no `--collect`, no restart); consult the journal for an OOM, SIGKILL,
manager deadline or host shutdown that prevented Python's terminal receipt.
Defaults: 7,200-second total wait/download deadline, 600-second individual CLI
bound, 60-second polls; the service has a further 30-second outer margin and
10-second whole-cgroup termination bound. SIGTERM/INT writes a failed receipt;
SIGKILL/power loss cannot. User-manager shutdown/reboot is not a survival promise.

On a diagnosed local failure or completed-download verification, stop the exact
printed unit (`systemctl --user stop UNIT`; `reset-failed UNIT` if failed), then
rerun the launcher with the same identity/output. Never stop an active worker just
to start a duplicate. An OS-released advisory lock excludes concurrent writers;
there is no stale lockfile to delete. An interrupted partial staging directory is
not success and may be preserved for diagnosis. A resumed successful download
checks its source and all saved file hashes without another GitHub request. If
those bytes changed, preserve them and use a new output directory for the same
existing run. Do not overwrite or relabel old evidence.

Each of `linux`, `windows`, `android-release` is downloaded separately. Empty sets,
symlinks and duplicate flattened filenames fail; only after all succeed does an
atomic rename expose `candidate-download/{artifacts,dist,download-receipt.json}`.
SHA-256 values bind the local bytes for recovery, **not publication acceptance**.
Run all existing inventory/checksum/source/signer/native/publication gates against
that `dist` exactly as before. This waiter does not install or qualify a candidate.

Regression checks: `python3 -m unittest discover -s tool -p test_wait_signed_candidate.py`.
Historical cause and local/live read-only evidence:
[wait/download lifecycle repair](../evidence/release-wait-repair-20261028/README.md).

## Dependency maintenance

[Inventory and per-version review](dependencies.md) separates app/dev, native/build and Actions dependencies. Dependabot proposes at most three pub, two Actions and two Gradle PRs (weekly pub/Actions, monthly Gradle) and never merges. The custom Flutter source pin, hosted images, inherited SDK/NDK defaults, Java patches, apt tools and Flathub revisions need periodic manual review. Before evaluating an update, review every changed direct and transitive version's source, hashes, native payload selection and install/build hooks, and choose native coverage from its application impact. The full release gates still apply.

## Android signing

Lee authorized a dedicated durable signing key generated/stored under the engineering account on the engineering host (called Farnsworth in older documents and in the registered reference-host ID; renamed Bender on 2026-11-08). The repository's Actions secrets hold a copy for hosted signing; maintaining them and the signing tooling is routine maintainer work, while replacing or rotating the key is Lee's decision (installed copies refuse updates signed by a different key). The public SHA-256 certificate fingerprint is pinned in `android/signing-certificate.sha256`; the supplied fingerprint is now pinned, and the owner-provisioned inputs successfully signed candidate run `36762053783`. Android release builds fail without all signing inputs; there is no generated-key or debug-key fallback.

At [repository Actions secrets](https://github.com/reddraggone9/tandemlog/settings/secrets/actions), choose **New repository secret** for each:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Standard Base64 encoding of the complete binary keystore, preferably one line; not the keystore path or a PEM certificate. |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password. |
| `ANDROID_KEY_ALIAS` | Alias of the signing key inside that keystore. |
| `ANDROID_KEY_PASSWORD` | Password for that key; may equal the store password. |

Owner-only CLI alternative on the trusted machine: `base64 -w 0 /path/to/keystore | gh secret set ANDROID_KEYSTORE_BASE64 --repo reddraggone9/tandemlog`; use interactive `gh secret set NAME --repo reddraggone9/tandemlog` prompts for the other values. Do not place passwords in shell command arguments/history or send private material through chat/Library. Keep an owner-controlled encrypted backup. The supplied public certificate SHA-256 is pinned; the generated PKCS12 key alias is `tandemlog-release`. Only public fingerprints (64 hex digits without colons) belong in the repository. [GitHub's secret setup guide](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) documents the UI and binary encoding convention.

Only the main-gated manually dispatched signing job references these secrets, scoped to its build step. It decodes the keystore under runner temporary storage with restrictive permissions, disables persistent Gradle daemons, verifies the APK signer/package/version/non-debuggable flag/phone and emulator ABIs, and removes temporary material on success/failure/cancellation. It does not upload/cache the key or write key.properties. The workflow grants read-only repository access; no signing secrets are passed to PR/debug validation. Repository secrets themselves are not platform-restricted to this workflow: GitHub environment protection would be a separate owner-approved hardening decision, not something configured here.

## Reusable private-draft commands

Run from the repository root (Python 3; `gh` uses inherited authentication). All paths are
explicit; keep `--output` outside the checkout, in private local evidence.
No command dispatches CI, merges, edits main or rebuilds candidate bytes.
`--lee-accepted` records an existing acceptance, not a request for one.

```sh
python3 tool/freeze-prior.py --repo-dir REPO --tag TAG --output EVIDENCE
python3 tool/verify-candidate.py --repo-dir REPO --tag TAG --output EVIDENCE --dist DIST --source FULL_SHA --build-tools ANDROID_BUILD_TOOLS
python3 tool/publish-stable.py --repo-dir REPO --tag TAG --output EVIDENCE --lee-accepted --notes REPO/design/stable-notes.md --policy-revision origin/main draft --dist DIST --run-id RUN_ID --android-sha256 ACCEPTED_APK_SHA
python3 tool/publish-stable.py --repo-dir REPO --tag TAG --output EVIDENCE --lee-accepted publish
python3 tool/verify-public.py --repo-dir REPO --tag TAG --output EVIDENCE --build-tools ANDROID_BUILD_TOOLS
```

The draft command writes its creating intent before the GitHub mutation. Recover
an interrupted draft by inspecting the saved state and GitHub; do not delete state
and retry. Publication verifies unchanged prior releases, exact draft bytes,
source and notes before finalizing Latest. Public verification is anonymous and
checks every asset, pinned note image, Latest, immutability and frozen prior tags.

Qualification helpers migrated from q16 live in `tool/qualification/`. Use
`qualification.py --help`: `prepare`, `run`, and `seal` are explicit separate
actions taking the same absolute `--repo`, `--output`, `--lab`, `--controller`,
`--dart`, `--native-library`, `--sqlite-library`, `--package-config` paths.
The existing reviewed controller and libraries remain host-provisioned and pinned;
package configuration comes from an explicit compatible prepared environment,
not a hard-coded old run. Use background-pause admission before `run` per the host
quiet-window procedure. The gate remains one-shot and sealing refuses failed
results. Exact owned reference units have their terminal result saved before
`reset-failed`; unrelated or active units are never reset. The external host
health-monitor ignore is not changed here: drop/narrow it after rollout verifies
all host-side producers use this cleanup path.

Regression checks: `python3 -m unittest discover -s tool -p test_release_tooling.py`.
