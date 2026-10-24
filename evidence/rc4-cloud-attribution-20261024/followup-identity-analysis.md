# Follow-up identity representation repair

The retained full AOT failures remain failures. Limits, samples, first-use and both growth comparisons are unchanged. The current change caches only immutable event-ID/effect-key strings; no admission/freshness/result or physical-history proof is cached. Full local units1500 pass, analysis is clean, and the narrow existing peer scenario passes correctness/full replay before and after. Exact-commit enforcing CI remains required.

## Exact retained failures

All values below are milliseconds. CPU brackets include counter overhead outside the timer. Append intervals include directory bookkeeping, native write/barriers and scheduling; they are not fsync-only service time. Earlier instrumented API partitions retain their original source and must not be assigned to these later uninstrumented samples. Full samples/counters: [JSON synthesis](followup-failure-synthesis.json).

### cloud-final

| Shape/action | Median / bound | Maximum / bound | Failing statistic | Slowest retained attribution |
|---|---:|---:|---|---|
| dense-1 / explicitTask.titleAndNotes.undo | 20.850 / 35 | 53.792 / 40 | maximum | append 0.684; CPU bracket 50.305; snapshot decoded 0; Task sorts 0 |
| dense-1 / startup.cold.total | 991.158 / 925 | 996.371 / 935 | median/maximum | Aggregate startup phase |
| dense-1 / startup.cold.history | 947.230 / 880 | 956.299 / 890 | median/maximum | Aggregate startup phase |
| dense-2 / converted.task.bulkReorder.undo | 42.593 / 50 | 60.916 / 55 | maximum | append 0.794; CPU bracket 58.642; snapshot decoded 0; Task sorts 0 |
| dense-2 / converted.checklist.add | 50.647 / 55 | 66.683 / 60 | maximum | append 0.602; CPU bracket 51.631; snapshot decoded 0; Task sorts 0 |
| dense-2 / historical.food.details.1.undo | 9.355 / 15 | 22.108 / 20 | maximum | append 0.759; CPU bracket 31.944; snapshot decoded 0; Task sorts 0 |
| dense-2 / startup.cold.total | 1343.373 / 1335 | 1358.310 / 1370 | median | Aggregate startup phase |
| dense-2 / startup.cold.history | 1286.754 / 1240 | 1302.342 / 1260 | median/maximum | Aggregate startup phase |

| Pair/action | Large median / computed bound | Large maximum / computed bound | Failing statistic |
|---|---:|---:|---|
| task-own-history / food.restore.1 | 7.583 / 11.426250 | 16.022 / 15.584000 | maximum |
| task-own-history / historical.food.details.1.undo | 9.355 / 11.776250 | 22.108 / 15.129000 | maximum |
| task-own-history / cardinality500.food.delete.1.undo | 13.976 / 13.871250 | 14.622 / 18.034000 | median |
| food-own-history / task.titleAndNotes.undo | 36.936 / 36.863750 | 43.582 / 71.245200 | median |
| food-own-history / food.restore.1 | 8.311 / 11.426250 | 16.033 / 15.584000 | maximum |
| food-own-history / sync.peerFood.whileTasks.storageAdmission | 14.158 / 11.786250 | 16.744 / 21.763600 | median |

### hosted-enforcing

