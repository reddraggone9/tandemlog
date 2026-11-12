# Release performance gate

## Where timing is judged (ADR0033)

[ADR0033](decisions/0033-controlled-reference-performance.md) (Lee, 2026-10-25): absolute
and both history-growth budgets are judged only on the controlled reference host, Bender
(registered as `farnsworth`, its name until 2026-11-08), under the reference caps and with
no hardware multiplier. Hosted CI keeps correctness, build, replay, integrity, source,
fixture and completeness checks mandatory; hosted timing is advisory and never reruns. The
required `reference-performance` job verifies the committed bundle in
`evidence/reference-performance/current/`; missing or stale qualification fails it and never
counts as a pass. Procedure: [operating protocol](performance-reference-qualification.md).

## The gate rule (Lee, 2026-10-31)

Goal: much faster qualification runs and far fewer false failures and investigations,
with no significant added risk of missing a real, user-facing slowdown.

1. Each action gets ONE sample per shape (dense-1, dense-2, dense-food), with no warmups.
2. That sample is judged against the existing median limits: absolute `medianMs`, and
   growth `maxMedianRatio` × small sample + `medianAdditiveMs`. No budget number changed.
   `maxMs` and the maximum-growth fields no longer decide the gate. They stay in
   `limits-v1.json`, unchanged and marked non-deciding, because keeping them is the smallest
   honest change: the file's diff shows no budget moved, and restoring them needs no
   reconstruction. Only Lee may change these numbers.
3. `run_gate.py` collects every first-pass miss, then, in the same invocation with no agent
   or manual step, reruns each one once. Actions chain within a family, so the whole family
   reruns in a fresh process with a fresh copy of the sealed workspace
   (`benchmark rerun-family`), under the same binary, fixture and limit bindings. A growth
   miss reruns both sides of its pair and judges the pair from the rerun values. One process
   serves every label in its family and shape. Only labels that missed the first pass are
   judged; a different label over its bound in a rerun is recorded in `notJudgedOverBound`
   and decides nothing.
4. The run fails only when the same label misses both times. That double failure is simply a
   real failure for a person to look at; there is no further automatic or official route.
   The result keeps every first-pass and rerun value, `firstPassFailures`,
   `firstPassFailureCount`, `reruns`, `rerunJudgments` and `confirmedFailures`, and
   `reference_receipt.py verify` reports first-pass misses in its output and as a CI warning.
5. Correctness, coverage, execution and binding checks are unchanged and terminal: a failing
   first pass or a failing rerun process stops the run with no rerun. Quiet admission, bounds
   and cleanup are unchanged. Hosted and measure-only runs take no rerun; their timing stays
   advisory or calibration-only.

The verifier recomputes the rerun plan and every judgment from the retained samples, binds
every first-pass and rerun sample to its raw log and sealed fixture contract, and refuses a
result that was produced under another gate rule. Code: `gate_policy.py`, `run_gate.py`, `reference_receipt.py`; tests:
`tool/test_single_sample_gate.py`.

