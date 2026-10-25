# Morning engineering review — 2026-10-25

Product remains **034a57dbc7092e242889d23d12e22091fed08b0c** on
`fix/rc4-task-latency-20261022`. Subsequent commits are documentation/evidence.
Cloud remains sole product writer until explicit handoff or the hard stop-write
cutoff **2026-10-26 13:00UTC**. No release,live operation or policy change.

## Ready development checkpoint

- Linux detached window/view/engine lifetime defect is fixed with same-thread,
  bounded normal-exit disposal. Exact CI40167598688 passes platform jobs,
  1515units,174tools,203Linux native workflows,original close and deterministic
  disposal. Original SIGSEGV and negative/intermediate proofs remain retained;
  this is not a universal graphics-crash elimination claim.
- The narrow UTF8 size-guard repair retains frozen bytes,caller errors and
  malformed-Unicode behavior. Current APK and native payload are source-pinned.
- Parent supplies **three fixed Farnsworth current-source AOT observations**,
  each0absolute/paired median/max misses,all118source/5390compiled inventory,
  fixture/correctness/sample/package checks passed,no retry/replacement.
  Terminal cleanup07:59:11UTC. [Supplied reference receipt](reference-034a57d-final-supplied.json).
- Parent now supplies **current034a57d wide Android emulator acceptance**:
  genuine dirty-editor toolbarUndo→Cancel preserves draft/re-enables Undo;
  refocusing permits continued typing; Undo→Discard adds exactly1matching
  compensation. Empty-title rejection/correctionSaveUndo,Task/Food emojiSaveUndo
  and cold reopen pass. **14independent replays**,full baseline restoration,
  unchanged canonical prefixes and exact compensation targets reported passed.
  Cleanup08:56:42UTC,before09:15:48deadline;both units inactive/MainPID0,emulator/
  ownedADBports absent. [Supplied Android receipt](android-034a57d-final-supplied.json).

The Farnsworth/Android raw local artifacts were not accessed by cloud. These are
qualified parent/local-executor reports,not claims of independent raw inspection.
The Android artifact's archive/APK/checksum/static byte checks were independently
performed in cloud: [exact artifact receipt](android-artifact-034a57d.json).

## Cancel focus review

Observed qualification: **Cancel did not automatically restore text-input focus**.
The draft survived; explicitly tapping the field allowed further input. Do not
claim automatic focus,caret/composition restoration or zero-extra-tap continuity.

Read-only Git comparison proves the relevant app,editor,unsaved-dialog and tests
are byte-identical from e23 to034a57d. `_undoLatest` requests guarded editor close;
Cancel returns false,leaves the editor/session mounted,and `_closeEditor` clears
`closingEditor`/re-enables Undo. `askUnsavedDraft` uses Flutter's normal dialog
route; there is no app requestFocus of the previously edited field on Cancel.
The reviewed Flutter SDK requests the modal route's focus and later the current
route scope,not a guaranteed specific input. Supplied evidence does not establish
which node receives final focus or the exact platform event sequence.

The existing native regression asserts retained draft text and re-enabled Undo,
not automatic text focus after this guard. ADR0026's explicit prior-input focus
restoration belongs to **field Help**,whose separate implementation remembers the
last attached field; it must not be generalized into a new Cancel requirement.
Rejected-Save focus guarantees and refresh/reorder focus preservation are also
separate existing contracts and are not waived by this review.

**Recommendation: preserve the observation; no product patch now.** This is
consistent with an existing dialog-focus handoff and is not a demonstrated new
regression. No before/after Android baseline proves a change. Automatic return to
the prior field could be evaluated later as a small usability improvement if Lee
wants it,with route ownership,newer user focus,keyboard/accessibility and native
text-session tests; silently forcing text focus now could steal deliberate focus.
No new focus requirement or intentional-design acceptance is invented here.

## Performance-gate recommendation for Lee

The hosted enforcing job **still fails5absolute maxima and3paired metrics**,
including Food confirmedSave paired median9.984ms versus9.3125ms. All correctness
checks pass. The prior hosted run's179/105failures used the **same AOT executable,
source/dependencies,fixtures,limits and caps** as this5/3run; CPU/environment differ.
Three current-source local0/0results reinforce environment dependence and do not
reproduce the hosted median miss. They do not isolate virtualization,storage,
scheduling or GC as the cause and do not establish a code speedup.

Keep the current hosted result red and all existing budgets/retry rules intact.
Do not launch another unchanged hosted run hoping for green or write speculative
micro-optimizations solely to absorb platform tails. The scoped development
repairs can remain a tested,source-pinned handoff checkpoint without publication.

For a **future explicit gate-placement decision**, recommend a documented reference
environment with reviewed CPU/kernel/filesystem,unchanged actual6GiB/2CPU/no-swap/
128pids bounds,controlled competing load,finite genuine-pressure supervision and
complete immutable source/tool/artifact/fixture bindings. Evaluate all actions,
first-use/history-growth cases and every failure using the same thresholds; retain
hosted measurements as cross-environment regression evidence. Manual ephemeral
execution through the existing lab route is possible; a persistent runner or new
service/security policy is not part of this recommendation. Any formal change
to which result grants acceptance needs a separate approved policy/implementation
review; the present diagnostic passes **do not make that change**. No limit
loosening is proposed.

## Remaining acceptance and reservations

| Item | Current state / next authorized boundary |
| --- | --- |
| Development correctness/platform/native Linux | Passed at034a57d;retain original exact CI and source/artifact receipts. |
| Current-source reference AOT | Three planned local observations reported0/0;complete,not enforcing-gate substitution. |
| Focused current-source Android | Wide emulator delta and genuine toolbarUndo guard reported passed;14replays. Previous wide-guard reachability gap is closed for this layout. |
| Cancel input focus | Not automatically restored;manual refocus works. Recorded usability observation,no demonstrated new regression or patch. |
| Hosted enforcing performance | **Failed**,unchanged limits. Gate-placement recommendation awaits separate decision;no retry/policy change performed. |
| Native visible responsiveness | Full-action input-to-visible/presentation,first-use and history-growth acceptance remains open. Prior Windows32/61/58ms was framework-postframe-only,not all-action acceptance. Software-rendered/emulator/ADB/framework/hardware endpoints stay distinct. No new Leela foreground permission. |
| Broader device/candidate checks | Focused debug-emulator continuity does not establish physical-device,owner-signed exact candidate or all platform/layout/provider coverage. Retain existing source-specific evidence;run only applicable future candidate gaps under their authorizations. |
| Failure/recovery guarantees | Empty-title rejection is form validation,not backend failed-Save durability proof. Rejected-Save continued typing,peer-change/selectiveUndo and owned-tail cleanup guarantees remain unchanged and retain their existing tests/evidence. |
| Release/live adoption | Held. Future exact candidate/editorial/native gates,physical-writer mapping,fresh frozen real-copy conversion/replay and explicit adoption/publication boundaries remain prerequisites. No signing change or live work. |
| Ownership | Cloud sole writer until coordinated cutover;stop writes byOct26 13:00UTC. Local executor has stopped its owned lab units;no overlapping editor. |

No new benchmark,CI,device operation or product edit was performed for this review.
No further product repair is justified by the supplied pass results alone.
