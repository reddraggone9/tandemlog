# Release performance gate

## Prospective host-role transition — ADR0033

Lee approved [controlled reference qualification](decisions/0033-controlled-reference-performance.md)
on2026-10-25: unchanged absolute and both history-growth limits qualify on
Farnsworth;hosted correctness/build/replay/integrity/source/fixture/completeness
remain mandatory,with hosted timing advisory. No hardware multipliers. This
supersedes earlier hosted placement only;all budgets/coverage/retry constraints
below stay active. [Operating protocol](performance-reference-qualification.md).
Missing or stale reference qualification fails the separate required verifier.
Old failures and measure-only passes retain their original status;implementation
is not qualified until reviewed registration,a fresh enforcing receipt and CI pass.

A failed reference qualification of unchanged source may receive exactly one
official rerun,and only after a recorded non-qualifying diagnostic covered every
failing label without reproducing any (Lee,2026-10-26). A second failure is
repeatable and must be profiled and fixed. Budgets are unchanged. See
[official rerun](performance-reference-qualification.md#official-rerun-after-non-reproduction).

Borderline rule (Lee,2026-10-27;absolute misses added2026-10-28):when IDENTICAL
relevant source (same relevant-source identity) already holds a verified passing qualification,a
later timing failure within normal run-to-run variation is a borderline limit,
not a regression. It does not block the release and queues a look at the limit
or the scaling behind it. For exactly this case it replaces "a failed rerun is
repeatable";the official-rerun rule stays for every other failure. Tooling
verdict `borderline-accepted` needs ALL of:a verified passing qualification of
the same identity issued before the failed request;an enforcing,complete
result whose correctness,coverage,replay/integrity and execution all passed;
every timing miss,absolute or history-growth,at most 5% over its unchanged bound
(`BORDERLINE_VARIATION_BAND`,from q9–q11 identical-code storageAdmission at
99.8%/96.3%/101.6%). Anything else is an ordinary failure. Budgets are unchanged.
See [borderline result](performance-reference-qualification.md#borderline-result-on-already-qualified-source).

Disk-stall resample rule (Lee,2026-10-28 21:37;standing,no per-release approval):
in a reference qualification,a timing miss gets ONE resample of its label when the
failing sample's durable append (write+fsync) accounts for the overrun and its CPU
time is within the bound:for every measured sample over the missed bound,the
sample minus its append time is within that bound and its CPU time (cgroup
`usage_usec` over the action) is within it too. Growth misses use their computed
bound;a label missing two bounds must satisfy the tighter one. Budgets are
unchanged. The resample re-measures the label: the label's whole family
(warmups and samples) runs once more in a fresh process on the same sealed
fixture and binary, and the label's seven observations replace the original
ones; every absolute and growth limit is then evaluated again. Resamples are
taken only when they can decide the attempt (every missed label attributed). A
resampled label that misses again is an ordinary failure under the existing
rules and is never resampled again. A miss that is not attributed (CPU over the
bound,append too small to account for it,missing diagnostics,or any other
unattributed miss in the attempt) follows the existing rules unchanged. The
receipt keeps the original samples and failures and adds `diskStallResamples`
with the attribution numbers (wall,append,CPU,throttled,wall minus append),the
resample's execution and log hash,its replacement observations and the
recomputed decisions;the verifier recomputes attribution from the attempt log and
the decisions from the samples. Code:`tool/performance/disk_stall.py`;tests:
`tool/test_disk_stall_resample.py`. This replaces an owner override for this case.
See [disk-stall resample](performance-reference-qualification.md#disk-stall-resample).


The standalone Dart executable measures production storage, application commands and readmodel queries in AOT release mode. It uses only generated public synthetic workspaces. There is no argument for a user workspace, mapping, profile, title or fixture import. Native text and SQLite libraries, compiler, package configuration, source and fixture bytes are sealed in the result.

The three versioned shapes share the SAME first 1,320 historical physical records, three writers, entity IDs and current Task/Food values. The dense-1 baseline and dense-2 Task-growth shape retain their integer specifications and three physical owners. Prospective fixture schema v2 (exact completion instants) gives Task-growth edits a separate normalized logical namespace, attributed to those same owners, so the continuing writer retains identical next logical IDs and completion order across shapes. Previously sealed v1 canonical bytes and evidence remain immutable; v2 is freshly generated and sealed, not a rewrite of accepted fixtures. An additive dense-food shape uses {baseRecords: 2640, growthKind: food}, normalized to the closed CLI food:2640. Dense-2 adds 1,320 bounded Task Notes edits alternating with exact restores; dense-food instead adds 1,320 Food brand edits alternating with exact restores on existing containers, each carrying its actual observed creation reference. Neither Food contents nor deletion state changes. All three then receive production native-text initialization and the same native checklist/recurring operations. Enforce equal initial-prefix hashes, full current-state digest, Task rows and Food container counts before treating this as history-only scaling. Actual record, effect and row counts are recorded. Both pairs must prove their growth module: Task effects grow only in dense-2, Food effects grow only in dense-food, and the other module's effect count stays equal to the baseline. Missing, unknown or mismatched growth claims fail correctness. The additional pair closes Food-own-history coverage; it does not test a growing number of recurring descriptors. Scalar synthetic IDs and strings are deterministic; production native actor allocation may vary between fixture generations. Generate each fixture once, seal its actual bytes, and reuse exactly those bytes for a timing retry. Profiles and workload copies are always fresh; existing output is refused.

Each action retains two warmups and five measured observations. Limits check both the median and maximum; no observations disappear as outliers. Each recurring repetition starts a separate fresh workspace/profile copied from the same sealed fixture and creates equivalent new parent inputs. Actions within that repetition accumulate canonical descriptors and native owners; later repetitions do not retain the previous repetition's history or owners. Newly allocated IDs and actors can vary. Cold startup means a fresh profile, not a flushed operating-system cache. Warm startup separately reports canonical/cache proof, cache restore and Task attachment. All three shapes must report the same 256 expected actions (the original146,45 converted-existing,33 Food-cardinality,2 confirmation-inclusive Food,6 first-point cases,12 Food-product cases,2 Food Move some cases 8 agent CLI calls and2 writer300 refreshes). Both comparisons (dense-1 to dense-2, and dense-1 to dense-food) retain their own per-action bounds and results. Versioned per-action paired rules check both median and maximum against small-size time multiplied by a fixed ratio plus a fixed additive allowance; report both sides and the computed bounds. A paired shape/coverage failure is correctness failure.

`limits-v1.json` contains the initial calibrated AOT storage/application/readmodel regression bounds, pinned by literal SHA in the workflow. The initial calibration combines current-source local and hosted Ubuntu observations, two warmups and five measured samples on each of the three shapes. Ordinary per-action median/maximum ceilings retain roughly 50% observed headroom, rounded to 5 ms with small-operation floors, and every ordinary maximum was additionally capped at 100 ms during calibration (a historical calibration cap, not a responsiveness target; see [What sets acceptable latency](#what-sets-acceptable-latency-lee-2026-10-27)). Both history-growth pairs enforce 1.25× + 3 ms median and 1.40× + 5 ms maximum for all 238 ordinary labels. The eight startup labels have separately calibrated size-specific absolute ceilings. Their existing paired guards remain unchanged at 2.25× + 100 ms median and 2.50× + 200 ms maximum: loose historical proof-growth bounds, without a history-independence claim. Startup remains history-scaled; these limits do not excuse avoidable work. Finite calibration is not a percentile guarantee. Actual native UI paint/interaction acceptance is separate and remains unresolved. Loosening an activated limit requires Lee's explicit approval; tooling has no automatic baseline-update switch.

A correctness, coverage, source, tool or fixture failure is terminal. A timing-only failure can receive at most one additional fresh-process run across the entire gate, with unchanged source, fixture, binary and limit seals, when separately observed CPU pressure and unrelated CPU work (sibling services excluding this service, or host busy CPU minus measured own/child CPU) overlap EVERY absolute-failing history-size process. Every failed pair requires qualifying evidence from that pair's larger-size process; if both pairs fail, both larger processes must qualify independently. Own quota throttling or slowness alone is insufficient. Aggregate pressure indicates suspected external noise, not proof about every individual sample. Preserve both attempts. A failed second attempt fails the gate; never retry until green.

This executable does not measure editor mounting, sidebar response, widget paint, keyboard input or first visible rows. Section preferences and projections are labelled storage/readmodel measurements. The actual release GUI needs a separate isolated GTK/Xvfb job with owned-window input, visible-pixel acknowledgments, finite cleanup and explicit capture overhead. Windows offscreen input probes are not substituted for that job.

Run `python3 tool/test_performance_gate.py` for gate policy and receipt regressions. `run_gate.py --measure-only` collects calibration observations and never claims release acceptance. A release invocation enforces the exact reviewed workflow-pinned limits; unbound or inactive limits fail closed. The calling workflow must impose the documented finite compile/runtime/resource bounds and retain every result and log.


The runner accepts no caller package configuration, source override or alternate limits file. It reads the repository package configuration, rejects a `tandemlog` root that resolves outside that checkout, creates its own fresh source fork, and changes only that package root URI and normalizes its already-validated effective library URI to lib/. Every copied file retains identical original and compiled SHA-256 values. The standalone storage closure needs no Flutter notifier/platform shim: the rewrite and shim allowlists are empty. Reachable Flutter UI imports, missing/escaping project imports, source extraction changes, changed dependency files or changed SDK kernel inputs fail closed. Production `LocalLogFolder` and `LocalDurability` implementations remain byte-exact, including append/flush semantics. A release invocation must execute tooling from the same checkout and supply the workflow's expected SHA-256 for the fixed versioned limits file.

One eligible timing rerun repeats ALL THREE original sealed shapes and BOTH comparisons in fresh processes/workload profiles, using the original sealed fixtures and all original bindings. It never regenerates different native actor bytes, cherry-picks action samples or repeats only until a ratio passes. The disk-stall resample above is the one per-label exception: it re-measures a whole label once, only when durable-append time accounts for the miss, and records both measurements.

The shared validation workflow has a separate required Linux performance job; it is also required by signed-candidate checks. Its 65-minute whole-job bound includes native setup; the gate runs as the existing runner UID in a transient system-manager service with 55-minute runtime, 6 GiB physical-memory cap, no swap, 2 CPU quota and 128-task cap, plus bounded compile/generation/workload children. An outer timeout and exit/signal trap stop that exact service; actual cgroup bounds are recorded and required before release measurement. It retains preflight stderr/stdout, compile/generation logs, every timing attempt, paired comparisons, source/tool/fixture seals and per-size fixture contracts, including failures. Synthetic workspace payloads and local SQLite profiles are excluded from uploaded artifact paths. The committed initial calibrated limits are active and the workflow pins their exact SHA. Fresh exact-source enforcement is required after tooling or application changes; measure-only observations do not satisfy it. Food editor/controller construction/cancel/paint is explicitly a native-UI coverage gap; no storage-only number substitutes for it.

The initial calibration showed that the pre-existing task.title/notes/titleAndNotes and task.editorOpenCancel labels select the fixture's inherited recurring successor with a copied checklist, rather than an explicit Task birth. Those labels and observations are retained and their target is now asserted. Separate explicitTask.* cases add native-born ordinary Task title/Notes/both Save, Undo, editor preparation and complete native cancellation; they do not replace the inherited cases or excuse their scaling failures.

Manual development CI can explicitly request performance calibration while initial limits or a runner-class review is pending. This collects the same source-bound observations with releaseGateAccepted=false; it cannot satisfy release acceptance. Signed-candidate validation explicitly fixes performance_calibration=false, and normal push/PR CI also defaults to the enforcing path. No calibration switch is exposed by candidate or promotion workflows.

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
coverage failures are terminal, and only the documented single externally
justified timing rerun is permitted.

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


The fixture-selection audit distinguishes fixed-target warm edits from first
durable activity on a newly derived entity. The inherited task.title family
warms the same target. The recurring family instead creates a fresh parent,
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

## Food-product prospective coverage (2026-10-28)

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
separate gaps. Fresh enforcing qualification is pending.

## Food Move some prospective coverage (2026-10-29)

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
gaps. Fresh enforcing qualification is pending.

## Agent CLI prospective coverage (2026-10-29)

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


### Next-release read-only Activity log

Before first measurement, `activity.read.derive` adds a 15ms median / 30ms maximum
readmodel budget on all three shapes and the unchanged ordinary paired-growth
rules. It builds published rows and current installation labels once per revision,
sorts by recorded logical occurrence clock, and checks count, uniqueness, order
and canonical immutability. This adds a 257th label; all previous 256 absolute and
growth bounds remain byte-value unchanged. It does not time first paint, scrolling,
details or incoming-history visible refresh; native workflows must assess these.
No work runs while the dialog is closed. No physical occurrence/skew correction
or missing actor-user reconstruction is claimed.
