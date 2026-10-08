# Distinct real start-time boundary observation

This additional actual Linux GTK debug run completed in about three minutes,
2026-10-08 14:02:23–14:05:20 UTC, on virtual X display :195. It did not reproduce
Lee's reported morning stale-view behavior. It used the same previously bound
instrumented main `0a16` bundle, with no rebuild or production-source edits.

All four scalar v3 records (one user and three tasks) were prepared before app
launch. Two tasks had UTC start times 14:04 and 14:05. Canonical bytes were then
unchanged throughout observation, verified by SHA256 before/after. Existing
foreground import fallback calls remained unchanged and returned changed=false;
no external peer writes or sync deliveries caused these view transitions.

At 14:04, with GTK visible and another window active, the normal production clock
published the now-available task 2.459 ms after its boundary, built after 11.924 ms
and painted the new entity after 47.688 ms. The actual before-input screenshot
shows two tasks, versus one beforehand. The app was inactive with frames enabled.

The app was explicitly minimized before 14:05. Its hidden lifecycle stopped the
view/import scheduling; no import/view/build/paint occurred across the recorded
hidden interval. Normal window restoration at 14:05:08 displayed the second
now-available task, with new-entity paint 86.530 ms after restore. The actual
restored screenshot shows three tasks before mouseover. The pointer stayed outside the app at
1390,890; there were no task/editor inputs, timer-generated input, WidgetsTester
pumps, forced frames, system-clock changes or attempted system suspend.

[Structured result](clock-result.json) records stage times, exact task IDs,
canonical SHA and raw artifact hashes. The raw application and window/action
traces plus PNGs are in
[run-clock-20261008T140223Z](run-clock-20261008T140223Z/).
Screenshots 03 (before), 04 (unfocused after boundary), and 07 (restored after
boundary) were viewed directly. The [runner](run_clock_probe.py) and
[summary tool](summarize_clock_probe.py) are retained with hashes in
[clock-manifest.json](clock-manifest.json).

The source/patch/bundle binding is the existing
[instrumentation manifest](instrumentation-manifest.json); every listed bundle
file hash was reverified before this run. Production main/importer remained
byte-identical to `0a16a88355823d74c98246ed55f1ce85e45428ab`. Diagnostic timing may be
perturbed by metadata I/O and render observers, and is not a benchmark.

This bounded virtual Linux probe does not establish Windows behavior, overnight
idleness, physical/manual monitor power transitions, physical sleep/wake, system
suspend or release acceptance. Parent-reported Windows High performance AC
settings (sleep/hibernate/display Never) are contextual data only; this probe
makes no automatic-sleep assumption and cannot identify the Windows cause.
