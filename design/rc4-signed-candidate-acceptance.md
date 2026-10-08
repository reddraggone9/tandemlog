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

Both were running when this handoff was prepared. Artifact identities, host output,
consumer byte verification and final acceptance will be recorded in the accompanying
receipt only after the corresponding evidence exists. The established workflow
requires its full matrix before owner signing and verifies the non-debuggable APK,
public owner certificate pin, package/version/code, native payloads and notices.
No keys or secret values are part of this handoff.

An unintended earlier dispatch37818335528 used old main `0a16a88` because the
operator dispatched before checking the rejected merge push. It completed with
failed preflight; checks and signed-android were skipped. It produced no signed
candidate. The replacement push succeeded and its remote SHA was verified before
the valid candidate dispatch.

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
