# RC4 main signed candidate: acceptance handoff

Main now contains `77a5f2dfde4ea914e7f2cf09dcbf77ee738056cc`, version
`2026.10.2-rc.4+46`. Parent authorized main integration and main-only signed
preparation at 2026-10-08 17:30 UTC after accepting the isolated Android
historical-recompletion regression. Final signed-package acceptance and publication
remain pending; stable feature promotion still requires Lee's approval.

## Source and review binding

Main accepted a normal non-force push on 2026-10-08. The linear commit has exactly
one parent, `0a16a88355823d74c98246ed55f1ce85e45428ab`, and tree
`94426a94d81559b2409a3efe108618174ae45f23`, byte-identical to reviewed integration
`56213cc5d781bc2e7ee96b6ba7d4f37f232d3b1b`. The merge-based integration remains
preserved separately; GitHub rejected its main push under existing linear-history
protection. Protection was not changed. Executable, test, native, platform,
workflow, dependency and version inputs remain exact frozen candidate
`e205e650b5614935a73cf5acb96ca9b36fda8e4e`.

Independent final correctness review accepted this entire-tree identity and
published-preview range `5ac35da50acca69ab196a54312efc8ccef1452da` → `77a5f2d`.
The accepted notes/media are unchanged: six user-facing changes and the actual
dark native Before/After tag image pinned to media commit `89cec5a1`, PNG SHA256
`8a635aecffc81584d3153d77fbb0c8480a10b805df19ebf7b966e464179e3a90`.
No later source change requires an additional behavior bullet or image.

Fresh main/stable/preview refs and absent RC4 tag were verified before pushing.
Published and successful signed-candidate build floors were both 45; source-bound
preflight and candidate-history checks passed for build46. Stable remains
`v2026.10.1` at `da4859ea82f8b066ed701740c57cb9bcff1083ff`; published preview
remains `v2026.10.2-rc.3` at `5ac35da50acca69ab196a54312efc8ccef1452da`.

## Parent-owned isolated regression acceptance

Parent reports the installed debug APK from source
`d73662ab8479aa8076ee04a5ed5badd1542e585d`, CI37804634954,
artifact11561899292, SHA256
`5e35400713e614c74730713c060e65bb3edea2d409df1cb57e7f6de94bf87a1c` passed:
original pre-leak A16 historical recompletion, Undo, cold replay before Undo,
duplicate delivery, legacy scalar history, retained grandchild, offline recurrence,
and later-parent/successor edits. The local isolated lab stopped cleanly without
new OOM/swap. Reported acceptance packet SHA256 is
`49ce66ebb848508cae7f96e07a938c3bd1cfb82533977f0c153bcb5ddc01fefc`.
The cloud consumer did not materialize that packet; this is explicitly attributed
parent acceptance. It closes the isolated regression gate, not final composed
signed-package acceptance.

## Exact-source candidate runs

