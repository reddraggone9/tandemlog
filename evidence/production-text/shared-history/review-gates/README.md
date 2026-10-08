# Independent review and fixes

Three fresh agents independently reviewed `34addf6..cc64bc2`, then the fixes
through `f952744c4e8623df49a90e575aa7293cfa2eb6ff`. Architecture, correctness /
compatibility / Undo / recurrence, and security / resource abuse now report no
remaining must-fix finding in their respective scopes. This is implementation
review, not Windows/Android acceptance or publication approval.

The frozen red commits are `f666630` and `c6a5761`; fixes are `5c6618e` and
`f952744`. The original red diagnostics remain beside this file.

| Finding | Result and regression |
| --- | --- |
| P2 obsolete graph shapes retained indefinitely under reordered arrivals | Disposable interning now has a 4096-entry LRU cap. Actual native 128-writer reverse arrivals retain old references and reconstruct exact native state. Hash construction is unchanged. |
| P2 original packet reapplied under differently shaped nodes | Each active native document retains original packet keys, including checkpoint restoration. Both initially failing branch cases now apply two originals exactly twice. |
| P2 external implementation forges a resolver-verified field | `ResolvedTextField` is final. Both external implementation and subclass compile on the earlier source and fail on the fix. The public legacy constructor still receives the independent native proof checks. |
| P2 rejected native payload persists outside memo budgets | Rejection discards memo authority. Three oversized native candidates leave zero graph packets and valid retry succeeds. |
| P2 pending resolution republishes fields from a closed runtime without inherited actor ownership | A reused resolver rejoins a live memo runtime before publishing. The independently authored native actor42 gate uses disjoint struct clocks: both cold and warm replay now reject the same ownership collision. |
| P3 cancellation failure masks rejection and interrupts cleanup | Cleanup detaches maps before best-effort disposal of every pool. Injected lost cancellation responses preserve the original failed operation and zero retained authority across all three candidates. |

The independent correctness reviewer also authored the frozen four-writer
historical delivery gate: Undo before marker before source, both source/marker
orders, duplicate refresh, and a source-hash mismatch discovered on delayed
arrival with transactionally unchanged event count and task snapshot.

Current local gates: all 507 Flutter tests, all 37 tooling/compiler tests, clean
analysis and full format gate. Both actual bundled Linux native text workflows
pass after the final application fix. Rust/Yrs code, frozen scalar fixtures and
lockfiles are unchanged from the prior 107-native/four-Rust checkpoint; final CI
reruns the platform-specific native gates.

The actual Linux GTK Release historical completion demo is in
[desktop-demo](desktop-demo/receipt.json): 1280×720, dark theme,100% text,
7.13 seconds, real visible pointer movement/click. Before/After and an extracted
pointer frame were inspected. Existing synthetic canonical files remain exact;
the only new record is the parent-only historical completion. The production
native payload/notices gate passes. This is Linux evidence; Windows and Android
affected flows/videos remain separate.

## Remaining performance and resource work

The 4096 cap bounds only the interning index. Held immutable reference chains,
memo summaries, checkpoints and active documents can retain larger graphs;
accepted original authority still grows with canonical history. Externally held
closed fields/resolvers can retain their closed runtime graph maps. They cannot
republish authority after the fix. These are explicit retention limits, not a
total heap/RSS guarantee.

A proportional 80-generation AOT diagnostic on the review-fix application tree
passes exact cold/warm projections and unchanged canonical files: warm reopen
3.987ms, cold rebuild311.202ms, native BLOB101B and reference JSON12564B. Median
completion time grows from17.022ms in the first20 to24.319ms in the last20. The
earlier640 run grows from13.465ms to125.409ms across the corresponding ends.
Single-run timings are diagnostic and were collected under different load;
they do not establish a speedup/regression. After the first completion, the80
run creates no new editor documents or native inspection calls during completion.
Full-prefix collection/hashing and graph ancestry scans remain candidates for
profiling; they have not been isolated as the dominant cost.

A later single 320-generation phase diagnostic uses the unchanged application
from `c1823856be3f2b5aada5aa6960e7fbe9023f918f` with measurement-only receipt and
transport timers. Exact warm/cold projections and canonical preservation pass.
Median completion grows from13.787ms in the first20 to54.620ms in the last20.
The before-receipt portion grows from6.945ms to31.450ms; after-receipt work grows
from6.707ms to23.195ms. Canonical file append medians remain0.055ms/0.040ms.
These independent medians need not sum. The receipt split includes validation,
snapshot/proof collection and staging before it; writer reservation, append and
ingestion/reconciliation follow it. Thus canonical file append is a small part
of the observed cost, and both sides of receipt preparation grow. This does not
isolate a specific Dart/SQLite method or establish a speedup. Warm reopen2.970ms,
cold rebuild1348.312ms, native BLOB101B and reference JSON50004B are diagnostic
results; [raw phase measurements](phase-320.json) retain every per-generation
sample and the synthetic fixture path. Native completion still creates no new
editor documents or inspections after the first generation.

Owner: Tandemlog implementation work, coordinated with Lee. Impact: growing
warm commands and potential retained-reference amplification under offline
history reshaping. Exit: measured per-phase scaling at20/80/320/640 with bounded
disposable structures, exact replay/Undo/ownership and preserved canonical bytes.
Revisit before claiming long-history performance acceptance or promoting the
shared-history preview. Broad memo flush after pending errors is safe but may
increase warm cost. Checklists and the preserved UX/security queue remain next
authorized feature work.
