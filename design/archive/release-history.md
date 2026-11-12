# Release history (moved from design/releases.md, 2026-11-12)

Per-release sections and retired runbooks, moved here verbatim when `design/releases.md` was reduced to the current procedure. Nothing below is current policy; the release receipts in `evidence/` remain the authoritative record of each release. Relative links were written for `design/` and are adjusted only by the leading `../`.

## Markdown authority and final cutover

Historical migration policy: Lee kept editing the Markdown todo list as the authoritative record throughout the early prereleases. On 2026-10-04 the coordinator confirmed Tandemlog is now authoritative. Stable publication does not authorize another cutover, source change or canonical cleanup. The following runbook governs any separately requested future import. Every rehearsal must use a clearly identified COPY. The default canonical folder path and Syncthing share are permanent; only their test contents are disposable. A passing snapshot is not the final import; do not treat test-app changes as authoritative or silently merge them back. Private source text, hashes, backups and diffs stay outside the public repository.

For any separately requested future source cutover, coordinate with Lee:

1. Obtain explicit agreement to pause Markdown edits and relevant app/sync writes for the chosen window, and confirm the existing permanent destination and every participating device. Keep its path and share configuration.
2. Snapshot and back up the latest Markdown source AND the existing test destination before any separately authorized cleanup. Verify the copies; retain recovery paths. Disposable does not authorize deletion by itself.
3. Import a fresh copy of that latest source into a new staging destination. Record the private snapshot hash, and verify the authoritative source still has the same hash before and after import. If it changed, stop and repeat from a newly agreed snapshot; never mix versions.
4. Repeat independent field/order/recurrence comparison, canonical serializer reparse, production-store reopen and representative native app/sync checks. Review limitations and any differences with Lee.
5. Obtain final destination/cutover acceptance, then, with all participating apps closed and sync coordinated, perform the explicitly authorized replacement/reinitialization of test canonical CONTENTS at the same permanent path. Preserve the Syncthing folder/share configuration. Prevent stale test logs on other devices from being reintroduced: reset/reconcile each replica to the validated new manifest and log set before resuming apps; keep offline devices out until they are reconciled. Reinitialize private cache/writer/selection state as needed for the new data-space identity without syncing those private files. Verify the new canonical manifest/log set on every participating device, hand over the validated data, and clarify that Tandemlog becomes authoritative. Keep backups until Lee approves their disposition. Resume device use only after the coordinated handoff.

No current prerelease, formatting diff or rehearsal authorizes live import, source deletion, test-folder deletion, stable publication or cutover. Stable release gates still apply in addition to this migration checklist.

One-off Markdown rehearsal/import/export tooling and its dedicated tests live only in the private standalone package, pinned to application APIs. They are not shipped desktop utilities or maintained release features. Keep generic app domain/storage/recurrence regression coverage in app CI. Provide refreshed native desktop and Android feature demos after the owner receives formatting guidance; migration-tool work does not replace those demos.

## Published experimental RC4

