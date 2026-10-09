# RC5 exact-candidate promotion recipe

This recipe is prepared for review and remains **held**. It does not dispatch a workflow, create a tag or release, rebuild an installer, or promote stable.

## Fixed candidate

- Tag: `v2026.10.2-rc.5`; version/build: `2026.10.2-rc.5+48`.
- Successful main-only signed candidate: `37865723987`, attempt 1.
- Candidate source: `bc1fc99db53ef0ff9b9ad281ddefed4ea3bf234b`.
- Required artifacts from that run: `linux`, `windows`, `android-release`. IDs, digests and expiry are recorded in [candidate-receipt.json](candidate-receipt.json).
- Owner Android certificate: `0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d`.
- Notes are independently reviewed at the candidate source; their image link is pinned to media commit `c11441353a919f21cc54234685ed3a52a509ab2c`.

## Required evidence before dispatch

1. Receive the local worker's completed exact-artifact acceptance receipt, including actual ZIP/member integrity, APK package/version/code, owner signer, nondebuggable flag, computed inner APK SHA-256, native install/launch/upgrade and the bounded [delta workflows](native-acceptance.md). Match the inner APK hash to candidate metadata and checksum. A ZIP digest is not the operator's APK attestation.
2. Complete the independent candidate artifact/provenance and recipe review. Confirm the successful candidate remains unexpired and source/run bindings match the receipt.
3. Obtain fresh parent quota clearance using Lee's standing publication thresholds. Earlier quota readings are not clearance for this dispatch.
4. Freshly confirm remote main is still `bc1fc99db53ef0ff9b9ad281ddefed4ea3bf234b`, and the proposed tag/release does not already exist. This recipe reviews that dispatch policy and notes revision. If main moves, review its policy and notes before dispatch rather than silently changing this receipt.

After all four conditions pass, assign `RC5_ACCEPTED_APK_SHA256` from the verified local receipt. Dispatch the existing experimental preview workflow on main:

```bash
set -euo pipefail
[[ "${RC5_ACCEPTED_APK_SHA256:-}" =~ ^[0-9a-f]{64}$ ]]
gh workflow run prerelease.yml --repo reddraggone9/tandemlog --ref main \
  -f tag=v2026.10.2-rc.5 \
  -f candidate_run_id=37865723987 \
  -f android_verified_sha256="$RC5_ACCEPTED_APK_SHA256"
```

Do not execute this while acceptance, hash, review or quota clearance is pending.

## Existing enforcement and publication verification

The workflow resolves the supplied successful main-branch signed candidate from this repository, verifies tag/version, and checks out that exact candidate. It downloads the three release artifacts from run 37865723987 and performs existing APK hash/source/version/certificate, inventory, installed desktop lifecycle and checksum gates. It copies the accepted installers to versioned public filenames; it contains no application compilation or signing step.

The reviewed current dispatch supplies the trusted release policy and reviewed notes. Publication uploads only:

- `tandemlog-2026.10.2-rc.5-android.apk`
- `tandemlog-2026.10.2-rc.5-windows-x64-setup.exe`
- `tandemlog-2026.10.2-rc.5-linux-x64.flatpak`

The release must be experimental prerelease, `latest=false`, with tag target equal to the candidate source. Monitor through terminal success, then independently verify public source/tag, the three download bytes/digests/sizes, reviewed notes/image link, prerelease status and unchanged stable Latest `v2026.10.1`.

No private draft is presently needed because main and candidate policy are identical. If a separately reviewed later dispatch cannot create a release at a historical workflow-different commit, use only the existing owner-authorized private-draft path described in [releases.md](../../design/releases.md). Bind that draft's tag/source/numeric ID, validate exact three asset digests, attach without clobbering, and finalize through the authorized connection after every gate. Do not weaken a gate or change permissions to bypass a failure.