| Shape/action | Median / bound | Maximum / bound | Failing statistic | Slowest retained attribution |
|---|---:|---:|---|---|
| dense-1 / task.titleAndNotes.undo | 27.496 / 45 | 60.556 / 55 | maximum | append 38.618; CPU bracket 22.653; snapshot decoded 0; Task sorts 0 |
| dense-1 / converted.task.complete.checklistConfirm | 81.047 / 70 | 216.522 / 85 | median/maximum | append 0.509; CPU bracket 38.362; snapshot decoded 0; Task sorts 0 |
| dense-1 / task.complete.checklistConfirm | 35.749 / 70 | 163.248 / 80 | maximum | append 0.376; CPU bracket 34.232; snapshot decoded 0; Task sorts 0 |
| dense-2 / converted.task.reorder | 29.433 / 55 | 62.728 / 60 | maximum | append 6.444; CPU bracket 89.283; snapshot decoded 0; Task sorts 0 |
| dense-2 / checklist.titleAndNotes.editorOpen | 2.341 / 10 | 110.619 / 15 | maximum | append 0.000; CPU bracket 2.846; snapshot decoded 0; Task sorts 0 |
| dense-2 / checklist.titleAndNotes.save | 24.638 / 50 | 206.569 / 60 | maximum | append 183.773; CPU bracket 35.723; snapshot decoded 0; Task sorts 0 |
| dense-2 / task.complete.checklistConfirm | 35.670 / 70 | 80.019 / 80 | maximum | append 1.495; CPU bracket 78.452; snapshot decoded 0; Task sorts 0 |
| dense-2 / recurring.complete.undoUntouched | 44.004 / 65 | 76.832 / 70 | maximum | append 0.493; CPU bracket 42.283; snapshot decoded 0; Task sorts 0 |
| dense-2 / recurring.complete.undoProtectedSuccessor | 50.087 / 70 | 85.988 / 75 | maximum | append 0.502; CPU bracket 53.716; snapshot decoded 0; Task sorts 0 |
| dense-2 / cardinality500.food.details.3.undo | 8.745 / 15 | 165.926 / 20 | maximum | append 156.746; CPU bracket 16.295; snapshot decoded 0; Task sorts 0 |
| dense-food / converted.checklist.add | 41.185 / 55 | 65.060 / 60 | maximum | append 0.593; CPU bracket 60.600; snapshot decoded 0; Task sorts 0 |

| Pair/action | Large median / computed bound | Large maximum / computed bound | Failing statistic |
|---|---:|---:|---|
| task-own-history / task.title.undo | 20.247 / 26.955000 | 43.429 / 36.140200 | maximum |
| task-own-history / checklist.titleAndNotes.editorOpen | 2.341 / 5.911250 | 110.619 / 8.330600 | maximum |
| task-own-history / checklist.titleAndNotes.save | 24.638 / 32.956250 | 206.569 / 46.477800 | maximum |
| task-own-history / recurring.complete.nativeChecklist | 36.658 / 47.431250 | 74.521 / 64.549000 | maximum |
| task-own-history / recurring.complete.undoUntouched | 44.004 / 56.071250 | 76.832 / 69.643600 | maximum |
| task-own-history / recurring.recomplete.nativeChecklist | 40.328 / 62.470000 | 74.728 / 73.723200 | maximum |
| task-own-history / derivedSuccessor.complete.nativeChecklist | 38.355 / 52.033750 | 75.767 / 70.357600 | maximum |
| task-own-history / recurring.complete.undoProtectedSuccessor | 50.087 / 64.517500 | 85.988 / 74.882400 | maximum |
| task-own-history / recurring.recomplete.keepProtectedSuccessor | 38.168 / 45.650000 | 57.881 / 55.404200 | maximum |
| task-own-history / explicitTask.notes.save | 13.369 / 19.417500 | 32.864 / 30.582200 | maximum |
| task-own-history / converted.task.reorder | 29.433 / 36.205000 | 62.728 / 45.889800 | maximum |
| task-own-history / converted.task.restoreViaUndo | 17.038 / 23.622500 | 34.185 / 30.429600 | maximum |
| task-own-history / cardinality500.food.details.3.undo | 8.745 / 12.370000 | 165.926 / 16.452000 | maximum |
| task-own-history / cardinality500.food.restore.1.undo | 7.619 / 11.953750 | 18.665 / 17.037200 | maximum |
| task-own-history / cardinality500.food.paired.details.save | 6.611 / 11.593750 | 17.041 / 15.509800 | maximum |
| food-own-history / task.metadata.tags | 10.178 / 16.106250 | 20.692 / 20.531600 | maximum |
| food-own-history / task.metadata.tags.undo | 9.606 / 13.502500 | 20.394 / 17.994800 | maximum |
| food-own-history / converted.task.bulkDelete.three | 22.765 / 33.851250 | 43.120 / 41.573600 | maximum |
| food-own-history / converted.task.reopen.withChecklist | 22.849 / 29.138750 | 46.694 / 40.100800 | maximum |

## Measured change and selected fix

