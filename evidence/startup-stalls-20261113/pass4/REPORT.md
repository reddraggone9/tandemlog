# Pass 4: bundled-font experiment (rejected)

Goal remains **NOT MET**. Production source remains 48b01b1d. No release, installation, live data or storage/publication-order changes.

## Experiment and decision

Bundled Google Fonts Roboto normal/italic variable fonts, all 100–900 weights, as Flutter font assets. Sources: https://github.com/google/fonts/tree/main/ofl/roboto (downloaded 2026-11-13); OFL license retained with fonts. Candidate patch retained here; reproduce by copying `fonts/` to `assets/fonts/` then applying patch at repository root. Variable font files are shared across weight declarations, not eighteen distinct files.

Weighed against system font installation (would hide the host-specific problem), more sliced warmup (cannot split a native match), and warm-open owner migration / first-list subdivision (not implemented this pass; these need causal profiling before a safe redesign). Private font family name first changed Flutter test fallback metrics and caused layout failures; preserving default Roboto identity resolved them (activity-layout 12 passed). Final candidate analyze clean, full suite **1,938 passed**, Linux release bundle built. Font warmup remained unchanged.

The asset candidate did not establish any improvement over pass3b, nor meet either acceptance condition. Rejected it and restored production source rather than add ~1MB of assets without a demonstrated benefit. Its observed gaps must not be re-labelled as Fontconfig without a symbolized profile. No new accepted production code.

## Five interleaved pairs

Release Linux synthetic fixture, serial before/after pairs, one strict plus one warm per binary; no concurrent builds/tests. Before = bundle-base origin/main; after = rejected bundle-pass4 atop 48b01b1d. Raw logs retain every >=8ms gap and phase landmarks.

Quiet-window request refused because video playback was active. Playback was not interrupted. Load average at pair starts: 12.67,13.96,14.60,15.36,16.70 (1-minute); 15-minute 16.10–16.31. Therefore elapsed parity is **unproven**. Fence requested/resumed/released; pause refused before any service-control changes; healthy services/pool verified afterward.

| Mode | Main max gap median (range) | Candidate max gap median (range) | Main app→list median (range) | Candidate app→list median (range) |
|---|---|---|---|---|
| Strict | 790ms (769–813) | 31ms (28–42) | 2106ms (2015–2390) | 2178ms (1981–2225) |
| Warm | 63ms (60–70) | 49ms (35–78) | 406ms (386–422) | 413ms (360–454) |

These before/after differences mostly measure the already accepted pass3 source, not a font win. Pass3b's earlier loaded medians were strict28/warm37ms; comparing separate loaded batches is not causal. Candidate strict elapsed +72ms; warm +7ms versus interleaved main medians. Neither is evidence of satisfying the no-slower constraint.

## Still over one frame

Candidate first-list frame remains ~26–30ms; warm early synchronous chunk reached78ms; other early ~19–29ms chunks remain. Prior source attribution (pass3) identifies first-list build/layout, manifest/folder/store probes, Linux Fontconfig variant matches and Dart-entry initialization. This pass has no new symbolized trace to assign individual candidate gaps. Startup [0,16–18ms] is near/over the16.7ms boundary; 8.3ms stretch is clearly unmet. Linux Fontconfig itself is platform-specific; Dart storage/build work is plausibly cross-platform but Android/Windows runtime timings remain unmeasured. Successful builds are not frame measurements.

## CI

Run43526697202 checked: performance, Android, Linux, linux-workflows0–3 and union passed; expected reference-performance failure; Windows still pending at last observation. New evidence-only CI dispatched once after push (URL in worker handoff). No claim all product jobs finished while Windows pending.

Next: obtain symbolized warm first-chunk/first-list traces and redesign the actual dominant work; obtain quiet interleaved qualification before any acceptance claim. Goal unfinished.
