# Targeted Linux native acceptance measurement

Unchanged production library: `/tmp/tandemlog-production-text-libs/linux/libtandemlog_text.so`, SHA256 `945c219d8191fa861020aae90c577e5b8814d17b625570d50b9d510614c16f2d`. No source, tests, prior performance evidence or packaging changed. All diagnostics ran in fresh ctypes processes with individual 60-second timeouts; all completed normally.

## Representative sessions

Near-full visible title (498/500 UTF16) and notes (9998/10000), repeated single-character replacements in a captured draft, nonmutating prepare-save, concurrent remote edit before save, exact prepared Undo receipt with another remote edit before commit. Remote edits survived; prepared save bytes matched committed save bytes. Limits update 1MiB/state 8MiB/session 16MiB/retained 64MiB.

| Field / edits | Max edit ms | Edit p95 ms | Max read ms | Prepare save ms | Save ms | Prepare Undo ms | Commit Undo ms | Peak less startup baseline KiB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| title / 100 | 0.461 | 0.314 | 0.078 | 0.036 | 0.375 | 0.189 | 0.248 | 2308 |
| title / 1000 | 2.537 | 1.745 | 0.049 | 0.044 | 2.320 | 0.171 | 0.436 | 4444 |
| notes / 100 | 1.597 | 1.327 | 0.074 | 0.030 | 2.194 | 1.527 | 2.861 | 3664 |
| notes / 1000 | 4.611 | 2.876 | 0.079 | 0.041 | 4.122 | 1.817 | 2.716 | 6356 |

These are measured synchronous ABI latency including JSON response decoding/free (request encoding excluded), not Flutter frame timings, disk append latency or mobile results. No GUI was running. Native-only workload means no Dart app; Python launcher/JSON/fixtures remain in RSS. Baseline subtraction estimates attributable growth, not an allocator-level native-only RSS proof. `/proc` current RSS and `getrusage` high-water accounting differ slightly on this host: notes1000 final current RSS was17632KiB versus reported high-water17316KiB, so conservative observed growth is6672KiB rather than6356KiB. Session had up to target+private draft+remote owners, not one standalone allocation. One1000-edit notes target after save/Undo reported32418 retained serialized bytes; global serialized52570 bytes. This sample does not saturate allowed session/state limits or establish a universal worst case.

## Concrete rejected-update blocker

A fixed valid Yrs V1 packet with a single plaintext struct has exactly1048576 decoded bytes (1048561 ASCII units, no deletes). Both title500 and notes10000 owners reject `apply` with `text size limit`; full state before/after is identical.

First exact-size run: title325.167ms, notes325.751ms; process peaks244824/246232KiB, baseline growth233872/235280KiB (~228–230MiB).
Repeat with already-built Python fixture baseline immediately before apply: title296.208ms and notes275.831ms; pre-apply RSS15892/16012KiB, peak244728/246156KiB. Thus peak above payload-ready process is228836/230144KiB (~223–225MiB). Python retains the base64 fixture and request/response JSON adds overhead, but that few-MiB fixture cannot explain the ~224MiB transient increase. Source admission expands each UTF16 unit into a HashMap identity before later visible-size rejection (`native/text_engine/src/admission.rs`); this matches measured allocation amplification.

Acceptance recommendation: normal representative sessions pass a single-call16ms diagnostic target on this Linux host, but hostile bounded-operation acceptance is blocked. Add a separately frozen admission/materialization work budget before per-unit expansion. Do not substitute visible length as a history identity cap blindly: historical deleted text and checkpoint identities can legitimately exceed visible limits. The serialized64MiB cap is demonstrably not a nativeRAM cap. No parser changes made in this diagnostic task.

The1MiB packet is a native-operation boundary test; canonical1MiB JSON-envelope publication would impose a lower raw base64 size. It nevertheless establishes the admitted native input worst-boundary hazard and is safe fixed synthetic data (no fuzzing).

## Idle list

Library-loaded process with zero native calls/doc creation: loadedRSS11264KiB versus baseline10964KiB, final11276KiB. This verifies lazy native ownership for no calls, not actual rendering of2000 app rows. Static production cache evidence: `lib/storage/text_cache.dart` creates/restores temporary materialization candidates and disposes them in finally (lines87–88,225–226); ordinary list data does not need retained editor owners. Actual2000-task Flutter owner-count instrumentation remains root-owned integration evidence; this diagnostic must not claim it ran a2000-task app list.

Raw evidence: `results.json`, `exact-1mib.json`, `exact-1mib-with-payload-baseline.json`; reproducible diagnostic `measure.py`. Earlier results use1MiB-minus2bytes; exact-size reruns are separate and preserved. No timeout, crash or state mutation on rejection occurred. No build running, no commits/publication.