[v0.1.0-rc.4](https://github.com/reddraggone9/tandemlog/releases/tag/v0.1.0-rc.4) uses exact accepted source `ded2eebc10eb1670658995cbc0c06b4676a5c583`, signed candidate 36906871648, Android code 24. Publication 36915456832 reused all 11 original assets without rebuilding after native API30 acceptance. Public downloads/signing/tag/checksums are verified; prerelease=true/latest=false. RC3 is preserved. [Verification](../../evidence/rc4-public-release-verification.json), [runtime limits](../runtime-qa.md) and [packaging prerequisites](../../packaging/README.md). Stable 0.1.0 and production cutover remain separate decisions.


## Published experimental RC7

[v0.1.0-rc.7](https://github.com/reddraggone9/tandemlog/releases/tag/v0.1.0-rc.7) uses exact accepted source `5d62b93f8154d71b9998683d9053e104dce16ae7`, candidate37009157582 and Android code32. Promotion37018242305 uploads three versioned installers with no rebuild after native API30 acceptance. Public bytes, signer, tag, prerelease/not-Latest behavior and compact notes are verified; RC6 remains unchanged. [Receipt](../../evidence/rc7-public-verification.json). Internal candidate diagnostics/checksums/install gates are retained. Stable publication and real-data cutover remain separately conditional.


## Published experimental RC9

[v0.1.0-rc.9](https://github.com/reddraggone9/tandemlog/releases/tag/v0.1.0-rc.9) uses exact accepted source `cf44c463ab632b6594f8114bdc0caee81feb2db2`, signed candidate 37087766510 and Android code 36. Promotion37091940925 reuses the three versioned installers without rebuilding after exact native API30 header/selection acceptance. Public bytes, signer, tag and exact notes verify; prerelease=true/latest=false, RC8 unchanged. [Receipt](../../evidence/rc9-public-verification.json). Protocol2/cache9 and core/storage/clock/schema/signing bytes are unchanged from RC8. Stable publication and real-data cutover remain separate.


## Published experimental 2026.10.0-rc.1

[v2026.10.0-rc.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.0-rc.1) uses accepted source `c3c1bd87dc3495de6158e1913e1f3e1f8bdb6f2e`, candidate37151096841 and Android code38. Promotion37163085342 reused the three installers without rebuilding after exact native API30 acceptance. Anonymous public downloads match accepted hashes/digests/sizes; official APK verification matches the owner certificate, package, code and nondebuggable flag. Tag and approved notes verify, prerelease=true/latest=false, and RC9 remains unchanged. [Receipt](../../evidence/calver-build38-public-verification.json). The exceptional v3 test-data format break is disclosed; old canonical folders are preserved and refused. Stable publication and real-data cutover remain separately authorized.


## First stable 2026.10.0 candidate

Lee explicitly accepted first stable publication on 2026-10-04. Build39 changes the accepted RC38 production closure only through `pubspec.yaml` display version/build metadata; package, owner signer, protocol3, cache13, hashes, event meanings and all `lib/` files stay unchanged. Freeze synthetic v3 compatibility bytes and expected projections before publishing. The full signed-candidate matrix and exact stable APK install/launch/retained-v3 checks must pass, then `stable.yml` promotes the same three installers as stable Latest without rebuilding. From this boundary future readers preserve durable v3 logs and meanings; no disposable data-reset promise applies. Live source/canonical data is untouched.


## Published first stable 2026.10.0

[2026.10.0](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.0) is stable Latest, prerelease=false/draft=false, from exact source `aacabf942122283731b5ea448a3800fe73ab63a2` and candidate37174502075/build39. Promotion37176968099 reused those three native-accepted installers without rebuilding. All anonymous public bytes/digests/sizes, APK owner signer/package/stable version/code39 and tag/approved notes verify; every previous RC remains unchanged. [Receipt](../../evidence/stable-2026.10.0-public-verification.json). Durable v3 backward readability now applies. No live reset, import or history rewrite accompanied publication.


A tested historical candidate can differ from main's workflow files after later
maintenance. GitHub Actions GITHUB_TOKEN cannot authorize that release creation.
Use the already-authorized workflow-capable connection to create a private draft;
pass its numeric ID to the preview workflow. All existing candidate gates still
run. The token only attaches three exact installers, rejects wrong/public/stable
drafts or unexpected/nonmatching assets, and never clobbers. The authorized
connection verifies source/digests before finalizing prerelease=true/latest=false.
No new credentials or repository permission/protection changes are implied.
See GitHub's [release API permission rule](https://docs.github.com/en/rest/releases/releases#create-a-release).


## Published stable2026.10.3/build56

[Stable2026.10.3](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.3) published2026-10-10T00:21:08Z as Latest with the Lee-authorized local storage migration and reviewed Android dependency maintenance. Candidate37995721678/source `76c5dd5cb7eedb09d2d4b62f737d429e1abab7d9` supplied the original three installers. [Promotion38008637367](https://github.com/reddraggone9/tandemlog/actions/runs/38008637367) used trusted dispatch `0ae5e66115e10f6a9c355086248ff01becddc423`, reviewed notes SHA256 `9e6bec8bd02baa9551bda43415b140e290f8da6d19ca3c7ef244533e2bec2e26`, and normal exact-artifact gates without rebuilding. No media was required for unchanged layout.

[Final evidence](../../evidence/stable-2026.10.3/README.md) records independent native/artifact and post-publication ACCEPT reviews, actual anonymous byte checks for the Android APK/Linux Flatpak/Windows installer, owner APK signing/package/version, source/tag/notes/Latest and all21 prior release identities unchanged. QA/debug/portable bundles were not published. Native coverage and its limits remain in the receipts; no live synced data was touched. Food and the minor icon seam remain deferred.


## Published experimental2026.10.4-rc.1/build60

[Food2026.10.4-rc.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.4-rc.1)
published as prerelease/not-Latest after exact affected Android build60 acceptance.
Candidate38085381679/source `3d671c20c6a1f6bdc2a2082f9a00e820c34b8050`
supplied the three installers. [Promotion38090188028](https://github.com/reddraggone9/tandemlog/actions/runs/38090188028)
used reviewed docs dispatch762df7737f047e578ac570a296a17d5ecd6728d4 and notes
SHA256 `3e54e578fe650c863f282e16119cb17ebff71f8017953427d74999a0abe6c5ae`,
retaining all exact-artifact/source/checksum/installed-lifecycle gates without
rebuilding. Public anonymous installer bytes match their accepted originals;
official public APK owner signer/package/version/code60 checks pass. All22 prior
release identities/assets/notes and tag refs remain unchanged; stable2026.10.3
stays Latest. [Public evidence](../../evidence/food-2026.10.4-rc.1/candidate/build60/publication/root-public-verification.json)
records exact identity, and the [native handoff](../food-native-acceptance.md) preserves
current60 acceptance and older59 editor/upgrade attribution. Private fixtures and
importer evidence remain separate; no live import or stable promotion occurred.


## Published experimental2026.10.4-rc.2/build64

[Food2026.10.4-rc.2](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.4-rc.2)
published2026-10-11T12:37:41Z as prerelease/not-Latest after exact build64 parent
Android acceptance and independent readiness/artifact/editorial review.
Candidate38133887765/source `71045e5021f9dee821bc24ea1c118158f029fd83`
supplied the exact three installers. [Promotion38139953180](https://github.com/reddraggone9/tandemlog/actions/runs/38139953180)
used reviewed docs dispatch `445f608d29c83a5dabd545e34887341cbeb09796` and notes
SHA256 `8608fcdba20b61f67ae9f9cd33b3c4da00c65c47af5fb34a7ae2011b6830fea8`.
Normal source/signer/version/closed-asset/checksum/installed-lifecycle gates passed
without rebuilding, a draft bridge or workflow changes.

[Publication evidence](../../evidence/food-2026.10.4-rc.2/candidate/build64/publication/README.md)
records actual anonymous three-installer checks, public APK owner signing/package/
version/code64/nondebuggable/ABIs, exact source/tag/notes and unchanged stable2026.10.3
Latest plus all23 prior release identities/assets/notes/tag refs. Native64 focused
calendar/SAF/cold-v2 passes and broader62 acceptance keep distinct source attribution.
The existing manual Windows GUI RC waiver and inherited Flutter/SQLite RELRO
qualification remain; no general16KB runtime/compliance claim is made. Private
fixtures remain separate; no live-data operation or stable promotion occurred.


## Published stable2026.10.4/build71

[Stable2026.10.4](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.4) published 2026-10-12T21:28:15Z as Latest after Lee accepted RC3 and explicitly authorized its full stable release with audited PR8/PR9, then the bounded Gradle mitigation. Exact source `b8cdfc3941cf171fb6e89bbd19c24e33729799bc`, signed candidate38299989871 and promotion38310766986 bind the original three installers. Reviewed notes SHA256 `03eac34a93d52555c76a072115a008d7fc6627ced55c5136fbc9f53e11257d0f` and docs dispatch `f9e1bdf719b8e5085273e6b329c69286a092e1e0` passed existing admission/source/signer/closed-assets/lifecycle gates without rebuilding.

[Final public evidence](../../evidence/stable-2026.10.4/publication/README.md) records actual anonymous byte verification, public APK signing/version/code71, source/tag/notes/Latest and all25 prior release/asset/tag identities unchanged. [Candidate acceptance](../../evidence/stable-2026.10.4/candidate71/README.md) preserves direct prepared stable56 and separate RC70 upgrades, affected native text/Food/SAF/Gboard checks and qualified reused coverage. Current runtime is Android11/API30; applicable manual Windows GUI waiver and inherited RELRO/16KB limits remain explicit. Private inventory/import/native packet remains external; no live Food cutover occurred.


## Published experimental2026.10.5-rc.2/build76

[Whole-container Food RC.2](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.5-rc.2) published2026-10-14T23:38:50Z from exact source `fe3f7ca36b50772abfaded7238a02f38d8fe9c73`. Candidate38645229999 and promotion38655311581 retain the original three native-accepted installers without rebuilding. Reviewed docs dispatch `067e4cae4159dd2b956f33c2edefb18f866b199d` supplied notes SHA-256 `9b85b60a0bb76375754443247a527090e29d233c5eb4d4cd71262b492f1f5195`; normal source/signer/closed-assets/checksum/installed-lifecycle gates passed. [Public receipts](../../evidence/prerelease-2026.10.5-rc.2/publication/README.md) verify anonymous exact bytes, public APK identity/ABIs, tag/notes, unchanged27 prior releases/assets/tag refs and stable2026.10.4 Latest. No private fixtures, production operation, dependency change or stable promotion accompanied publication.


## Published experimental2026.10.5-rc.3/build79

[RC3](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.5-rc.3) published2026-10-15T06:20:27Z from exact accepted source `f6407a0eb7f288fee7f7fb5f573227d442141f9c`. Signed candidate38682978068 and promotion38691768854 retain the original three native-accepted installers without rebuilding. Dispatch source also supplies independently reviewed notes SHA256 `74cf472bb38eb6b1c8e1774df605a87e10962bfde0a3200ad2c542dd582dcde0`; normal source/signer/closed-inventory/checksum/installed-lifecycle gates passed. [Public receipts](../../evidence/prerelease-2026.10.5-rc.3/publication/README.md) verify anonymous installer bytes, APK identity/native payload, exact tag/notes and unchanged28 prior releases/assets/tag refs. Stable2026.10.4 remains Latest. Recorded LinuxGTK/API30/WindowsGUI-waiver qualifications remain; no production operation, dependency change or stable promotion occurred.


## Published experimental2026.10.5-rc.4/build80

[RC.4](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.5-rc.4) published2026-10-15T15:59:08Z from exact accepted source `3118b6122a4c70e5db4e2e0c68822bbcf8e3e583`. Signed candidate38750707077 and promotion38765033863 reused the three original accepted installers without rebuilding after parent authorization and independent review. Reviewed notes SHA256 `bdecaa0f1571c706267f8b35688aca4132e0c7309acb7ce5393c222dfed0d324` and all existing source/signer/version/closed-assets/checksum/installed-lifecycle gates passed. [Public receipts](../../evidence/prerelease-2026.10.5-rc.4/publication/README.md) verify actual anonymous bytes, owner APK identity/native payload, exact tag/notes and unchanged29 prior releases/assets/tag refs. Stable2026.10.4 remains Latest. Qualified LinuxGTK/API30/WindowsGUI-waiver coverage remains explicit; no production operation, dependency change or stable promotion occurred.


## Published stable 2026.10.5/build 81

[Stable 2026.10.5](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.5) published 2026-10-15T19:19:31Z as Latest from exact source `bfb17ed71e0ed7953cc32c8f77a8907e7fdb337d` after Lee accepted RC.4 and explicitly authorized stable publication. Signed candidate 38782112182, push 38782103745 and [promotion 38792894635](https://github.com/reddraggone9/tandemlog/actions/runs/38792894635) passed every required job. Reviewed stable notes SHA-256 `9c3572ec2153cbbde6a8316b87092d1b078734522fe1371d40c8edd282477e0a` and all existing source/signer/version/closed-assets/checksum/installed-lifecycle gates passed without rebuilding. [Public receipts](../../evidence/stable-2026.10.5/publication/README.md) verify actual anonymous installer bytes, public APK owner identity/stable version/build 81/ABIs/native payload, stable metadata/notes/tag/Latest and unchanged 30 prior releases/assets/tag objects. Exact LinuxGTK and retained Android 80-to81 acceptance and preservation/replay completed with independent review before fresh-quota publication authorization. Existing Windows manual-GUI waiver, API 30 x86_64 and inherited native/16 KiB runtime limits remain explicit; no physical ARM/API 36 claim is made. No production operation, dependency change or Food wide side-pane work accompanied publication.


## Published experimental 2026.10.6-rc.1/build84

[RC.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.6-rc.1) published 2026-10-15T22:52:24Z from accepted source `09d631ce073a4fd42e42c9baafd2a79ac3364845` using signed candidate38806622314 and [promotion38819962767](https://github.com/reddraggone9/tandemlog/actions/runs/38819962767). Reviewed docs dispatch `5f3737b1a9c592058112ee30603b7dcdb715e1e5` supplied notes SHA-256 `89feef67da44d044bdb985443343afb47d1e34309764da91e0fc0b3c1293aa2e`. Existing source/signer/version/closed-assets/checksum/installed-lifecycle gates reused the three original installers without rebuilding. [Public receipts](../../evidence/prerelease-2026.10.6-rc.1/publication/README.md) verify actual anonymous bytes, owner APK identity/build84/native payload, exact reviewed notes/tag/source, prerelease/not-Latest status and all31 prior release/asset/tag identities unchanged. Parent authorization and independent final native/media/editorial/privacy review preceded publication; independent post-publication review accepts the public receipt. Stable2026.10.5/build81 remains Latest. Existing WindowsGUI/API30/simulated-wide and GTK-versus-hosted-Flatpak qualifications remain explicit. No production operation, dependency change or stable promotion occurred.


## Published stable 2026.10.6/build85

[Stable2026.10.6](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.6) published 2026-10-16T01:57:18Z and is Latest from accepted source `1a00c8de432407d4e58d7278ac90d62f1cdbace4`, candidate38825977292 and [promotion38837831145](https://github.com/reddraggone9/tandemlog/actions/runs/38837831145). Reviewed docs dispatch `6c8f19a7a62062cbce248112a5b4c2664d51ed3a` supplied unchanged notes SHA-256 `b9140813d5b64c75b15495711d1b8d83f302f7ca414e12790c68d0f915a67187`. Existing gates reused the three original installers without rebuilding. [Public receipts](../../evidence/stable-2026.10.6/publication/README.md) verify actual anonymous bytes, owner APK identity/build85/ABIs/native payload, reviewed notes/tag/source/Latest and all32 prior release/asset identities plus every prior tag ref unchanged. Fresh exact LinuxGTK and Android84-to85 acceptance, preservation/replay, demonstrations, independent final reviews and authorized fresh-quota publication completed. Existing WindowsGUI/API30/simulated-wide and manual GTK versus hosted Flatpak qualifications remain explicit. No production operation, dependency update or unrelated feature work accompanied publication.


## Published experimental2026.10.7-rc.1/build86

[RC.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.7-rc.1) published 2026-10-17T20:58:52Z from accepted source
`ad79bda0abc9ad5a72ec3dc92da29f1cb8f3c586`. Signed candidate 39061411870, push 39061383511 and
[promotion 39068954432](https://github.com/reddraggone9/tandemlog/actions/runs/39068954432)
passed every required job and reused the three original accepted installers without
rebuilding. Reviewed notes SHA256 `40f54dc02dcc7a9d1beddeb49ea32524c61f5b62441dae3cd0d67144ec8a59aa` match public copy.
[Public receipts](../../evidence/prerelease-2026.10.7-rc.1/publication/README.md) verify
actual anonymous bytes, public owner APK identity/build 86/native payload, source,
tag and all 33 prior releases/assets/tag refs preserved. Stable2026.10.6 stays Latest.
Exact LinuxGTK/Android85-to86 native acceptance, preservation/read-only replay,
visible-input demos and independent final/editorial review preceded fresh-quota
publication. Existing WindowsGUI-waiver/API30x86_64/manualGTK-versus-hostedFlatpak
qualifications remain. No stable promotion, production or dependency operation.

## Published experimental2026.10.7-rc.2/build91

[RC.2](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.7-rc.2)
published2026-10-18T14:49:25Z from accepted source
`7b4ffba164207f4a029e3fda2e37c3559b436d61`, signed candidate39125969801 and
[promotion39137679534](https://github.com/reddraggone9/tandemlog/actions/runs/39137679534).
Reviewed docs-only dispatchc5cd0c051231e5fbb21de1fb2034b1f89477ccad supplied notes
SHA256 `3c37114317dd5a4d2124f0df5f806be79b9da9065221f3a278a53af3e70baf1c`.
Normal source/signer/version/closed-assets/checksum/installed-lifecycle gates
reused the three original native-accepted installers without rebuilding.
[Public receipts](../../evidence/prerelease-2026.10.7-rc.2/publication/README.md)
verify anonymous bytes, official owner APK identity/build91/native payload,
exact notes/tag/source, prerelease/not-Latest and all34 prior releases/assets/tag
refs preserved. Stable2026.10.6 remains Latest. The accepted forward-only local
schema3-to4 upgrade prevents stable/build85 and RC.1/build86 reopening the same
upgraded profile; existing shared v3 stays v3. Qualified native/UI/media coverage
remains explicit. Production conversion, writer adoption and stable promotion
remain held; no dependency adoption accompanied publication.

## Published experimental2026.10.7-rc.3/build98

[RC.3](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.7-rc.3) published2026-10-20T19:59:59Z from exact accepted source `5358967e9c3c97dabd914acd5ca59fd5f15317c3`. Signed candidate39454347693 and [promotion39488138047](https://github.com/reddraggone9/tandemlog/actions/runs/39488138047) passed every required job and reused the original installers without rebuilding. Reviewed notes SHA256 `c418540e148b5e4840507be36c26754cff8d597575732d34b976158ee55bedf9` match public copy. [Acceptance and public receipts](../../evidence/prerelease-2026.10.7-rc.3/publication/README.md) verify anonymous original bytes, owner APK identity/build98, exact tag/source/notes and all35 prior releases/assets/tag refs unchanged. Lee explicitly authorized this RC; fresh quota cleared the standing threshold without override. Stable2026.10.6 remains Latest. Windows manual-GUI waiver, extracted GTK versus hosted Flatpak, API30/x86_64 and retained Android01 failed-cleanup/separate Android02 successful-replacement qualifications remain explicit. No production migration, stable promotion or unrelated dependency update occurred.


## Stable 2026.10.7/build101 preparation — 2026-10-27

Lee explicitly accepted RC.5 on2026-10-27 at09:31CDT and authorized the coordinated live unified cutover; the [stable candidate receipt](../../evidence/stable-2026.10.7/README.md) records his exact words. Build101 changes only pubspec display/build metadata from accepted RC.5. Known minor UX regressions remain in this accepted release; next-release fixes are excluded.

Publication/Latest remains held until the agreed offline window. Unified-only readers cannot open the old live canonical set, so Obtainium auto-update before conversion is unsafe. A prepared runbook alone does not make early Latest safe. After all candidate gates, stage the exact three installers **and original portable ZIP in a private draft before publishing**; RC.5 showed immutable releases reject later uploads. Preserve original candidate member-hash provenance locally; no rebuilding/repacking.

The existing stable workflow creates and immediately promotes a new release; unlike the preview workflow it has no draft attachment input. Do not dispatch it against a pre-existing draft or change it as a hidden addition to this version-only source. At the coordinated window, use the existing workflow-capable GitHub connection to validate the same candidate_source.py and publish_gate.py gates, verify the exact complete draft assets/notes/source, then finalize that draft as stable Latest without rebuilding. This is an explicit publication-method adaptation for immutable assets, not a gate waiver or permission to publish before the window. Record dispatch/API receipts and verify anonymous public bytes, Latest and every prior release/tag identity afterward. No repository/protection/signing changes are involved.

## Published experimental 2026.10.8-rc.1/build102 — 2026-10-27

Source `03ecab3` (main fast-forwarded from stable `ca76e2d`): review fixes plus the Food batch, date-picker fork, editor-centering, hint, peer-admission scaling and gate-rule changes. One enforcing reference qualification (request `9b29fa84`) passed after re-registering the reference host's text and SQLite libraries; one branch CI run (40618866978), one signed candidate (40624505011) and one prerelease publication (40630893094) all succeeded. Native Android acceptance upgraded a synthetic stable 2026.10.7 install in place on an API30 emulator. Publication used the immutable-release draft path: a private prerelease draft, the workflow's `draft_release_id` attachment of the three gated installers, then the original portable ZIP uploaded to the draft before finalizing as prerelease, not Latest. Anonymous bytes, tag and notes verified; prior releases unchanged.

## Published stable 2026.10.8/build103 — 2026-10-28

[Stable 2026.10.8](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.8) published 2026-10-28T07:34:03Z as Latest after Lee accepted RC.1. Source `6b8bb74` changes only release metadata from RC.1 (`03ecab3`): pubspec 2026.10.8+103, the Flatpak metainfo release entry, stable notes (RC.1 notes body unchanged) and README. Relevant-source identity v2 kept the existing qualification (request `9b29fa84`) valid, so no new reference run was needed; push CI 40643574069 and signed candidate 40643585573 each ran once and passed. Native acceptance upgraded a synthetic RC.1 Android install in place (API30 emulator) and a synthetic 2026.10.7 Flatpak install in an isolated GTK lab. Publication used the private-draft path: the three gated installers plus the original portable ZIP were attached and verified before the draft was finalized as Latest. Anonymous bytes, owner APK signer, tag, notes and note images verified; all 40 prior releases unchanged. [Record](../../evidence/stable-2026.10.8/README.md).

## Published experimental 2026.10.9-rc.1/build104 (Food products) — 2026-10-28

[RC.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.9-rc.1) published 2026-10-28 as prerelease, not Latest, from main `e346711`. It adds Food product records, so older installs stop with an update-required message until updated (one-release format change). Reference performance is **not qualified**: q4 and its single official rerun q5 failed timing maxima, and Lee accepted `634cd9c` for this prerelease only ([owner override](../performance-reference-qualification.md#release-owner-override--prerelease-2026109-rc1104-only)). After it, `e346711` adds only that override record and a `.gitattributes` fix for the frozen Food products fixture on Windows checkouts. Branch CI 40773989801 passed. Signed candidate 40776872517 passed on its second attempt: the first Windows unit job hit the 2-minute default timeout in `adaptive_text_read_test.dart` on a slow runner, and only failed jobs were rerun once. Publication 40784689794 attached the three gated installers to a private draft, and the original portable ZIP was added before finalizing. Native acceptance upgraded a synthetic stable 2026.10.8 Android install in place (API30 emulator), and the stable 2026.10.8 reader refused the workspace the RC wrote, without writing. Anonymous bytes, tag and notes verified; all 41 prior releases are unchanged.

## Published experimental 2026.10.9-rc.2/build105 — 2026-10-28

[RC.2](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.9-rc.2) published 2026-10-29T04:54:12Z (10-28 23:54 CDT), immutable prerelease/not-Latest, from exact source `bf266e6` (relevant source `4a34046`). Controlled-reference q3 `df710a4c` qualified with zero resamples/reruns; budgets are unchanged and RC.1's owner override does not apply. Original CI40814756221, signed candidate40817088690 and promotion40820223599 each passed on the first attempt. Both native Android in-place upgrades, stable103→105 and RC.1_104→105, passed on separate synthetic API30 AVDs with retained SAF grants, product minimum/Running low menu count+dot/view, cold reopen and append-only canonical history. A private draft held the three exact installers plus the original portable ZIP before finalization. Anonymous public bytes, tag/source and reviewed notes pass; stable2026.10.8 remains Latest and all42 prior releases/tags are unchanged. [Receipts and coverage limits](../../evidence/prerelease-2026.10.9-rc.2/README.md). No live data or physical owner-device install was performed.

## Published stable 2026.10.9/build106 — 2026-10-29

[Stable2026.10.9](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.9), release428147543, is immutable Latest, published 2026-10-29T16:54:16Z from `b6dbe70e2911ad34a6b7cb1c45b2f54e8cf1c8f4`. Lee accepted RC.2 at10:13CDT. Version/documentation-only promotion reuses qualified q3 `df710a4c` through identity v2 without an override or fresh reference run. Deterministic AppStream ordering on the first source was repaired by replacing same-base RC rows; corrected CI40904687047 passes. Candidate40904707689 passed attempt2 after its one diagnosed setup-flutter SDK-download infra retry (curl92), preserving all failed evidence. Exact original Android103/105→106 and GTK103→106 native upgrade acceptance passes. Three installers and portable ZIP were verified in draft before publication, with no rebuild. Anonymous public verification checks all4assets, owner APK signer, exact reviewed notes/tag/source/Latest and all43 previous releases/tags unchanged. [Receipts and platform limits](../../evidence/stable-2026.10.9/README.md). No owner-device installation/live operation.

## Published experimental 2026.10.10-rc.1/build107 — 2026-10-30

[RC.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.10-rc.1), release 428741281, published 2026-10-30T07:11:22Z, immutable prerelease/not-Latest, from `a61f6a9` (qualified source `e212575`, reference `50a8ca56`). Adds the agent CLI/MCP, Food row selection and Move some. Candidate 41009283931 passed on attempt 2 after one diagnosed slow-runner `rerun --failed`. Exact Android and GTK upgrades from stable 2026.10.9 passed on synthetic labs. Stable 2026.10.9 remains Latest. [Receipts and limits](../../evidence/prerelease-2026.10.10-rc.1/README.md).

## Published stable 2026.10.10/build108 — 2026-10-30

[Stable 2026.10.10](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.10), release 429395840, is immutable Latest, published 2026-10-30T19:10:10Z from `12b9f03b55915813345e8940c361ae58366ac02c`. Lee accepted RC.1 at 13:21 CDT. Version/documentation-only promotion reuses qualified reference `50a8ca56` / identity `12a2167c` without an override or fresh reference run. CI 41106541492 and candidate 41106539516 passed on attempt 1 with no reruns. Exact-asset Android 106→108, Android RC 107→108 and GTK 106→108 native upgrades pass on synthetic labs. Three installers and the portable ZIP were verified in draft before publication, with no rebuild. Anonymous public verification checks all 4 assets, the owner APK signer, exact reviewed notes/tag/source/Latest and all 45 previous releases/tags unchanged. [Receipts and platform limits](../../evidence/stable-2026.10.10/README.md). No owner-device installation/live operation.

## Published experimental 2026.10.11-rc.1/build109 — 2026-10-31

[RC.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.11-rc.1), release 430241634, published 2026-10-31T23:12:13Z, immutable prerelease/not-Latest, from `cea8576` (relevant source `59c446d5`, q6 `eaab6c53`, first qualification under `single-sample-confirm-v1`), notes from `498f6f0`. Adds the Activity log and fixes Food recovery notices, Move some with large text, repeating-task selection, pinned Food controls and full-width sticky headings. CI 41245345912 and signed candidate 41245367111 passed on the first attempt. Exact Flatpak and APK upgraded retained synthetic 108 labs in place with log prefixes, identity and Android folder grant preserved; acceptance covered Activity read-only and live cross-writer refresh, Move some with a real IME at 200%, selected repeating completion, bulk edit and its Undo on GTK, cold reopen and integrity. Windows has installer and portable inventory checks only, with no GUI run here. Known and deferred: a wide bulk editor keeps a stale count after completing one of its selected tasks; Save refuses without writing and the next selection gesture recovers. Stable 2026.10.10 stays Latest.

## Published stable 2026.10.11/build110 — 2026-11-02

[Stable 2026.10.11](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.11), release 432283432, is immutable Latest, published 2026-11-03T04:38:18Z from `d52a81d47ff1b0400526eb9ce5bc03d1b795527e`. Lee accepted RC.1 at 22:00 CST on 2026-11-02. Version/documentation-only promotion reuses qualified reference q6 `eaab6c53` / identity `59c446d5` without an override or fresh reference run. Signed candidate 41575738097 passed on attempt 1. Automatic push CI 41575733635 failed only `verify_linux_disposal.py` with the known intermittent Linux quit-time abort (`FlutterEngineRemoveView` kInvalidArguments, `g_mutex_clear`); the candidate's Linux job on the same source passed, and it was not rerun. Exact-asset Android and GTK RC 109→110 in-place upgrades pass on the retained synthetic labs. Three installers and the portable ZIP were verified in draft before publication, with no rebuild. Anonymous public verification checks all 4 assets, the owner APK signer, exact notes/tag/source/Latest and all 47 previous releases/tags unchanged. [Receipts and platform limits](../../evidence/stable-2026.10.11/README.md).

## Published experimental 2026.11.0-rc.1/build112 — 2026-11-03

[RC.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.11.0-rc.1), release 432661901, published 2026-11-03T12:23:54Z, immutable prerelease/not-Latest, from `760d97a` (relevant source `a579f229`, q12 `9d82e5c2`), notes from `22ce132`, media `9b067d5`. Redesigns the Activity log (values and what changed, day headings, details titled by the change with Open), fixes planned agent commits colliding in the text cache, and shows why Save is disabled when a bulk selection changes. CI 41630081645 and signed candidate 41630089106 passed. Earlier candidates were not published: 41585684689 (evidence logs dropped by `.gitignore`), 41607232219/build111 (Activity named captured tasks twice), 41614823156 (format gate) and 41617981312 (bulk stale notice scrolled out of view). Exact APK upgraded the retained synthetic Android lab 111→112 in place (110→111 covered the stable path) and exact Flatpak upgraded the retained GTK lab 110→112, with log prefixes, identity and Android folder grant preserved; acceptance covered Activity headings, values, details and Open, one completion, cold reopen and integrity. Windows has installer and portable inventory checks only, with no GUI run here. Stable 2026.10.11 stays Latest.

## Published stable 2026.11.0/build113 — 2026-11-03

[Stable 2026.11.0](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.11.0), release 432735389, is immutable Latest, published 2026-11-03T13:29:56Z from `b363a13fadca08b72eb020ee0abc0a29a84563d8`. Lee accepted RC.1 at 06:51 CST on 2026-11-03. Version/documentation-only promotion reuses qualified reference q12 `9d82e5c2` / identity `a579f229` without an override or fresh reference run. Signed candidate 41639486016 and automatic push CI 41639469591 passed on attempt 1 with no reruns. Exact-asset Android and GTK RC 112→113 in-place upgrades pass on the retained synthetic labs. Three installers and the portable ZIP were verified in draft before publication, with no rebuild. Anonymous public verification checks all 4 assets, the owner APK signer, exact notes and images/tag/source/Latest and all 49 previous releases/tags unchanged. [Receipts and platform limits](../../evidence/stable-2026.11.0/README.md).

## Update channels — dropped (Lee 2026-11-03)

Publish-time installs already reach every household device, so the signed
Flatpak Pages repository, Scoop/winget channel and post-stable device rollout
were dropped. Their unused tooling (`flatpak_channel.py`, `update_channels.py`,
`household_update_policy.py`, the Advance stable update channels workflow and
the build's signing options) was removed; it never ran and no key was created.

## Stable 2026.11.1/build116 published — 2026-11-07

[Stable2026.11.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.11.1) is immutable Latest, published15:53 CST from `ef71b880`. Lee accepted RC115 on his phone at15:19 CST. Version/docs-only promotion reuses sealed q16 after identity verification, without a new benchmark or override. Signed candidate42415487006 and CI42415472687 passed first attempt. Exact Android and GTK115→116 retained-lab upgrades, independent reviews and four-asset anonymous public verification pass; all51 prior releases/tags unchanged. [Receipts and platform qualifications](../../evidence/stable-2026.11.1/README.md).
