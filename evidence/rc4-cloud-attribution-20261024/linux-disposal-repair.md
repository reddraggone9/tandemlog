# Accepted-exit window and engine disposal

Parent authorized this continuation of the existing Linux close-crash repair.
No feature, rendering-backend substitution, forced process exit, SDK/dependency,
security, signing, persistence or performance-budget change.

## Evidence before changing ownership

The actual full-CI SIGSEGV and [sanitized stack](utf8-size-guards-linux-close-stack.txt)
remain retained: LLVM/Gallium compilation was active while the main thread ran
process-exit handlers. That located the failure without proving root ownership.
The pinned Flutter platform consumes WM_DELETE, asks Dart to exit, detaches its
application windows and quits. Its view/engine disposal paths perform the actual
engine shutdown, but the runner did not destroy those detached windows.

A weak-notification/destroy-signal observer on the exact retained failing bundle
found window, view and engine all alive when the application loop returned.
The process closed cleanly locally; this is a deterministic lifetime defect,
not a new SIGSEGV reproduction or clearance. The bundle bytes stayed unchanged.
[Original negative proof](linux-disposal-original-proof.json).

Window destruction alone finalized the window/view but left the engine alive.
That unsuccessful intermediate result is [retained](linux-disposal-window-only-negative.json).
Its binary was not separately archived before rebuilding; no binary attestation
is claimed for that intermediate prototype.

Further bounded task tracing found an incomplete default-context GTask created
by `fl_engine_remove_view`. The pinned SDK rejects removal of the implicit view,
but its GTask still queues completion and retains the engine. One diagnostic
context dispatch did not suffice; four already-ready dispatches released the
observed task and finalized the engine. No sleep or new-work wait was involved.
Other context work was still pending after the engine disappeared.

## Minimal ownership repair

The runner records weak window/engine references for each window it creates.
Only accepted GApplication shutdown destroys surviving windows. Canceled Dart
exit never enters that callback; existing draft, Save, queue and native-owner
shutdown decisions remain in Dart and run first.

After destruction, the same GTK thread dispatches already-ready completions only
while tracked engines remain alive. It does not wait for new events or drain
unrelated work after engines are gone. A 256-dispatch operational cap prevents
a continuously-ready source from making that loop unbounded; it changes no
existing responsiveness, normal-close, retry or release limit. Remaining live
engines cause a warning and unsuccessful process exit, never a clean-close
witness. No `exit`, `_exit`, termination signal or graphics override is added.
Weak references prevent this tracking from retaining its own objects.

## Regression and native proof

[Current-source validation](linux-disposal-validation.json):

- All 1,515 unit tests pass, including concurrent held-work shutdown, canceled
  dirty-draft exit followed by Save, cleanup-error transparency, cache sealing,
  and reopened-cache proof. Analysis passes; 399 Dart files need no formatting.
  All 174 tooling tests pass; native release build passes.
- The original **uninstrumented** immediate-normal-close harness passes fresh and
  verified warm-cache launches. No forced cleanup is a successful result.
- The additional deterministic gate observes real weak finalization of window,
  view and engine on the owning GTK thread before the application loop returns.
  Fresh and verified warm-cache launches both pass; bundle bytes stay unchanged.
  Its validator rejects retained original/window-only negatives, missing/late/
  duplicate/foreign-thread observations and false completion fields.
- An additional [renderer-child observation](linux-disposal-renderer-probe.log.txt)
  confirms the renderer is destroyed/finalized before loop return too. It needed
  no further product change or private native-structure access.

The original CI smoke check remains unchanged. A separate bounded native disposal
step is added afterward; its observer is QA-only and never linked into the app.
Its source is `tool/linux_lifecycle_probe.c`; `tool/verify_linux_disposal.py`
creates its own synthetic fixture, observes two normal launches, verifies real
cache reuse and retained bundle pins, and retains failure diagnostics. Raw SQL,
request payloads and personal data are not observed.

The pinned SDK logs an implicit-view removal rejection and three messenger
handler warnings during teardown. These messages are retained in the
[fresh](linux-disposal-final-fresh.log.txt) and [warm](linux-disposal-final-warm.log.txt)
logs; no handler or test policy suppresses them. Exact messenger-callback
attribution is unresolved. The ownership proof is not a claim of warning-free
SDK shutdown, hardware presentation latency or universal crash clearance.

Fresh exact-source CI remains required before claiming its original hosted
normal-close/native gates pass. The previous SIGSEGV, all enforcing performance
failures and their exact commits remain in the handoff. Local software-rendered
proofs and the separately supplied older-e23 Android trial establish neither
latest-source Windows/Android acceptance nor a release/cutover decision.


## Follow-up warning attribution

A separate single-launch [warning-origin control](linux-disposal-warning-origin.json)
kept the original warnings visible and captured only native return addresses,
not arguments or raw memory. Symbol mapping and the pinned generated sources
identify two emissions in `ful_url_launcher_api_clear_method_handlers` during
URL-launcher disposal and one in `ffs_file_selector_api_clear_method_handlers`
during file-selector disposal. Those helpers construct basic channels and then
clear their handlers after the messenger's engine link has gone. The earlier
method-channel annotation reports unknown because these are basic-channel calls.
[Original warning/backtrace log](linux-disposal-warning-origin.log.txt) is retained.
No plugin, SDK, log policy or product source was changed for this diagnostic;
this explains the local warning emission path without assigning the original
LLVM SIGSEGV to those plugins or claiming warning-free native shutdown.


## Hosted exact-source checkpoint

[Verified hosted artifacts](linux-disposal-hosted-checks.json) now record original
uninstrumented fresh/warm normal exits 0/0, verified warm proof reuse and zero
cores. The separate deterministic gate also passes both launches, finalizing all
three objects on the owning thread before loop return. Both checks share all 18
bundle pins; four QA source pins match. This verifies the lifetime correction on
the original hosted execution path, while broader native workflows and required
performance results remain pending. Historical SIGSEGV evidence is retained, not
replaced by a universal crash-elimination claim or a hardware latency claim.