This replaces the in-invocation noise retry, the official rerun, the borderline band and the
disk-stall resample for new qualifications. Results sealed under those rules keep their
original meaning; see [results under earlier rules](performance-reference-qualification.md#results-under-earlier-rules).

What it gives up, knowingly: a single sample cannot see a slowdown that only appears in some
repetitions unless it lands on both passes, and a slow small-side sample widens its growth bound
for that pass. Replay of retained q2–q5 (2 warmups + 5 samples each, so every repetition position
stands in for a single sample) found about 2.3 first-pass misses per run and no shared
index-0 miss across distinct runs. A rough extrapolation using matched
repetition positions gives 2.60–5.68% model probability of any double failure per run,
assuming exchangeable observations, independent passes and independent labels. This is
not a confidence interval, measured quiet-host failure probability or proof of noise.
Repetitions within four processes are not independent fresh-process confirmations;
first-use state, shared small-side samples and common host pressure limit the model.
The eight `startup.*` labels showed no historical single-sample miss; future risk is not zero.
The most exposed labels are `sync.peerTask.whileFood.storageAdmission` and
`recurring.recomplete.nativeChecklist` growth, each about a 10–14% single-sample miss.

Quiet admission matters more now. Under the reference caps, a whole single-sample pass took
about 3.4 minutes against about 12 for seven repetitions. Two such non-qualifying runs on this
host without admission, overlapping other work, had 46 and 47 first-pass misses with no label in
common, against about 2 expected. A third, loaded by unrelated analyzer runs, double-failed
`dense-food:agent.write.taskComplete` at 508.7 and 502.1 ms against 500; that label ranged
458.7–492.1 ms over all 28 repetitions of the admitted q2–q5. Its roughly 5% headroom makes it the
likeliest real double failure.

The rule came from the first two qualifications of `9b06f97` (requests `15e16069` and
`1055af47`, both retained and failed), which missed only maxima and took two causal diagnoses
that established no fix.


The standalone Dart executable measures production storage, application commands and readmodel queries in AOT release mode. It uses only generated public synthetic workspaces. There is no argument for a user workspace, mapping, profile, title or fixture import. Native text and SQLite libraries, compiler, package configuration, source and fixture bytes are sealed in the result.

The three versioned shapes share the SAME first 1,320 historical physical records, three writers, entity IDs and current Task/Food values. The dense-1 baseline and dense-2 Task-growth shape retain their integer specifications and three physical owners. Prospective fixture schema v2 (exact completion instants) gives Task-growth edits a separate normalized logical namespace, attributed to those same owners, so the continuing writer retains identical next logical IDs and completion order across shapes. Previously sealed v1 canonical bytes and evidence remain immutable; v2 is freshly generated and sealed, not a rewrite of accepted fixtures. An additive dense-food shape uses {baseRecords: 2640, growthKind: food}, normalized to the closed CLI food:2640. Dense-2 adds 1,320 bounded Task Notes edits alternating with exact restores; dense-food instead adds 1,320 Food brand edits alternating with exact restores on existing containers, each carrying its actual observed creation reference. Neither Food contents nor deletion state changes. All three then receive production native-text initialization and the same native checklist/recurring operations. Enforce equal initial-prefix hashes, full current-state digest, Task rows and Food container counts before treating this as history-only scaling. Actual record, effect and row counts are recorded. Both pairs must prove their growth module: Task effects grow only in dense-2, Food effects grow only in dense-food, and the other module's effect count stays equal to the baseline. Missing, unknown or mismatched growth claims fail correctness. The additional pair closes Food-own-history coverage; it does not test a growing number of recurring descriptors. Scalar synthetic IDs and strings are deterministic; production native actor allocation may vary between fixture generations. Generate each fixture once, seal its actual bytes, and reuse exactly those bytes for a timing rerun. Profiles and workload copies are always fresh; existing output is refused.

Each action takes one measured observation per shape with no warmups (Lee, 2026-10-31; earlier receipts have two warmups and five samples), and nothing is discarded as an outlier. Each recurring repetition starts a separate fresh workspace/profile copied from the same sealed fixture and creates equivalent new parent inputs. Actions within that repetition accumulate canonical descriptors and native owners; later repetitions do not retain the previous repetition's history or owners. Newly allocated IDs and actors can vary. Cold startup means a fresh profile, not a flushed operating-system cache. Warm startup separately reports canonical/cache proof, cache restore and Task attachment. All three shapes must report the same 257 expected actions (the original146,45 converted-existing,33 Food-cardinality,2 confirmation-inclusive Food,6 first-point cases,12 Food-product cases,2 Food Move some cases 8 agent CLI calls,2 writer300 refreshes and1 Activity read derivation). Both comparisons (dense-1 to dense-2, and dense-1 to dense-food) retain their own per-action bounds and results. Versioned per-action paired rules check the large-size sample against the small-size sample multiplied by a fixed ratio plus a fixed additive allowance; report both sides and the computed bound. A paired shape/coverage failure is correctness failure.

`limits-v1.json` contains the initial calibrated AOT storage/application/readmodel regression bounds, pinned by literal SHA in the workflow. The initial calibration combines current-source local and hosted Ubuntu observations, two warmups and five measured samples on each of the three shapes. Ordinary per-action median/maximum ceilings retain roughly 50% observed headroom, rounded to 5 ms with small-operation floors, and every ordinary maximum was additionally capped at 100 ms during calibration (a historical calibration cap, not a responsiveness target; see [What sets acceptable latency](#what-sets-acceptable-latency-lee-2026-10-27)). Both history-growth pairs enforce 1.25× + 3 ms for the ordinary labels; their 1.40× + 5 ms maximum rule is retained but no longer decides. The eight startup labels have separately calibrated size-specific absolute ceilings. Their existing paired guards remain unchanged at 2.25× + 100 ms (and the non-deciding 2.50× + 200 ms maximum): loose historical proof-growth bounds, without a history-independence claim. Startup remains history-scaled; these limits do not excuse avoidable work. Finite calibration is not a percentile guarantee. Actual native UI paint/interaction acceptance is separate and remains unresolved. Loosening an activated limit requires Lee's explicit approval; tooling has no automatic baseline-update switch.

A correctness, coverage, source, tool or fixture failure is terminal. Timing follows [the gate rule](#the-gate-rule-lee-2026-10-31); never retry until green.

This executable does not measure editor mounting, sidebar response, widget paint, keyboard input or first visible rows. Section preferences and projections are labelled storage/readmodel measurements. The actual release GUI needs a separate isolated GTK/Xvfb job with owned-window input, visible-pixel acknowledgments, finite cleanup and explicit capture overhead. Windows offscreen input probes are not substituted for that job.

Run `python3 tool/test_performance_gate.py` for gate policy and receipt regressions. `run_gate.py --measure-only` collects calibration observations and never claims release acceptance. A release invocation enforces the exact reviewed workflow-pinned limits; unbound or inactive limits fail closed. The calling workflow must impose the documented finite compile/runtime/resource bounds and retain every result and log.


The runner accepts no caller package configuration, source override or alternate limits file. It reads the repository package configuration, rejects a `tandemlog` root that resolves outside that checkout, creates its own fresh source fork, and changes only that package root URI and normalizes its already-validated effective library URI to lib/. Every copied file retains identical original and compiled SHA-256 values. The standalone storage closure needs no Flutter notifier/platform shim: the rewrite and shim allowlists are empty. Reachable Flutter UI imports, missing/escaping project imports, source extraction changes, changed dependency files or changed SDK kernel inputs fail closed. Production `LocalLogFolder` and `LocalDurability` implementations remain byte-exact, including append/flush semantics. A release invocation must execute tooling from the same checkout and supply the workflow's expected SHA-256 for the fixed versioned limits file.

The shared validation workflow has a separate required Linux performance job; it is also required by signed-candidate checks. Its 65-minute whole-job bound includes native setup; the gate runs as the existing runner UID in a transient system-manager service with 55-minute runtime, 6 GiB physical-memory cap, no swap, 2 CPU quota and 128-task cap, plus bounded compile/generation/workload children. An outer timeout and exit/signal trap stop that exact service; actual cgroup bounds are recorded and required before release measurement. It retains preflight stderr/stdout, compile/generation logs, the timing result, paired comparisons, source/tool/fixture seals and per-size fixture contracts, including failures. Synthetic workspace payloads and local SQLite profiles are excluded from uploaded artifact paths. The workflow pins the limits file's exact SHA and runs the gate with `--hosted-advisory` (`tool/performance/run_ci.sh`): hosted correctness, bindings, coverage and caps decide the job, while hosted timing misses are recorded but never fail it or rerun. Timing acceptance comes only from the reference bundle that the separate `reference-performance` job verifies; measure-only and hosted observations never satisfy it. Food editor/controller construction/cancel/paint is explicitly a native-UI coverage gap; no storage-only number substitutes for it.

The initial calibration showed that the pre-existing task.title/notes/titleAndNotes and task.editorOpenCancel labels select the fixture's inherited recurring successor with a copied checklist, rather than an explicit Task birth. Those labels and observations are retained and their target is now asserted. Separate explicitTask.* cases add native-born ordinary Task title/Notes/both Save, Undo, editor preparation and complete native cancellation; they do not replace the inherited cases or excuse their scaling failures.

A manual `ci.yml` dispatch can set `calibrate_performance` to run the hosted job with `--measure-only` instead. This collects the same source-bound observations with releaseGateAccepted=false; it cannot satisfy release acceptance. Signed-candidate validation explicitly fixes performance_calibration=false, and normal push/PR CI uses `--hosted-advisory`. No calibration switch is exposed by candidate or promotion workflows.

## Initial performance acceptance

Choose each action's timing boundary and budget from its intended responsiveness
before accepting the implementation. Do not measure a slow first implementation
and add headroom to turn it into an approved baseline. A passing storage-only
measurement does not establish visible responsiveness.

### What sets acceptable latency (Lee, 2026-10-27)

Responsiveness sets what is acceptable, judged in human time first: an ordinary
action should feel immediate to the person using it. The "100 ms" figure in
earlier documents was Lee's rough guess at an upper limit for a local save, not
a target, objective or ceiling, and is no longer used as one. The calibrated
regression bounds in `limits-v1.json` (measured cost plus headroom) are the
enforced contract; they keep fast actions from drifting toward any such
ceiling. Spend optimization and energy attention where cost actually adds up:
idle and background work (wakeups, polling, rescans, startup replay) and
per-action cost that grows with history. Do not spend effort shaving interactive
actions that are already fast and flat. This framing does not loosen any
existing calibrated limit.

Initial acceptance must use realistic public synthetic fixtures, representative
existing/converted entities, first-use and steady-state samples, and relevant
history-growth comparisons. Reconcile exclusive wall-time costs, state timing
and instrumentation boundaries, and review repeated scans, decoding, validation,
SQL work and refresh/render work for redundancy. Optimize demonstrated misses
within existing integrity and durability guarantees. A genuinely necessary
exception requires Lee's informed approval of the measured cost and guarantee
tradeoff; calibration must not approve it automatically. Existing limits stay
in force until Lee explicitly approves a change.

Startup and bulk actions may need distinct, justified budgets and visible
responsiveness checks. Define the operation size, useful-progress endpoint and
UI blocking boundary explicitly; neither category is a blanket exemption.
Regression prevention follows this initial acceptance, preserving the accepted
requirements rather than legitimizing a slow starting point.

## Maintaining action coverage

Performance coverage is part of implementing a new or materially changed user
action, including changes to its refresh, Undo, background maintenance or editor
lifecycle. Update the same change with:

- Registered metric IDs and the action inventory in coverage-v1.json, naming the
  production entry point, target/fixture, timing boundary and remaining gaps.
  Keep existing case IDs and their meaning stable; do not rename or drop a slow
  case to make a gate pass.
- Correctness assertions for the acknowledged result, relevant Undo and canonical
  integrity. Benchmark work must use public synthetic data and exercise existing
  imported/converted entities when those are supported.
- Explicit versioned per-case budgets for every applicable fixture shape, plus
  matched-history growth checks where history can affect the path. Investigate
  redundant work before proposing a larger budget. Only Lee may approve loosening
  an existing limit; neither calibration nor a new metric name bypasses that rule.
- Faithful release-mode UI-path coverage for user-facing behavior: use the actual
  callback, editor/capture lifetime, refresh/maintenance and visible acknowledgment
  as appropriate. Keep storage/application and input-to-visible-response budgets
  distinct. A storage-only case leaves a documented UI gap, not UI acceptance.

Before merging and again before release, a reviewer must reconcile the actual
Task/Food controls, shortcuts and background-triggered work with that inventory.
Check new paths, renamed/removed actions, production API references, representative
targets and declared gaps. CI cannot discover every possible unregistered action
or prove that a descriptive UI reference still means the same behavior. Do not
call an inventory complete merely because its registered cases pass. Native UI
coverage that is not implemented or has not passed remains explicitly pending.

The policy tests compare the registered IDs with every fixture's absolute
budgets and both growth-rule sets. Runtime evaluation also rejects missing or
unknown observed cases, invalid values and incomplete sample sequences. A stale
registered ID therefore cannot be silently skipped by a workload. These checks
complement the human inventory review; they do not replace it. Correctness and
coverage failures are terminal; timing follows [the gate rule](#the-gate-rule-lee-2026-10-31).

## Cost accounting

A passing total is not an explanation of its cost. Investigate repeated scans,
allocation, validation and database work even when the ordinary-action target
is met. A breakdown must reconcile mutually exclusive wall intervals plus an
explicit unclassified remainder to the same measured action. Identify nested
intervals, overlapping asynchronous work, scheduler/await time, FFI boundaries
and instrumentation overhead; do not sum inclusive component medians.

The first RC4 repair report was incomplete: its read timer combined many
provider calls and asynchronous scheduling, while verification ran elsewhere.
Its BEGIN-to-COMMIT transaction timer included Dart validation and projection
between SQL calls, so it did not measure SQLite engine time. Compare one append
with the actual file/byte/syscall counts of the read workload, and distinguish
API wall time from storage service time. Preserve traces and explain residual
gaps before presenting a reconciled cost breakdown. Storage accounting still
does not measure input, widget construction, layout or paint.

A history-growth failure or near-miss means some work scales with canonical
history inside one ordinary action. Find it by comparing dense-1 and dense-2
profiles of the measured window only (CPU samples filtered to the action's
start/end, never in a qualifying run), then guard the fix with a work count
rather than a wall-clock test. `sync.peerTask.whileFood.storageAdmission` is
the worked example: a delivered peer Task re-sorted and re-validated the whole
Task input and scanned every canonical row for each new event's tag
references; see [peer Task delivery as a monotonic delta](task-latency-repair.md#peer-task-delivery-as-a-monotonic-delta).


Converted-existing coverage has separate metric IDs and provenance assertions.
The original inherited/new-native Task and historical Food targets retain their
contracts. Added converted Task cases use imported scalar Tasks3/6/9/18 for text,
metadata, completion, reopen, deletion, reorder, bulk and a checklist on an
imported parent. The paired Food case uses imported Food1000, a brand-only edit,
its exact creation reference and Undo; the small60 functional fixture explicitly
uses Food4 and cannot establish that native pairing. Imported-birth and owner
checks also guard the original historical Food selection. Native and storage
comparisons must record matching source, entity, pre-action heads/current state,
input sequence and native-owner lifetime. Fixture coverage remains distinct from
actual widget/input/paint coverage; no existing metric or accepted limit is
renamed, removed or relaxed by these additions.


The fixture-selection audit distinguishes fixed-target edits from first durable
activity on a newly derived entity. The inherited task.title family reuses one
target, so its single sample is now that target's first activity in the family
(earlier receipts warmed it first). The recurring family instead creates a fresh parent,
successor and copied items for every repetition: derivedSuccessor.titleAndNotes.save
measures the successor's first durable activity in every reported sample.
copiedChecklist.titleAndNotes.save measures the item's first durable activity
after the preceding parent Save and Undo protect its containing seed. The
oversized-descriptor correctness test separately covers a copied item's first
Save without that preceding parent activity; it does not establish a separate
timing distribution. None of these boundaries excuses slow first activity.

Remembered-section metrics time LocalSettings persistence only. They do not
include WorkspaceState publication or actual section navigation. Audit.open
ends after FoodStore/settings loading and excludes main occurrence maintenance,
workspace binding/publication and first useful paint. Checklist text cleanup
runs in finally outside the timed labels, so it is not a separately timed cancel
action. These gaps remain visible in coverage-v1.json until separately measured.


The separate food-cardinality500 family starts from a fresh copy of each original sealed shape and adds synthetic containers through the production API outside timers, requiring 500 active containers plus 3 deleted containers (503 total). Setup uses mostly unique names and explicit stock, retained, inbox and deleted cohorts. The original 191 metrics remain; 33 cardinality500.* metrics add imported Food1000 brand Save/Undo, single/group Food commands, views, matching and unmatched filters, and unchanged Food refresh. Mode and positive-filter results must contain exactly the captured cohort IDs and counts, without duplicates; these assertions run outside timers. Undo must restore the full logical state; Task values, original prefixes and peer bytes remain checked. Setup adds both containers and canonical records and allocates new IDs, recorded separately: this is current-state stress, not isolated cardinality causation or byte-identical per-family histories. These added cases are included in the active initial calibrated limits; their storage boundary remains distinct from actual UI acceptance.

A separate converted-food-confirmed family measures imported Food1000 brand Save and Undo through the same exact-receipt confirmation and real session Undo history callbacks as the app. These additive confirmedSave/confirmedUndo labels include work beyond the preserved backend-only timings; they still exclude widget preparation, publication and paint. Food500 expected mode memberships preserve the original input's retained and inbox cohorts. The failed inventory-only setup trial remains external evidence.

Six additive first-point metrics cover untouched successor tags, untouched copied checkbox, and mixed native title+Due+tag Save/Undo. Each case and repetition starts from its own fresh sealed-fixture copy before any successor/item own activity. Target/parent seed selection, actual native context, full ready/SQL replay oracles, exact row Undo and zero full-readiness on the supported ordinary path are checked outside timers. The mixed case owns its actual captured native session through Save and Undo. Retained153 measures the old positive full-fallback counter before repair. These additions do not claim every field combination or first delete/move timing, and cannot substitute for actual input-to-paint acceptance.

First-point full replay oracles run after the timed Save/Undo pair against separately captured immutable Save and Undo snapshots, row encodings and ready sets. Retained153 first Save precedes that replay; its Undo followed same-owner full oracles and is not a direct baseline for an adjacent app Undo. Those original observations remain retained, with no latency effect inferred from this boundary finding.


### Windows framework-action diagnostic

The separate windows-widget-qa.yml build pins the existing release-widget target and controller. The probe now requires the sealed public UI fixture:1,325 canonical records in three writer logs plus the manifest, with existing historical Task3. It creates settings-only local state for the already-enrolled synthetic writer and user, without seeding new tasks, enrolling another writer or priming the app projection. It retains native Save/closed-editor Undo, typed atomic records, original-prefix and nonowner preservation, semantic restoration and the post-close full audit.

The input title is Benchmark paired title, matching the paired Linux stimulus. Text still enters through the explicitly mocked framework channel; this is not native keyboard/IME evidence. Optional foreground probing waits for a run-bound controller arm, checks the actual foreground process before and after each action, and requires1280x860 logical pixels. Input-return, state-ready and post-frame fields are nested cumulative measurements; the delivered engine-frame slices are separate. App-mount readiness excludes process bootstrap, fixture setup and the controller wait. A single diagnostic sample does not establish median/tail or all-action acceptance, hardware renderer attribution or compositor presentation. These qualifications and the existing enforced budgets remain unchanged.

The fixture controller reads only the public contract and four canonical files. Local profiles are not migration inputs. The generated Flutter plugin files are pinned as literal bytes across Windows worktrees; unexpected tracked changes still reject packaging, with bounded filenames/diff and raw working/Git byte hashes for diagnosis. This does not authorize a generated-source exception or release-gate waiver.


Optional Windows provider-cost diagnostics
The existing release-widget probe accepts explicit --cost-trace through its
controller. The default remains uninstrumented. A LocalLogFolder subclass
preserves range/bounded/replacement/tail capabilities and delegates production
durability; its common-clock raw spans include provider list/read/range offsets,
returned bytes and append/create/atomic-write-plus-barrier intervals. Action
windows are correlated by timestamps, not invented causal async parents.
Inclusive/overlapping intervals must not be summed; provider await is not kernel
I/O service time. Optional profile observation now adds synchronous SQLite API,
transaction/body/BEGIN/COMMIT/ROLLBACK, queue-wait, semantic validation and refresh
intervals; the native owner adds JSON/FFI/native API intervals. The pinned SQLite
payload omits tracing, so no engine statement counter or engine-only duration is
claimed. Diagnostic database views preserve the original connection, statements,
hooks, parameters, results and errors and do not send SQL text to the observer.
Direct raw/cursor SQL, write-versus-flush, allocation and render/scheduler details
remain explicitly unmeasured. Bounded trace overflow preserves the operation result/error
and invalidates the diagnostic after actions, rather than turning a successful
append into a failed Save. Packaging pins this additional Dart source. These
diagnostic samples cannot replace ordinary release or native visible-response
acceptance, and no time/growth budgets change.

The standalone runner exposes --diagnose-costs only together with --measure-only.
It instruments every ordinary action through the same production paths, retains
per-sample raw JSON traces under the disposable workload's cost-traces directory,
and requires complete, exactly reconciled interval partitions. Raw trace files
are written after the action timer stops. These instrumented timings can never
satisfy release acceptance. Default/enforcing runs remain uninstrumented; action
IDs, sample counts, first-use fixtures, history-growth comparisons and versioned
budgets are unchanged. See task-latency-repair.md for the SQL-hook limitation,
remaining attribution gaps and exact-row Task snapshot representation memo.

<a id="food-product-prospective-coverage-2026-10-28"></a>
## Food-product coverage (added 2026-10-28)

Twelve additive `food.product.*` labels cover production implicit-product edit
(name/brand/size/links/minimum), mixed two-product/container bulk Save,
rename-to-existing merge, three-container Add linked to a renamed product, and
two-line purchase import (dry run, commit, idempotent retry and Undo). Each
repetition starts with a fresh sealed fixture copy. Writes include exact receipt
confirmation and real session Undo history. Full catalog/aliases/purchases and
container restoration, active-state reopen, fresh-profile replay, Task isolation
and original canonical prefixes are checked outside timers. Previous232 labels
and bounds remain unchanged.

Before any new measurement, every new label receives15ms median/20ms maximum
on all3shapes, taken from existing Food details/add/Undo bounds. Both paired
ordinary rules remain1.25x+3ms median/1.40x+5ms maximum. These are intended
responsiveness bounds, not a measured baseline or qualification. The import is
explicitly two lines/four containers (one matched historical hand entry and three
new Inbox containers), not a maximum500-line import allowance. Native widget,
input, publication/paint and larger bulk/import/merge-chain timings remain
separate gaps. These labels are part of the 257-label inventory every current qualification measures.

<a id="food-move-some-prospective-coverage-2026-10-29"></a>
## Food Move some coverage (added 2026-10-29)

Two additive labels, `food.moveSome` and `food.moveSome.undo`, cover the Food
row ⋮ **Move some…** action: the production Location `changeDetails` the page
sends through `onDetails`, moving the first two current containers of a
three-container row (the imported container plus two added to its row outside
the timer) into their own row, with exact receipt confirmation and real session
Undo. Each repetition starts with a fresh sealed fixture copy. The split, one
Undo entry, active-state reopen, full restoration of the three-container row and
Task isolation are checked outside timers. Previous244 labels and bounds remain
unchanged.

Before any measurement, both labels receive15ms median/20ms maximum on all3
shapes, equal to the existing Food details/Undo and `food.product.bulkEdit`
bounds, because Move some is the same one-action Location edit. Both paired
ordinary rules remain1.25x+3ms median/1.40x+5ms maximum. These are intended
responsiveness bounds, not a measured baseline or qualification. The dialog's
open, typing and paint, and moves of hundreds of containers, remain separate
gaps. Both labels are in every current qualification.

<a id="agent-cli-prospective-coverage-2026-10-29"></a>
## Agent CLI coverage (added 2026-10-29)

Eight additive `agent.*` labels cover the headless agent CLI
([agent interface](agent-interface.md) section 8): `agent.read.coldOpenTasksList`,
`agent.read.foodList`, `agent.write.taskComplete`, `agent.write.textEdit`,
`agent.write.textEditUndo`, `agent.dryRun.bulkEdit2`,
`agent.dryRun.purchaseImport2` and `agent.write.purchaseImport2`. The
`agent-cli` family gives every repetition a fresh sealed fixture copy, joined
outside timers by `init` with a fresh agent profile (its own writer). Each label
times one whole in-process `runCli` call, as an agent's tool call experiences it:
argument parsing, the profile lock (reads: a disposable profile copy),
`WorkspaceSession.open` (read-only folder for reads; write mode with open-time
occurrence migration otherwise), the registry command, close and JSON rendering.
Targets are imported scalar Tasks3/6/9/18 and the imported Food1000 product for
the matched receipt line; the import is the same two lines/four containers as
`food.product.import`. Outside timers: listed IDs and rows; workspace and agent
profile byte-identical after reads and the copy-on-write bulk dry run; canonical
bytes unchanged by the import's own dry run (it opens the profile for writing);
returned revs match a later show; whole-action Undo of the completion and the
timed text Undo restore the shown task; the audit installation then replays the
agent's history with Tasks unchanged and exactly three new purchase-linked
containers. Previous244 labels and bounds remain unchanged. (Merged with the
Food Move some labels above: 256 labels in total (including2 writer300 refreshes), one combined limits digest.)

Budgets were declared before any `agent.*` measurement from the intended
human-time response of one agent tool call, identical on all3shapes: reads
400ms median/600ms maximum, single writes and whole-action Undo 500/750, dry
runs and the two-line import 700/1000. Every label contains a complete,
history-scaled workspace open and close (the same proof/replay the app's
`startup.*` labels bound), so both growth pairs use the existing startup-class
rule, 2.25x+100ms median/2.5x+200ms maximum. Applying the ordinary 1.25x+3ms
rule to a call that includes the open would fail by construction from the
existing startup budgets alone (dense-1 versus dense-2 warm history open
270 versus 450ms). The per-action store work stays guarded under the ordinary
rule by the existing labels for the same store paths (`task.complete.*`,
`converted.task.title.*`, `task.bulkEdit.*`, `food.product.import.*`).

Not covered in-process, and recorded as gaps in coverage-v1.json: process
start, Dart AOT runtime boot, native text/SQLite library loading and stdout of
a real `tandemlog-cli` run; packaged-binary timing (Flatpak second command,
Windows installer/ZIP) and Windows zone lookup (calls pass `--tz`); MCP framing;
lock waits with a concurrent GUI; commands without their own label (they share
the timed open/close boundary).

The app's open sequence moved into `WorkspaceSession.open`. The timed startup
labels keep their per-phase store calls (history open, Task attach, Food
attach), which are the session's own calls in the same order, so
`startup.*.history`/`taskAttach` keep their meaning. Outside the timers, the
startup family now opens the same profile through `WorkspaceSession.open` and
requires identical Task/Food state and no canonical writes. Folder listing and
the open-time occurrence migration remain outside the startup labels (the
existing startup gap); `agent.*` calls time them end to end.

### Bounded cache proof overlap and installation-cardinality refresh

Clean close now prepares the bounded decoded-cache payload/checksum on a pure
worker while sealing the independently compared Task projection. Each proof is
still invalidated/consumed before exposure; publishing either or both independent
proofs after a crash cannot authorize unfinished intent. No canonical bytes,
receipt generation, digest algorithm, admission checks or budgets changed.
Concurrent opens share only an *in-flight* opaque verification receipt when
payload bytes, digest and complete binding are exactly equal. No completed result
or path/stat-based authority is retained.

The additive `writer300-refresh` family registers two labels under the existing
unchanged Tasks/Food refresh budgets and ordinary growth rules. A fresh copy of
each sealed shape receives enough deterministic synthetic joined installations
to have exactly300 physical histories; every join must be admitted before the
timers. Every repetition checks unchanged full Task/Food values and canonical
inventory; reopen and original-prefix checks still apply. This is writer-count
stress, not isolated history causation; actual GUI scheduling/paint stays separate.
The manifest owner bound is unchanged. All prior254labels/limits are retained.

### Read-only Activity log

Before first measurement, `activity.read.derive` adds a 15ms median / 30ms maximum
readmodel budget on all three shapes and the unchanged ordinary paired-growth
rules. It builds published rows and current installation labels once per revision,
sorts by recorded logical occurrence clock, and checks count, uniqueness, order
and canonical immutability. This adds a 257th label; all previous 256 absolute and
growth bounds remain byte-value unchanged. It does not time first paint, scrolling,
details or incoming-history visible refresh; native workflows must assess these.
No work runs while the dialog is closed. No physical occurrence/skew correction
or missing actor-user reconstruction is claimed.

## Native cold process start to first usable list (Lee 2026-11-03, coverage correction 11-05)

**Goal:** show a usable Task list promptly while opening the shared Task + Food
workspace. **Budget remains 1,000 ms median**; only Lee may change it.

### Workload and correctness

`tool/performance/native-cold-start-v1.json` specifies 2,000 synthetic Tasks,
220 Task edits and 560 completions, plus 530 Food add actions (17 multi-adds),
104 container edits, 92 removals, 148 product edits and eight purchase imports
with 34 lines. Four writers use the production Task/Food APIs, one action per
record. The synthetic reference shape contains **3,667 records / 6,419,277 bytes
in four files** in the diagnostic fixture, with 522 active containers in 483 Food rows, 551 products and 34
purchases. Random fixture identities can change byte lengths and grouping; every
measurement retains its own authoritative receipt. The seeded Task projection
contains 2,000 Tasks plus one person (560 completed Tasks remain in that
projection).

The seeder independently checks planned action-family counts, expected active
inventory, purchases and writer count through a read-only production reopen and
full integrity audit. The native run verifies the complete Task cache and actual
warm-proof reuse. It also requires `TANDEMLOG_FOOD` counts to exactly match the
nonzero receipt on every strict and warm launch. Food counts are emitted **after**
the first-list marker, outside the timer; Food admission itself remains inside
workspace opening. Food attachment under 1 ms is not total Food startup cost.
A Task-only fixture or missing/mismatched Food evidence cannot satisfy this case.

### Timing boundaries and source binding

`TANDEMLOG_FIRST_LIST process_ms` ends at the UI-thread post-frame callback for
the first usable Task list. It includes process/engine startup, workspace open,
Task view setup and UI build/layout/paint submission. **It does not establish
raster completion, GPU presentation or physical screen visibility.** `ms` starts
later, at app-state creation. Logged `settings/folderList/history/tasks/food/
migration/bound` values are cumulative wall checkpoints, not CPU attribution.
Subtract adjacent checkpoints for their intervals; do not sum them.

Each series starts one new **uncached/strict** process (reported, not budgeted),
then five new **cold processes with warm persisted caches**, following verified
normal close and seal reuse. OS page cache is not flushed. Thus "cold process"
is not "uncached history" and neither is a phone measurement.
`native_cold_start.py measure` builds a clean, source-bound GTK release under
Xvfb on the registered reference host (Bender, registered as `farnsworth`; ext4). The result retains the
fixture receipt, samples and load. `verify` checks the exact relevant source,
host, unchanged budget/shape, Food correctness, reuse and recomputed median.
The committed result lives in `evidence/native-cold-start/current/`, and the
`reference-performance` job runs `native_cold_start.py verify` after the AOT
receipt check, so a relevant-source change needs a fresh native measurement as
well as a fresh AOT qualification. The native case has no automatic quiet-host
controller; loaded-host exploratory runs below are **not** the controlled AOT
qualification, and neither replaces signed-candidate acceptance.

### Investigation and bounded improvements (11-05)

[Diagnostic samples](../evidence/startup-investigation-20261105/diagnostic-summary.json)
are same-pristine-workspace A/B runs on a loaded host (about 5–7 load), not gate
acceptance. Warm medians were **630→520 ms** and **540→510 ms** in two paired
series. Independent per-writer tail checks fell from ~42–45 ms to ~8–9 ms;
open-time migration's candidate-discovery refresh fell from ~23–32 ms to <1 ms.
Do not add these component medians to explain the entire process-median change:
noise, scheduling and other work vary between samples.

History opening includes SQL/store restore, asynchronous provider operations,
isolate decoding, rebuilding bytes, semantic validation and projection commits.
In the first paired series, stored-row SQL was ~12–16 ms, isolate decode ~51–56 ms,
byte rebuilding ~23–28 ms and validation ~105–107 ms. Task semantic validation
(~49–51 ms) and Food admission (~18–20 ms) are **inside** that validation interval,
not additional terms. Nested restore laps likewise cannot be added again to
outer open intervals. These are wall measurements, not CPU samples.

Food admission is directly measured; the Food share of shared SQL/decode/rebuild
is not separately attributed. The synthetic logs contain 882 Food-bearing records
(24.1%) and 1,837,099 Food-bearing bytes (28.6%). Those proportions are measured
counts, **not an assertion of equal CPU-cost shares**. An earlier private estimate
of ~40% shared Food cost was unsupported and is superseded by this distinction.

The two contained changes preserve the trust boundary:

- Tail checks run in batches of at most four and settle all started operations
  before strict fallback, preserving deterministic seal order and every check.
- Only the deferred app-open migration uses already-loaded candidate discovery.
  Each candidate still refreshes before planning, commands recheck snapshots and
  unified writes recheck canonical revisions/admission. Ordinary/CLI migration
  and workspace refresh retain their discovery refresh. Newly arrived candidates
  absent from the loaded projection are handled by the app's mandatory importer
  reconcile (`ForegroundImporter.start` requests one immediately, plus watcher
  hints and fallback); no stale migration is permitted to overwrite peer Due.

Bound→post-frame was ~61–89 ms. A bounded Task-only control at 150 versus 2,000
Tasks measured ~54–60 ms for the first full UI build/layout/paint, while Task
projection was ~0.2–0.9 ms versus ~2–3 ms. The lazy list does not build every row.
This supports leaving the already-fast list logic alone; it is not a CPU profile
of every widget. Corresponding raster durations (~7–18 ms) occur beyond the
marker. FrameTiming's vsync overhead may overlap history opening and must not be
added wholesale to the bound→post-frame interval.

### Current acceptance and limitations

The former **420 ms result and candidate 42111287310 describe the Task-only
shape**, not the corrected mixed case. They remain historical evidence, not
current mixed-workload acceptance. The first fresh mixed native measurement, on `7e7b028`, passed at 520 ms median (uncached first launch 2,500 ms; 480 Food rows in its receipt). After the Linux runner follow-up `e930f31` the case was measured again: **500 ms median** (500, 490, 500, 500, 500 ms), uncached first launch **2,550 ms**, receipt 3,667 records / 6,419,498 bytes / four writers and 522 active containers / 477 Food rows / 551 products / 34 purchases; every measured launch matches its own receipt. Food row counts differ between fixtures because generated identities affect selection and grouping; no sample is relabeled. This is the source-bound native case, not the controlled AOT qualification or signed-candidate/lab acceptance. See the committed receipts for exact boundaries and provenance.

Off-UI-isolate opening remains deferred: SQLite/store ownership and Android SAF
channels make that a larger safety-critical change. Decoding already uses worker
isolates; validation/commits and the first full frame still occupy the UI thread.
The bounded findings do not justify a broad rewrite or claim perfectly smooth
startup. Phone after-history-store timing remains unmeasured (keyguard blocked
an earlier attempt); no phone was accessed during this follow-up. Desktop
software-rendered figures cannot be promoted to phone numbers.

## History

Dated measurements and fixes kept for their reasoning. They are not current procedure; results
under earlier gate rules keep their own meaning ([results under earlier rules](performance-reference-qualification.md#results-under-earlier-rules)).

### Agent CLI first measurement (2026-10-29)

First local `run_gate.py --measure-only` observation (Farnsworth, the
reference unit caps, ext4 output, all252labels, 2 warmups/5 samples; advisory,
not qualification): correctness, pins and both growth pairs passed, every
previous label met its limits, and only `agent.*` absolute budgets missed.
Median/maximum ms:

- dense-1: tasks list 571/573 (miss), food list 308/317, complete 324/341,
  text edit 314/314, Undo 313/319, bulk dry run 717/727 (median miss),
  import dry run 305/309, import 310/316.
- dense-2: tasks list 786/791, food list 518/522, complete 546/566, text edit
  524/565, Undo 525/570, bulk dry run 1042/1139 (all misses); import dry run
  509/518 and import 513/518 pass.
- dense-food: tasks list 833/842, food list 559/565, complete 564/566, text
  edit 567/571, Undo 566/573, bulk dry run 1086/1151 (misses); import dry run
  554/583 and import 565/587 pass.

Phase probes attribute the misses to redundant work, not to the commands'
store actions: (1) the warm history open is 165/275ms on dense-1/dense-2, the
same as the app's warm startup; (2) every `TaskStore.close` re-seals the warm
Task cache proof, 135/218ms, and on reads and the bulk dry run that seal goes
into a disposable profile copy that is deleted immediately; (3) `tasks list`
spends about290ms in the command because `people()` re-reads and JSON-decodes
all visible Task rows (`TaskStore.rows`) once per listed task, for both the
JSON and the eagerly rendered text form (`food list` takes 2ms); (4) the bulk
dry run's shadow open is a cold full replay (530/770ms) because `_rebind`
points the copied profile at the shadow folder, whose different location key
misses the warm cache; the command and both state observations take about 45ms.
Options, none applied here: skip the cache seal when closing read-only or
disposable sessions; compute the people map once per call and render only the
requested format; keep the real location for the copy-on-write overlay so the
warm cache applies; reduce the history-scaled seal and proof for write calls.
Budgets are unchanged. Fresh enforcing qualification is pending, and the
private reference controller's hard-coded limits digest must be re-registered.

### Agent CLI fixes after the merge (2026-10-29)

Applied on `vex/agent-interface-20261029`, budgets unchanged:

1. Agent reads and dry runs run on a disposable profile copy and no longer seal
   the warm Task/decoded caches at close (`close(sealCache: false)`); the app
   and agent write calls still seal (default unchanged).
2. `tasks list` decodes Task rows once (people map and view from one read) and
   builds its text form only when asked.
3. The copy-on-write dry-run overlay reports the real folder's location, so the
   profile copy keeps its workspace binding and warm decoded cache (no cold
   replay).
4. Write calls: the Task cache seal compares live and validator rows exactly
   (type-strict; NaN and -0.0 refuse) instead of digesting both, and the
   decoded cache seal hashes and stores its JSON UTF-8 bytes directly (same
   TEXT value and proof). A planned commit opens the real workspace while its
   dry run runs on the profile copy (started after the copy exists; the
   command still runs only after the plan check).

The purchase-import labels changed meaning before these fixes: after the
agent review, `purchases import` follows the general plan contract, so the
timed commit re-runs the dry run under the identity lock and then commits
(two workspace opens), where the first measurement timed one open.

Local measure-only gate at `041cfed` (fixes 1–3; reference unit caps, ext4,
all254labels): correctness, pins and both growth pairs passed and every
non-agent label met its limits. `agent-cli` family resampled at `700d456`
(fixes 1–4, same caps and fixtures, 2 warmups/5 samples), median/maximum ms,
before → after:

- dense-1: tasks list 571/573 → 183/188, food list 308/317 → 178/180,
  complete 324/341 → 276/279, text edit 314/314 → 271/279, Undo 313/319 →
  268/270, bulk dry run 717/727 → 230/236, import dry run 305/309 → 218/222,
  import 310/316 → 444/446. All pass.
- dense-2: tasks list 786/791 → 304/307, food list 518/522 → 301/302,
  complete 546/566 → 457/467, text edit 524/565 → 455/460, Undo 525/570 →
  445/460, bulk dry run 1042/1139 → 363/377, import dry run 509/518 →
  333/346, import 513/518 → 694/731. All pass; import is within 6 ms of its
  700 ms median.
- dense-food: tasks list 833/842 → 353/360, food list 559/565 → 350/355,
  complete 564/566 → 506/514 (median miss), text edit 567/571 → 501/512
  (median miss), Undo 566/573 → 494/498, bulk dry run 1086/1151 → 411/432,
  import dry run 554/583 → 386/408, import 565/587 → 757/769 (median miss).

Remaining cost, dense-food write call (phase probe): the warm history open
about 320ms (the app's `startup.warm.history` path, decoded-cache proof and
Task cache proof included) and the close-time seal about 140ms (one Task cache
digest, decoded-cache encode and SHA-256 of a ~5 MB payload); command work is
under 10ms. Further cuts need incremental cache proofs or a faster warm open,
both shared with the app's startup and outside this change. The planned
import is two such opens partly overlapped. Budgets stay as declared.

Full local measure-only gate at `f2d6fcf` (all fixes; same caps, ext4, all
254 labels): correctness, pins and the Task growth pair passed; dense-1 and
dense-2 passed every label. dense-food missed `agent.write.taskComplete`
517/540, `agent.write.textEdit` 503/517, `agent.write.textEditUndo` 508/529
and `agent.write.purchaseImport2` 798/835 (budgets 500/750 and 700/1000),
and `food.product.edit.undo` maximum 23.6ms (one sample; the other four
5.8–7.8ms; earlier runs 7.0 and 6.4ms maximum), which also failed the Food
growth pair's maximum. That in-session Undo does not open, close or seal, so
the spike is not attributed to these changes; it is unexplained. The
dense-food write misses are open.

### Planned purchase import: one plan check, entities encoded once (2026-10-29)

A phase probe of the dense-food planned import (reference caps) showed two
full plan observations in the commit (one before the command and the one
inside the append) and an effect diff that re-encoded every task, container,
product and purchase twice. `purchases import` now skips the pre-command
check: its append refuses inside fresh admission (`canCommit`, tested; a
registry test pins which commands may skip). The observation keeps each
entity's JSON encoding, made once; its hash uses an injective framing and the
diff decodes only changed entities. Plan hashes are unchanged. No budgets,
proofs or checks were relaxed.

Local measure-only gate at `b282f03` (same caps, ext4, 256 labels, no
reruns): correctness and pins accepted; dense-2 and dense-food passed every
label. `agent.write.purchaseImport2` 707/716 → 686/692 on dense-food,
641/660 → 611/616 on dense-2 and 416/422 → 397/400 on dense-1 (budget
700/1000). dense-1 missed only `recurring.complete.undoUntouched` maximum:
one sample 74.6ms against 70 (others 40.8–51.2; median 43.4 against 65; at
`e535889` 35.6–38.2). That sample spent 66.6ms of its own CPU, with no
throttling and a 0.6ms append, so it is not a disk stall. It is an app
recurring-task path that this change (agent code only) does not run. It is
reported as is, not resampled.


The planned-import correctness pass additionally passes the plan guard into the
store's freshly admitted append, binds exact external plan bytes (frozen once for
the overlay preview and real command), and includes canonical history heads,
manifest and installation in the in-append input witness. This covers hidden
purchase/provenance evidence and net-zero peer edits, not just visible projected
values. Effect-based dry-run planning and both workspace opens remain; no
state-only single-open token substitutes for the reviewed effect plan.

### Planned commit: plan on a worker isolate (2026-10-29)

Reference qualification of `24f2927` failed twice (see
[evidence](../evidence/agent-interface-performance/README.md)): q1
`food.product.merge` Food-growth median 8.532 ms against 8.52125 ms, then the
one official rerun q2 dense-food `agent.write.purchaseImport2` median 747.336
against 700 ms. The import miss is repeatable (q1 684, advisory 676, local
diagnostic 699 ms median: always at the budget edge), so it was profiled and
fixed; budgets are unchanged.

Phase probe (dense-food, reference caps, separate diagnostic runs, not
qualification): the planned commit ran the dry run's full open of the profile
copy and the real workspace open interleaved on one isolate, about 496 ms
together (one warm open is about 340 ms: decoded-cache verification 159,
restore 22, record decode 45, effect validation 94), then the command 25 ms and
the close-time cache seal about 111 ms. A pure-Dart SHA-256 rewrite was tried
and was no faster than package:crypto.

Fix: the planned commit's dry run (open of the profile copy, command, both
observations, effect diff and plan hash) now runs on a worker isolate once the
copy exists, while the real workspace opens on the calling isolate. Both full
opens, the effect plan, the plan-hash check before the command and the
in-append plan guard are unchanged; the worker receives only plain values (no
lock, database or open file) and the caller keeps the identity lock
throughout. A plain `--dry-run` still plans on the calling isolate. Diagnostic
`agent-cli` family under reference caps, median/maximum ms:
`agent.write.purchaseImport2` dense-food 699/714 → 576/586, dense-2 490/497,
dense-1 318/323; the other agent labels did not change. Test: a planned commit
opens only the real workspace on the calling isolate, and refusals raised in
the worker keep their kinds (mutation-checked).

Costs of the move: the two opens no longer share one in-flight decoded-cache
verification, so the worker repeats it (about 160 ms of extra CPU on a second
core) and reloads the time-zone database; the wall-time gain therefore needs
at least two CPUs (the reference unit has a 2-CPU quota; a single-core host
gets roughly the old serial time). Calling-isolate test hooks and phase probes
no longer see the plan side. Failures are translated to their stable kinds
inside the worker. The packaged-CLI smoke test (`tool/build_agent_cli.py`)
now runs one planned commit, so the worker path is exercised in the built
binary on Linux and Windows.

The q1 merge-growth miss did not reproduce in either bounded diagnostic
(dense-food median 6.585 and 6.194 ms; dense-1 4.599 ms; bound about 8.75 ms);
q2 passed it (5.293 ≤ 9.120). Both refreshes in the merge take the unchanged
fast path; the remaining 1–2 ms of Food growth is in the Food append and
projection. It stays within its bound and is not changed in this release.

### Next-release reference failure (request d8874dea, 2026-10-31)

The first qualification of `de6636d` failed on timing alone: dense-food
`agent.write.taskComplete` median 504.969 ms against 500, and Task-growth maxima
`converted.task.bulkDelete.undo` 36.562 against 36.0954 and
`food.product.bulkEdit.undo` 19.656 against 19.4984. Budgets are unchanged and the
failure stands. None of the disk-stall resample, official rerun, borderline or
noise-retry rules applies.

No source cause was found, so no optimization was made. No code in the three failing
paths changed since the last qualified source. The host was busy before and during
this run: quiet admission recorded load 2.49 and CPU PSI avg10 1.46 where every earlier
admission recorded avg10 0.00, and PSI over each attempt was 8–10× earlier runs, from a
desktop session that the gate's sibling-service evidence can't see. Interleaved
diagnostic runs afterwards (non-qualifying, same caps, q1 fixture, that load still
present) put `agent.write.taskComplete` at 480–512 ms on the last qualified source and
503–517 ms on this one, with no consistent source effect across the other agent labels,
and neither growth miss reproduced (maxima about 21.6 and 12.5 ms). That the load caused
the miss is likely but unproven, since the load was not removed and re-measured.

Even on a quiet host the label has only about 5% headroom (475.6 ms at `e212575`). If a
quiet-host qualification also misses it, treat that as a repeatable miss: the remaining
cost is the shared warm open and close seal, not the command.

### Qualification scope (Lee 2026-11-12)

New requests use relevant-source v3: only benchmark-compiled Dart code,
`tool/performance/`, `pubspec.lock` and the native engine (`native/`) void a
qualification. Budgets and CPU/caps/filesystem registration pins are unchanged.
Schema-v2 host registration records kernel/Python in every result and receipt
instead of enforcing exact versions; historical schema-v1 receipts keep their rules. Historical
receipts keep their recorded scheme; see [qualification protocol](performance-reference-qualification.md#relevant-source-identity-schemes).
