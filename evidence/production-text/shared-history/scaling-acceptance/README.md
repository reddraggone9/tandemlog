# Bounded performance and soundness assessment

Exact candidate `c1823856be3f2b5aada5aa6960e7fbe9023f918f` is unchanged.
CI run 37728151359 passes Linux, Windows and Android, including the Linux aggregate
native workflows. The independently reviewed application inputs remain those
of `f952744`. Measurements use production TaskStore/native FFI in Dart AOT on
this cloud executor, retain synthetic fixtures and check exact cold/warm views
and original canonical bytes. These are single-run diagnostics, not native
phone latency or a total heap bound. Runs were sequential, with a 180-second
workload bound and a 2-second individual-completion bound; both full cases finish.

| Workload | Late completion median | Cold rebuild | Warm reopen | Peak process RSS | Lineage native cache BLOB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 320 occurrences, title/notes edited each time |54.620 ms|1348.312 ms|2.970 ms|81.3 MiB|101 B|
| 640 occurrences, title/notes edited each time |120.380 ms|3742.804 ms|2.652 ms|109.5 MiB|101 B|
| 520 weekly occurrences over ten simulated calendar years, edits every four weeks, 50 other active tasks |59.296 ms|1715.268 ms|3.290 ms|79.9 MiB|101 B|

Late completion means the final 20 samples per run. The realistic case contains 571 task
views and 702 canonical events; 130 edit commands update title and notes. It
simulates recurrence dates from 2016-10-07, not ten years of measured wall clocks
or actual user activity. Its total native BLOB payload is 3991 B, including the 50
independent tasks; only 101 B belongs to the 521-occurrence lineage. Total reference
JSON is 81406 B. Canonical bytes are 931182 B and SQLite pages 2957312 B. All 520
completions finish in the 27.076-second whole probe, including edits/reopens/rebuild.

The 640 stress case finishes in 98.177 seconds with 641 views / 1282 records.
Canonical bytes 1513056 B, SQLite 4874240 B and reference JSON 99924 B retain roughly
twice the 320 payloads; inherited native BLOBs stay 101 B. RSS is measured for the
whole AOT process and includes native state, caches and temporary allocations;
it is neither retained-graph accounting nor an Android RSS promise.

## What amplification was removed

The new representation actually shares original native packets and immutable
history references. It removes each occurrence's growing persistent inherited
BLOB and flattened original-packet list. Incremental pools deduplicate originals
across differently shaped branches and checkpoint restoration. The frozen native
and resolver gates verify original-packet replay rather than repeated inheritance
replay. Cache loss reconstructs exact fields, including original identities and
Undo/receipt meanings. Nothing was moved into another per-occurrence native BLOB.

It does **not** make total execution linear. `verifyTextInheritance` maps,
filters and sorts available canonical histories for observed prefixes; the
resolver scans histories and hashes each exact prefix before memo lookup.
Actual declared prefix memberships total 103040 at 320 and 410880 at 640: nearly
four times as many for twice as many completions. These are memberships derived
from actual frontier records, not an instrumented CPU visit count. Prefix work
is at least quadratic across a complete growing chain; sorting can add cost.
Global task snapshot comparisons grow with retained task rows. Ancestry scans,
sparse growing full-state exports every 32 levels of depth and transient exact
editor state capture/restore also retain growing work. Checkpoint bytes and
interned node counts are bounded; these do not bound total reachable references
or asymptotic CPU.

At 640, first/last 20 completion medians are 13.457/120.380 ms. Before-receipt medians
are 6.785/69.662 ms, after-receipt 6.739/49.610 ms, and canonical append 0.057/0.040 ms.
The realistic case grows 14.271→59.296 ms; its last 20 before/after-receipt medians
are 33.899/25.324 ms and append 0.085 ms. Independent medians need not sum. Append
is a small component; these phases do not isolate a particular Dart/SQLite method.

## Counter interpretation and review

Earlier raw `native_document_creations`/`native_creations` fields instrument only
the Dart `createDocument` method. They exclude `restoreDocument` and Rust-internal
document allocations. They must not be called a total native-document count.
The updated diagnostic counts create/restore calls separately. A supplementary
20-generation native run preserves exact views/canonical bytes and records 6
create calls and 50 restores overall; 4 restores occur in completion 1, and none
in completions 2–20. Materializer creation has a separate counter. The large
measurements were not repeated solely to fix this counter's description.

The preserved weekly report's older `edits_each_generation: true` field means
edits were enabled. Its explicit `edit_every_generations: 4` and 702 event count
describe the actual sparse-edit workload. The current driver separates enabled
edits from edits on every generation. Raw reports remain original run output.

Independent architecture assessment reports no new correctness/security blocker
and confirms removal of native/persistent amplification with remaining quadratic
prefix-processing debt. Original record meaning, actor ownership and pending
recovery remain protected by the already reviewed tests. This is a partial
performance improvement, not end-to-end linearity or final native acceptance.

Recommendation: retain the reviewed candidate and proceed with exact Android /
Windows affected-flow, latency and memory observation. The realistic cloud case
does not justify another broad native redesign or an open-ended optimization
loop. Further profiling should target prefix verification and global snapshot /
order work if actual native workflows exceed an agreed latency budget. No new
product/stack decision is established by these measurements. Checklist work can
proceed separately after the required fresh quota read; stable promotion remains
Lee's decision.

Owner: Tandemlog implementation, coordinated with Lee. Impact: growing completion
and cache-loss costs, with remaining temporary-prefix and held-reference memory.
Exit: either explicitly accept measured native-device latency at the preview
milestone or remove unnecessary prefix/snapshot work while preserving closed
proofs, original hashes, ownership and replay. Revisit before a long-history
performance claim or stable shared-history promotion.

Raw 640/realistic/counter reports and the updated driver are preserved alongside
the prior 320 phase report. Original fixture directories are recorded in each
JSON. No live synced data, existing candidate payload or dependency was changed.

Independent review: `/root/architecture_review` checked these reports, counter
interpretation and preserved history. It independently recomputed 410880 prefix
memberships at 640 and 196040 for the weekly fixture, found no remaining must-fix
in this measurement/assessment scope, and recommended the bounds wording above.
