# Durable Food implementation checkpoint

Unreleased work on `feature/food-inventory-implementation`, based on stable
2026.10.3/main `530b458845288856ffa3bc91a671e7bc9a43ff12` and the historical
synthetic slice `a47015d799f575616f5b80222d8435dd351836b1`. This is source and
synthetic Linux evidence, not a distributable candidate or platform acceptance.
The existing pubspec version remains 2026.10.3+56; it must not be used to publish
Food as the already released version.

Food has separate bounded canonical streams, exact protected append receipts,
an additive schema3 upgrade on the existing profile owner, and production
Tasks/Food navigation. Released task v3 records and the native text engine are
unchanged. See [ADR0014](../../design/decisions/0014-food-inventory.md) for the
accepted scope and storage/recovery boundaries.

## Density and actual pixels

All images show synthetic data in a native Linux GTK debug window. Viewports are
390×850 and 1200×850, device-pixel ratio1. Neither a narrow Linux window nor
scripted Flutter taps are Android or human touch acceptance.

| Same 12-container fixture, normal text | Before | After |
| --- | ---: | ---: |
| Row including margin |112px|64px|
| Fully visible groups at390×850 |5|10|
| Fully visible groups at1200×850 |6|10|
| Measured icon action target |40px|48px|

No text size was reduced. Name and quantity share a line; expiry and brand share
the next. Inspect reveals size, location, physical identities and secondary
actions. The density/discovery tradeoff remains provisional pending Lee's
feedback. Both themes and200% text grow without overlap: narrow enlarged rows
are136px with3 complete groups; wide enlarged rows are104px with5 groups.

| Matched native dark images | Before | After |
| --- | --- | --- |
| Narrow |[Before](density-before/density-dark-1x-390.png)|[After](density-checkpoint-final/density-dark-1x-390.png)|
| Wide |[Before](density-before/density-dark-1x-1200.png)|[After](density-checkpoint-final/density-dark-1x-1200.png)|

[Before measurements](density-before/density-measurements.json) and
[final after measurements](density-checkpoint-final/density-measurements.json) include viewport
heights and actual rendered row heights. The native harness uses the same names,
dates, brands, nominal sizes, locations, physical IDs, fonts and content for both
runs. The previous renderer is preserved as text in
[density-before-source](density-before-source/); it is a pre-density uncommitted
renderer snapshot, not falsely attributed to a released commit. Its callback
capture was restored before execution so the earlier negative control does not
change behavior. The actual executed native harness is preserved separately
from its initial out-of-tree unit-mode attempt. Warm-up/Test-starting frames are
excluded from deliverables.

The [scripted native Linux demo](preview-accepted/native-linux-scripted-preview.mp4)
is14.133333 seconds,1200×850,H.264/15fps. Independent review verified a visible
native cursor. It exercises inspection, selected partial-container deletion,
Deleted/Restore, retained sections, Inbox and the editor. These preview actions
are process-local synthetic operations, not a persistence demo. The separate
[production narrow](production-recovery-final/production-narrow-stock.png) and
[production wide](production-recovery-final/production-wide-stock.png) captures come
from the final durable production-host Add/remove/restart/Restore workflow.
The [enlarged recovery screen](production-recovery-final/production-narrow-shared-recovery-2x.png)
shows the guarded Retry at390×800 and200% text; private draft/controller identity
and unchanged canonical bytes are verified by the native test before admission.
The separate scripted native Inspect check passes1/1 across both viewports and
normal/enlarged text: actual Tab/Shift+Tab and Enter reach Inspect, actions and
details; Escape and dispatched Back close menu/editor; complete container JSON
remains unchanged. [Final Inspect frames](inspect-keyboard-final/) bind renderer
3b1555c7, the same shared presentation used by the production host. The five
production workflows and87 Tasks flows bind pre-copy renderer8219fa; precisely
three singular/plural label changes separate it from3b, with the complete
[copy-only diff](tandemlog-food-renderer-singular-copy.diff) preserved. The early
density commit intentionally contains evidence only, not the new host code.
At narrow200% editor text, platform ellipsis shortens ancillary optional/date
format suffixes and a helper tail. Core labels/values and actions stay readable
and reachable; independent UX review qualifies this remaining large-label limit.
This is inspected-group keyboard access, not full-list wraparound or assistive
technology acceptance. The successful Inspect fixture is preserved independently;
its final source changes only a diagnostic getter to remove a deprecation, with
an exact reversal proof in [fixture delta](inspector-fixture-diagnostic-delta.json).