The prior sort fix observed peer-Food medians8.112/12.408/15.432ms changing to7.029/10.935/14.158ms across base/Task/Food growth. Its exact-set proof removed Task sorts, but final Food growth still exceeded its11.78625ms median bound. Separately generated sealed fixtures and finite samples prevent an isolated causal-speedup claim. Snapshot serialization reuse measured zero redecodes on repeated unchanged live SQL results; those SQL/freshness checks still execute.

A narrow immutable Food-admission copy probe measured171/180/481us median on329/329/1649 Food records. That copy cost alone is too small to explain the complete peer-refresh growth. Inspection instead found repeated identity-string construction in full-history maps and prior-ID comparisons: UnifiedEffect.key interpolated module/space/ID on every lookup, and LogEvent.id repeatedly interpolated immutable writer/sequence. The same decoded effects are revisited across refreshes.

The fix retains those two derived strings per existing immutable object. All history collection, duplicate-byte comparisons, reference validation, ready/pending publication, native checks and transaction boundaries remain. Wire encoding/meaning is unchanged. No global cache, new authority, new dependency or persisted format is introduced. Owner/cache lifetime already bounds retention of the decoded objects.

The targeted before/after probe invokes the existing production `scenario(..., peer, changedPeer)` with the same sealed three fixture workspaces, unchanged two warmups/five measured repetitions, original-prefix checks and fresh replay. It is not a replacement for the full232-metric gate. [Full probe evidence](followup-peer-identity-probe.json), [exact diagnostic entrypoint](followup-peer-identity-probe.dart.txt).

| Shape | Before peer-Food median/max ms | After peer-Food median/max ms | After peer-Task median/max ms |
|---|---:|---:|---:|
| dense-1 | 7.273/10.438 | 6.159/10.212 | 34.078/41.879 |
| dense-2 | 11.548/13.187 | 10.412/15.682 | 40.233/41.760 |
| dense-food | 12.445/14.551 | 9.654/10.642 | 35.190/42.511 |

The targeted after-change peer-Food medians10.412/9.654ms fit the baseline6.159ms-derived10.69875ms bound; both maxima fit too. These are finite narrow observations, not acceptance or a guaranteed speedup. RSS observations are retained in JSON rather than interpreted as a controlled memory comparison. Hosted durable-append tails and remaining operation-specific costs are still unresolved; no unavoidable product tradeoff has been established.

## Original close failure conditions

The original cb1ea0e failure used the unmodified measure_startup.py queue/pipe reader and sent WM_DELETE immediately after the readiness marker. It exited with SIGSEGV. The successful GDB controls used a debugger-mediated start and50ms file polling; their package setup also omitted the original Linux job's Flatpak/portal installation. They therefore do not clear the original failure or prove an upstream cause.

The next standalone diagnostic checks out exact cb1ea0e, uses the original Ubuntu24.04 package set plus GDB, restores its native-unit environment, builds the ordinary release binary and runs the unchanged original fresh/warm harness once. A bounded kernel core is produced only after a fault; GDB reads it after the harness exits. The prior kernel setting is restored. This does not change pre-fault app launch, readiness observation or normal-close input, and it retries no AOT timing experiment. Packaging-tool prewarming and host scheduling are not claimed identical.

Only cores whose PIDs the original owned-window receipts certify are read. Raw memory cores are excluded from artifacts because ambient CI credentials could be present; retained stack output omits frame arguments/locals. Core hashes, binary hash, signal/stack status and every original harness result are retained. No crash workaround or SDK change is inferred from clean runs.

## Full-prefix native-close capture

The original-source isolated pair completed cleanly (fresh1307ms, warm225ms),
with no core; its binary SHA matches the earlier GDB control. That does not
clear the failure. The new full identity-repair CI40129495617 again failed normal
close with SIGSEGV after startup3351ms, close1882.567ms. Thus two full pipelines
have failed while the isolated pair did not. This is a small observed pattern,
not proof that prior test work causes the crash.

The next original-source diagnostic includes the original Linux check prefix:
AppStream preparation, formatting/analysis, all units, native/frozen contracts and
tooling, followed by the same ordinary build and original fresh/warm harness.
Post-fault core collection remains enabled, with no debugger before the fault.
This is a distinct execution-condition control, not an AOT retry or additional
unchanged clean-close sampling. Product/performance source remains c213ea9.
