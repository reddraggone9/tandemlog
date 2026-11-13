# Startup UI stalls — 2026-11-13

Goal: no UI-isolate gap over 16.7 ms (aim 8.3 ms), strict and warm, through the first list. **Not met.** No release, install or live profile was used.

## Native paired measurements

Five interleaved before/after pairs, one strict plus one warm per binary per pair, release Linux bundles, identical synthetic canonical fixture, private Xvfb/DBus. Local tests/builds and profiling children finished before measurements. Ordinary household services remained running. Raw files retain every reported gap >=8 ms, including timestamps; measurements.json includes all phase landmarks. Millisecond heartbeat gaps are not raster/GPU frame timings.

| Build | Mode | Longest gaps (ms), samples 1–5 | Median gap | Median app→list |
|---|---|---|---|---|
| before | strict | 760, 761, 754, 729, 787 | 760 ms | 2138 ms |
| before | warm | 63, 57, 60, 65, 61 | 61 ms | 394 ms |
| after | strict | 98, 86, 97, 85, 84 | 86 ms | 2880 ms |
| after | warm | 62, 59, 74, 59, 73 | 62 ms | 569 ms |

The main strict freeze is substantially reduced, but startup takes longer overall because cooperative pauses trade elapsed time for responsiveness. Warm longest gaps are not improved. Do not present this as 60 fps or as a faster launch.

## Implementation and safety

- Strict and warm Task validation now cooperatively slice replay, reference/readiness checks, ordering and index work with a 4 ms budget. Synchronous callers retain their API. Private scratch transactions are discarded on interruption/failing pause; concurrent validation is refused.
- Warm witness-protected Task projection restore pages 512 rows, rechecks the witness after reading, then consumes it. A changed witness falls back to strict replay; no shared-profile cursor spans a pause.
- Task sort/revision and cold Food admission use pure short-lived workers. History row reads page 128 records; worker-prepared serialization still commits atomically with heads.
- Bounded task-row widget creation and theme reuse reduce eager UI work. The heartbeat starts at Dart entrypoint.

## Remaining work (not a release gate pass)

1. Strict shared-history SQL commit remains roughly 51–62 ms in the final runs. TaskStore projection staging/copy remains roughly 84–98 ms, synchronous and atomic. Move private preparation/copy work off-isolate without weakening the shared profile transaction, then repeat these exact paired measurements.
2. First-list Linux native font resolution remains roughly 59–74 ms. Independent symbolized profile showed Fontconfig FcPatternFilter/FcFontSetMatch dominating layout/build (first-list layout57.1 ms, nested BUILD35.5 ms; another trace layout71.6 ms). Lazy Dart row construction is not evidence of a Fontconfig fix. Compare with Android before generalizing this desktop cause.
3. Warm after samples include 72–73 ms intermediate gaps as well as the final font frame. Follow their timestamps in raw evidence; do not hide them behind the validator improvement.
4. Phone measurement remains unverified: no install was authorized for this worker. No claim about Android frame safety.

## Verification

- Full clean local suite: **1,926 passed**; analyzer: no issues; Linux release bundle built.
- Validator child: 206 related tests plus final 12-file subset passed, including parity, tampered witness, close during pause, concurrent calls and failed pause cleanup.
- Existing independent safety review reported no findings; deep UI review identified font matching rather than recommending speculative Dart restructuring.
- CI dispatch/result tracked by the parent; this report is local evidence, not a CI pass.

The JIT validator slice microbenchmarks (mostly 6–10 ms) are diagnostic only; native launch gaps above supersede them.