## Verification and provenance

- Configured full unit suite:788 passed, zero failures/skips. Native ABI supplied
  explicitly; the earlier unconfigured failure is not acceptance evidence.
- Analyzer: no issues. Dart format check passed.
- Durable Linux production suite:5 workflows passed on the final host source,
  including repeated guarded Retry with the exact restored manifest and the same
  draft controllers. Missing guard stays blocked. The older4-case log remains
  historical. The full existing87-case Tasks native suite passes87/87 with zero failures.
  Both final native suites bind main6f5b37fc and the pre-copy-only renderer8219fa;
  the later singular wording change is separately reviewed and exercised.
- Native preview1/1, historical density1/1, matched-before1/1 and final density1/1
  passed. Final density supplies all eight theme/scale/viewport frames on3b; its
  measurements match the earlier density fixture. Inspect1/1 covers four cases.
  Renderer bytes and actual images remain bound by independent visual review.
- The bounded replay regression admits12,418,562bytes,1002records,100targets and
  1000-reference resolutions in2112ms on this Linux executor. This is a generous
  regression check, not mobile latency or a full-resource-limit claim.
- Independent correctness, architecture, security and UX receipts are under
  [reviews](reviews/). Receipts bind reviewed source bytes and distinguish
  independent execution from review of owner-executed logs. Older holds and
  narrower receipts remain historical and are not silently overwritten.

The final [renderer copy delta](renderer-copy-delta.json) verifies that reversing
only three label replacements restores exact pre-copy8219fa source bytes. The
Inspect failed attempts remain logs: singular-copy expectation red, one debugger
startup failure and forward-traversal/lazy-card fixture failures. The accepted
keyboard test retains real keys and full state checks, using Shift+Tab for the
preceding Collapse control and capturing the whole card for context.

Logs preserve meaningful observed red/green checks for exact receipt binding,
nullable legacy certainty, unsaved-editor confirmation, poisoned-owner close,
captured render origins, pending-editor exclusion and shared-authority loss.
Missing-implementation compile failures and historically misleading `*-red.log`
names are qualified in the independent correctness receipt. A prior production
run's failed `findsNothing` assertion was corrected to test hit reachability:
the recovery overlay deliberately retains the editor subtree. Its canonical
no-append assertion already passed; that run is not counted as a final pass.

Run configured checks from the repository with `/workspace/toolchains/env.sh`
sourced. Unit tests use `TANDEMLOG_TEXT_LIBRARY` pointing to the built reviewed
native library. Native suites run under `xvfb-run -a flutter test <integration
test> -d linux --no-pub --reporter expanded`. `FOOD_PREVIEW_EVIDENCE` selects a
synthetic screenshot output directory. To reproduce the historical Before,
restore the `.dart.txt` snapshots to the paths recorded in their imports and
place the executed harness temporarily in `integration_test`; run it as a Linux
integration test, not an out-of-tree unit test. No private/live data is required.

`manifest.json` binds checkpoint sources and every evidence file except itself.
The immutable review receipts retain original absolute local paths; compare the
copied attachment bytes by SHA256 rather than assuming those paths are public.

## Remaining gates and delivery limits

Actual Windows and Android device workflows, keyboard/accessibility expansion,
exact new candidate identity, installer/native acceptance and independently
reviewed release notes/media remain pending. No candidate/release is created or
promoted by this checkpoint. Private source import is unstarted; no live synced
user data was touched. The current unreleased Food wire format is not frozen.

Library's supported ordered helper upload failed before upload with a hosted
tool-list HTTP401. No Library file IDs or Library URLs were returned. GitHub
branch media is the authorized alternate delivery route; no direct Library
fallback was attempted after the helper write began.

Android tooling recovery is isolated under `/tmp`: the pinned Gradle archive
was SHA256-verified, and matching installed OpenJDK21 Debian snapshot compiler
and runtime packages were SHA256-verified and extracted without maintainer
scripts. No repository dependency, wrapper, SDK/NDK version or signing input
was changed. Initial failures (network/cache, missing compiler, then SDK35
installation under the nearly full inherited SDK root) remain qualified logs;
the final isolated-SDK `:app:compileDebugKotlin` succeeds (64 tasks).
[Compile provenance](android-kotlin-compile.json) binds the actual class files and
unchanged Kotlin source. None proves a
device acceptance or distributable APK.