- [Main CI37819186249](https://github.com/reddraggone9/tandemlog/actions/runs/37819186249)
  checks exact main `77a5f2d`.
- [Main-only signed candidate37819214432](https://github.com/reddraggone9/tandemlog/actions/runs/37819214432)
  checks and prepares release artifacts from exact main `77a5f2d`.

Both completed successfully on exact source77. The signed candidate completed
2026-10-08 18:13 UTC; all five jobs passed. Its Linux checks report 628 unit and
70 actual native app flows; Windows 626 unit plus two expected Linux-only skips;
each desktop 4 Cargo, 107 native worker and 37 tooling cases. Packaging, packaged
native/notices and desktop installed-lifecycle gates passed. Owner job113464059496
verified the pinned certificate, package/version/code, non-debuggable flag and
all three universal ABIs, then verified packaged native payloads/notices. The
[qualified receipt](../evidence/rc4-signed-candidate/receipt.json) retains public
API metadata and exact decoded job-log hashes. No signing secrets are included.

| Artifact from signed run37819214432 | ID | Outer ZIP bytes | Outer ZIP SHA256 |
| --- | --- | --- | --- |
| `android-release`, owner-signed package | `11569174876` | `30300888` | `08d2f8c157f27140aef448d5d33b1492b85b606f7d53a91caf39f16c42d7b58a` |
| `windows`, release setup and portable QA | `11568777570` | `25760961` | `24fd648350c1a38aca93f1e37e362d604a4fb5ebda63f4ab6fb0efb7c346bdd0` |
| `linux`, release Flatpak and installation receipts | `11568853640` | `9004286` | `2a182f33fa184781510b214b935b489320f42c02d128962cf9df72c9cdfa194d` |

These ZIP digests are matching GitHub artifact metadata/completed runner output,
not consumer rehashes. The separately named `android` artifact11568054116 is a
debug package and must not be selected as the owner-signed release. The three
release artifacts expire on Oct13 at their respective creation times.

Hosted Windows setup SHA256 is
`3c12d59c4c269002c246fd39cbb2a222c15f115e9c75aed82fb8b1a12608ab3f`;
portable ZIP is `823fd2b5b03ea0c016d80cfc8785101da37a655fb4fe4390627e0b5ac8c9d31c`,
EXE `b670e44ef9884c193a63a0e2df717413cd60367a7371158e73a0c3437ebb25c8`,
native DLL `19d2028a338464d7b1e306f5f31fada1c5b3ddd55c6aed0ac370ba102de64abe`.
Consumer Windows and owner-Android preparation succeeded, but supported local
materialization returned403. No local archive/member/APK/signature verification
is claimed. The existing signing workflow stores the APK hash inside
`android-SHA256SUMS.txt` and `android-release-metadata.json`, without printing it;
this consumer cannot supply that inner hash. The local executor must verify those
exact files, actual APK hash and owner signature before installation/acceptance.

An unintended earlier dispatch37818335528 used old main `0a16a88` because the
operator dispatched before checking the rejected merge push. It completed with
failed preflight; checks and signed-android were skipped. It produced no signed
candidate. The replacement push succeeded and its remote SHA was verified before
the valid candidate dispatch.

## Reviewed publication inventory correction

Windows retains three portable QA files alongside its three required installer
files. The earlier strict eleven-file combined inventory rejected that fourteen-file
candidate even though public staging selects only three installers. Independent
architecture review confirmed this mismatch. Reviewed policy revision
`3111dd94510a8f77e6978aa177e8d9b44fd7607c` was integrated with a normal main push:
every original eleven asset and gate remains required, and only the complete
three-file QA set is additionally allowed after source/archive/checksum/member
validation. Partial/unknown extras and unsafe archive entries still fail. QA stays
engineering-side; public assets remain one installer per platform plus automatic
GitHub source archives. Notes/media bytes are unchanged.

Thirteen focused and fifty tooling tests pass; baseline behavioral reds and
independent correctness/security/architecture reviews are retained in
[policy evidence](https://github.com/reddraggone9/tandemlog/blob/3111dd94510a8f77e6978aa177e8d9b44fd7607c/evidence/publish-portable-qa/README.md).
[Normal policy CI37822643601](https://github.com/reddraggone9/tandemlog/actions/runs/37822643601)
is still running. This source advances main's trusted dispatch policy only:
application, native, dependency, producer, workflow and notes/media inputs are
unchanged. Select successful signed run37819214432/source77 for acceptance and
publication; do not replace it with a later debug artifact. The existing trusted
dispatch-policy route consumes those exact built artifacts without a rebuild.
Final native acceptance, completed dispatch-policy CI and fresh quota still gate
publication. No new signing or release dispatch accompanied this policy push.

## Final native and promotion gates

Use only independently isolated synthetic test profiles. Preserve failed original
and pre-leak evidence; the retention fix prevents new incorrect proofs and does
not repair already-appended leaking canonical history. All participating preview
peers must use the updated reader. Never truncate/rewrite canonical records or
touch live synced user data.

1. Verify each actual outer archive and inner APK/Windows payload against its own
   receipt. Verify Android owner certificate
   `0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d`,
   package `com.reddraggone9.tandemlog`, version `2026.10.2-rc.4`, code46,
   non-debuggable state, all packaged native ABIs and notices. Do not assume a
   debug-to-owner-signed in-place update.
2. Accept the exact installed owner-signed APK: historical recompletion/Undo/cold
   replay/convergence and stable-v3 readability, shared text and checklist
   recurrence, real IME/chips/suggestions/pending-query decisions in editor,
   bulk Add/Remove and Filter, SAF picker/grant/reopen/refresh and lifecycle/runtime
   FFI. Retain the approved 6GiB/2CPU/one-AVD lab and parent storage restrictions.
3. Accept the exact installed Windows release payload with manual visual,
   keyboard, assistive-technology and affected-flow checks. Earlier hosted debug
   execution is supporting evidence. Complete the distinct task-based UX audit
   across required desktop/narrow, themes/larger text and actual Android behavior;
   qualify any reused unchanged-input evidence.
4. Obtain a fresh parent quota read before publication. Last supported read was
   67% weekly remaining at 2026-10-08 17:30:04 UTC, reset Oct14 10:33:41 UTC;
   it authorizes current preparation, not the later fresh publication gate.
5. After every gate passes, publish the authorized experimental preview from the
   reviewed dispatch source with expected tag `v2026.10.2-rc.4`, successful signed
   run ID and actual accepted APK SHA256. Consume accepted artifacts without a
   rebuild, prerelease=true/latest=false. Five-day artifact expiry requires a
   fresh build and exact native reacceptance. No stable promotion is authorized.
