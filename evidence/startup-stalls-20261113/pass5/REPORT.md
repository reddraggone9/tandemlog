# Pass 5: symbolized attribution and rejected warm-decode experiment

**Goal not met. No accepted production source change.** Source remains 48b01b1d.
No release, device install, or live user profile. Synthetic Linux runs only.

## New causal evidence

Current-source Linux profile executable captured strict and warm launches via VM service CPU samples and VM timeline. Full raw JSON is compressed alongside this report; capture harness and raw launch logs included. Profile timing is diagnostic, not a release-mode main comparison.

- Strict profile: app-to-list 2107 ms, max heartbeat gap 30 ms; warm: 411 ms, max 57 ms.
- Warm first-list LAYOUT was **23.472 ms** at VM timestamp 1021443341340, main thread 992059. Of 19 CPU samples in that exact window, 6 contain `FcPatternFilter`; other stacks include widget mount/rebuild. Fontconfig is therefore **still present in first-list layout**, contrary to earlier interpretations that warmup removed all font work. Initial loading LAYOUT also took 18.041 ms.
- An early warm embedder `DartIsolate::HandleMessage` lasted 37.092 ms at 1021443054990. Actual `Dart_HandleMessage` starts only at 1021443092036 (~37.05 ms later) and then completes in ~39 microseconds. There are **zero main CPU samples** in that 37 ms window. Numerous worker Scavenge/ConcurrentMark slices have the same isolateGroupId as main. This does NOT prove 37 ms of synchronous manifest/store Dart work. Shared-group GC/worker churn or host scheduling is a hypothesis, not a proven exclusive cause.
- Timezone initialization appears in early stacks, but only a few samples: not evidence that it accounts for the 57 ms heartbeat gap.
- Warm app stacks overall include validator cache restore, SQLite bind/UTF8, projectTaskView and ViewClock invalidation. Do not assign their global inclusive sample counts to the early sample-free window.

## Experiment and rejection

Warm store restore already runs on its background connection owner, but creates nested decode isolates for each 400-row chunk. Prototype decoded those chunks sequentially on that existing owner to reduce shared-group worker/GC churn. No transaction, sealing, or post-commit publication semantics changed. Rejected: warm startup became slower. Production restored.

Five serial interleaved **incumbent48b01b1d vs prototype**, release Linux, strict+warm per pair, no concurrent build/tests. NOT origin/main pairs. Playback active; quiet-window eligibility check returned true for playback blocking, services untouched. Load retained in load.txt. Strict improvement (untouched strict code) illustrates host-load/order drift; do not attribute it to the warm-only change.

| Mode | Max gap incumbent→prototype (median) | App→list incumbent→prototype (median) |
|---|---|---|
| strict | 29→27 ms | 2168→1990 ms |
| warm | 33→30 ms | 412→509 ms |

Cumulative phase medians (ms since main):

| Mode/side | settings | folderList | history | tasks | bound | first list |
|---|---|---|---|---|---|---|
| strict incumbent |37|42|1981|2128|2131|2168|
| strict prototype |37|42|1808|1952|1958|1990|
| warm incumbent |36|41|331|376|379|412|
| warm prototype |36|42|423|463|469|509|

Phase-bucket max-gap medians are separately retained in phase-gap-medians.json (bucketed by gap start; boundary-spanning gaps are not split). All >=8 ms gaps and individual phase timestamps in measurements.json and p5-*.txt. Valid-fixture decode work is identical in both prototype forms; rejected patch includes a Future.sync failure-handling refinement made during the initial build/test round, so it is not presented as a source-bound qualified artifact.

## Main-relative status and remaining

No new main-relative claim: previous pass3b five loaded pairs were strict max median781→28 ms / elapsed2155→2255 ms, warm62→37 ms / elapsed386→398 ms. Pass4 rejected fonts, also without a quiet parity result. Current incumbent batch strict29 / warm33 ms still exceeds16.7 ms (8.3 stretch). No phone runtime evidence.

Next useful investigation: identify the exact fallback/glyph/style still invoking Fontconfig in first-list layout (not another broad bundled-font change), and obtain scheduler/GC-aware warm trace before subdividing supposed synchronous Dart work. Shared-heap worker churn remains a candidate; simply serializing decode is rejected by the elapsed requirement. Quiet main pairs remain blocked by playback.

## Verification

Initial analyze clean; full suite1938 PASS; profile and release candidate builds passed. Restored-source final analyze/full-suite outcome recorded in checks.txt. No CI dispatch this pass (evidence-only); branch pushed after checks. Existing pass3/4 CI is not represented as verification of a new candidate.
