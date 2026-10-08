# RC4 promotion inputs, pending final acceptance

Promote the existing owner-signed candidate run `37819214432`, source
`77a5f2dfde4ea914e7f2cf09dcbf77ee738056cc`, version `2026.10.2-rc.4+46`.
Its [signed artifact receipt](../evidence/rc4-signed-candidate/receipt.json) binds
Android-release artifact `11569174876`, Windows `11568777570` and Linux `11568853640`. Artifacts
from the later policy CI are not the selected signed candidate.

Reviewed main dispatch-policy source is
`3111dd94510a8f77e6978aa177e8d9b44fd7607c`. Policy SHA256
`257e124987e2a3f43c2f98c797880916d977b001a0f191850885e7e577a07147` passed
independent architecture, correctness and security review. The policy admits only
the complete, source/archive/member-verified optional three-file portable QA set
alongside every required original asset. Unknown and partial sets fail.

The three public installers are exactly:

- `tandemlog-2026.10.2-rc.4-android.apk`
- `tandemlog-2026.10.2-rc.4-windows-x64-setup.exe`
- `tandemlog-2026.10.2-rc.4-linux-x64.flatpak`

The portable ZIP, provenance, checksums, signatures and installation reports remain
engineering evidence. GitHub supplies its automatic source ZIP/tarball links.
The unchanged `release_assets.py` copies installer bytes; it does not rebuild.
`test_public_installers_are_versioned_and_byte_identical` verifies each staged
payload matches its original. `test_current_complete_portable_evidence_passes_without_public_extras`
verifies a fourteen-file candidate still stages exactly those three names and
leaves every source byte unchanged. These tests are among the reviewed thirteen
focused and fifty tooling tests; they are synthetic staging proof, not a claim
that this cloud consumer downloaded the signed APK.

The actual read-only promotion selector, executed with reviewed policy source `3111dd9`
and candidate run `37819214432`, returned
`sha=77a5f2dfde4ea914e7f2cf09dcbf77ee738056cc`. Application, native, dependency,
platform, packaging producer, publication workflow, public staging and notes/media
inputs are byte-identical between candidate `77a5f2d` and policy `3111dd9`. The existing trusted
dispatch route checks out `77a5f2d`, downloads the selected run's existing artifacts,
loads reviewed policy/notes from the dispatch commit, and stages accepted bytes.
It performs no Flutter/Gradle/native build or signing step. No rebuild or change
to frozen candidate bytes is required.

## Remaining operator gates

Policy CI `37822643601` completed successfully on exact `3111dd9`; its
[terminal receipt](../evidence/rc4-policy-ci/receipt.json) records all three green
platform jobs and desktop50 tooling cases. Publication still requires actual outer/inner artifact
and owner-signature verification, local exact package/device and Windows/manual/UX
acceptance, and a fresh quota read. Existing notes/media review remains applicable
because its bytes and covered executable behavior are unchanged. Stable
v2026.10.1 remains Latest; RC4 is prerelease-only/latest=false.

The only unknown command input is the exact inner APK SHA256 accepted by local
package/device QA. Obtain it from the actual accepted APK, match it to
`android-SHA256SUMS.txt` and `android-release-metadata.json`, and retain the owner
certificate/source/version verification. The outer artifact ZIP digest is a
different checksum. This consumer's artifact materialization returned403, so it
does not supply an invented APK hash.

## Command after all gates pass

This command is prepared for the coordinator and has not been dispatched. Set
`TANDEMLOG_ACCEPTED_APK_SHA256` to the locally accepted APK hash first. Re-read main
before dispatch; an advanced revision requires review of that dispatch policy and
notes, rather than silently substituting it for the reviewed source below.

```bash
set -euo pipefail
: "${TANDEMLOG_ACCEPTED_APK_SHA256:?Set the exact APK hash accepted by local package/device QA}"
[[ "$TANDEMLOG_ACCEPTED_APK_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]
TANDEMLOG_DISPATCH_SHA=$(gh api repos/reddraggone9/tandemlog/git/ref/heads/main --jq '.object.sha')
test "$TANDEMLOG_DISPATCH_SHA" = 3111dd94510a8f77e6978aa177e8d9b44fd7607c
gh workflow run prerelease.yml \
  --repo reddraggone9/tandemlog --ref main \
  -f tag=v2026.10.2-rc.4 \
  -f candidate_run_id=37819214432 \
  -f android_verified_sha256="$TANDEMLOG_ACCEPTED_APK_SHA256" \
  -f draft_release_id=''
```

The workflow selects the successful main signed run, checks absent tag and source,
retains APK/signer/version/installed-desktop/checksum gates, and publishes exactly
three installers with prerelease=true/latest=false. A promotion run ID exists
only after an authorized dispatch; no publication run has been created here.
