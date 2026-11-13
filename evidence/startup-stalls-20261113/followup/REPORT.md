# Follow-up: bounded SQL batching rejected

The 60fps/no-slower-startup goal remains **unmet**. No production source change is retained from this experiment. The rejected patch is included for reproducibility, not application.

## Prior CI

Run 43515128533: Linux, Windows, Android, performance, all native workflow shards and their union passed. Only reference-performance failed: its controlled-reference qualification and native cold-start evidence are source-bound to other source. These are not proof of current frame-budget compliance.

## Profile-directed experiment

Prior symbolized VM/native profiles identify synchronous Task projection copying and shared history SQL commit, plus Linux Fontconfig in first-list layout. Tried bounded multi-row SQL projection INSERTs (32 rows, <=900 bindings) to reduce native calls while retaining the shared atomic transaction, proof triggers, and validator ownership. Targeted cache-integrity and latency tests: 20 passed. Linux release build passed. No tests/builds ran during the following measurements.

Five serial interleaved main/prototype samples, identical synthetic template and existing paired harness:

| Mode | Main max-gap samples ms | Prototype max-gap samples ms | Median app-to-list main/prototype |
|---|---|---|---|
| strict |715,729,797,849,738|83,93,85,93,85|2108/2728 ms|
| warm |58,65,59,62,70|67,63,62,58,73|383/509 ms|

The prototype includes all previous branch changes. Previous branch medians: strict86/warm62ms gap, strict2880/warm569ms elapsed. New85/63ms gaps are not a material solution. Cross-batch elapsed differences are not causal evidence. Sample4 took3774ms; all samples retained. Rejected patch is saved, production source restored to2c337aa5.

Residual per-stall ranges, previous branch -> prototype:

- Shared history atomic SQL publication:51–62 ->51–64ms.
- Task projection/open:84–98 ->83–93ms.
- Linux font/layout:59–74 ->57–65ms strict; warm final up to73ms.
- Warm intermediate:72–73ms previously; up to61ms this batch, not a verified fix.

Phase-associated heartbeat gaps are not isolated function timers. Raw timestamps and landmarks are retained.

Remaining architectural boundary: the shared profile owns a synchronous SQLite connection and synchronous projection callbacks. Scratch validator slicing cannot move final shared-profile copying/commit off the UI isolate. This needs an async database-owner interface spanning atomic heads, history, projections and post-commit publication. Independent piecewise commits or yielding inside an exposed transaction would violate the requirements. Batching was insufficient; integrity/seals/atomicity were not weakened.

Fontconfig FcPatternFilter/FcFontSetMatch is a Linux backend, not the Android/Windows backend. This does NOT prove equivalent font/layout stalls absent elsewhere. CI proves builds/tests, not platform frame timings. No device install, live profile or release occurred. Runtime comparisons remain unverified. No speculative synchronous prewarm added: that would move rather than remove the launch stall.

This is negative experimental evidence, not completion. Next substantive work remains off-isolate shared SQLite ownership, backend-specific font profiling, then the same five-pair measurement. No accepted follow-up improvement is claimed.
