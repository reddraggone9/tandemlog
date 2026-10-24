# Release performance gate

The standalone Dart executable measures production storage, application commands and readmodel queries in AOT release mode. It uses only generated public synthetic workspaces. There is no argument for a user workspace, mapping, profile, title or fixture import. Native text and SQLite libraries, compiler, package configuration, source and fixture bytes are sealed in the result.

The three versioned shapes share the SAME first 1,320 historical physical records, three writers, entity IDs and current Task/Food values. The existing dense-1 baseline and dense-2 Task-growth shape retain their integer specifications and canonical generation. An additive dense-food shape uses {baseRecords: 2640, growthKind: food}, normalized to the closed CLI food:2640. Dense-2 adds 1,320 bounded Task Notes edits alternating with exact restores; dense-food instead adds 1,320 Food brand edits alternating with exact restores on existing containers, each carrying its actual observed creation reference. Neither Food contents nor deletion state changes. All three then receive production native-text initialization and the same native checklist/recurring operations. Enforce equal initial-prefix hashes, full current-state digest, Task rows and Food container counts before treating this as history-only scaling. Actual record, effect and row counts are recorded. Both pairs must prove their growth module: Task effects grow only in dense-2, Food effects grow only in dense-food, and the other module's effect count stays equal to the baseline. Missing, unknown or mismatched growth claims fail correctness. The additional pair closes Food-own-history coverage; it does not test a growing number of recurring descriptors. Scalar synthetic IDs and strings are deterministic; production native actor allocation may vary between fixture generations. Generate each fixture once, seal its actual bytes, and reuse exactly those bytes for a timing retry. Profiles and workload copies are always fresh; existing output is refused.

Each action retains two warmups and five measured observations. Limits check both the median and maximum; no observations disappear as outliers. Each recurring repetition starts a separate fresh workspace/profile copied from the same sealed fixture and creates equivalent new parent inputs. Actions within that repetition accumulate canonical descriptors and native owners; later repetitions do not retain the previous repetition's history or owners. Newly allocated IDs and actors can vary. Cold startup means a fresh profile, not a flushed operating-system cache. Warm startup separately reports canonical/cache proof, cache restore and Task attachment. All three shapes must report the same 232 expected actions (the original146,45 converted-existing,33 Food-cardinality,2 confirmation-inclusive Food and6 first-point cases). Both comparisons (dense-1 to dense-2, and dense-1 to dense-food) retain their own per-action bounds and results. Versioned per-action paired rules check both median and maximum against small-size time multiplied by a fixed ratio plus a fixed additive allowance; report both sides and the computed bounds. A paired shape/coverage failure is correctness failure.

`limits-v1.json` contains the initial calibrated AOT storage/application/readmodel regression bounds, pinned by literal SHA in the workflow. The initial calibration combines current-source local and hosted Ubuntu observations, two warmups and five measured samples on each of the three shapes. Ordinary per-action median/maximum ceilings retain roughly 50% observed headroom, rounded to 5 ms with small-operation floors, while every ordinary maximum stays at or below the 100 ms target. Both history-growth pairs enforce 1.25× + 3 ms median and 1.40× + 5 ms maximum for all 224 ordinary labels. The eight startup labels have separately calibrated size-specific absolute ceilings. Their existing paired guards remain unchanged at 2.25× + 100 ms median and 2.50× + 200 ms maximum: loose historical proof-growth bounds, without a history-independence claim. Startup remains history-scaled; these limits do not excuse avoidable work. Finite calibration is not a percentile guarantee. Actual native UI paint/interaction acceptance is separate and remains unresolved after the current diagnostic exceeded 100 ms. Loosening an activated limit requires Lee's explicit approval; tooling has no automatic baseline-update switch.

A correctness, coverage, source, tool or fixture failure is terminal. A timing-only failure can receive at most one additional fresh-process run across the entire gate, with unchanged source, fixture, binary and limit seals, when separately observed CPU pressure and unrelated CPU work (sibling services excluding this service, or host busy CPU minus measured own/child CPU) overlap EVERY absolute-failing history-size process. Every failed pair requires qualifying evidence from that pair's larger-size process; if both pairs fail, both larger processes must qualify independently. Own quota throttling or slowness alone is insufficient. Aggregate pressure indicates suspected external noise, not proof about every individual sample. Preserve both attempts. A failed second attempt fails the gate; never retry until green.

This executable does not measure editor mounting, sidebar response, widget paint, keyboard input or first visible rows. Section preferences and projections are labelled storage/readmodel measurements. The actual release GUI needs a separate isolated GTK/Xvfb job with owned-window input, visible-pixel acknowledgments, finite cleanup and explicit capture overhead. Windows offscreen input probes are not substituted for that job.

Run `python3 tool/test_performance_gate.py` for gate policy and receipt regressions. `run_gate.py --measure-only` collects calibration observations and never claims release acceptance. A release invocation enforces the exact reviewed workflow-pinned limits; unbound or inactive limits fail closed. The calling workflow must impose the documented finite compile/runtime/resource bounds and retain every result and log.


The runner accepts no caller package configuration, source override or alternate limits file. It reads the repository package configuration, rejects a `tandemlog` root that resolves outside that checkout, creates its own fresh source fork, and changes only that package root URI and normalizes its already-validated effective library URI to lib/. Every copied file retains identical original and compiled SHA-256 values. The standalone storage closure needs no Flutter notifier/platform shim: the rewrite and shim allowlists are empty. Reachable Flutter UI imports, missing/escaping project imports, source extraction changes, changed dependency files or changed SDK kernel inputs fail closed. Production `LocalLogFolder` and `LocalDurability` implementations remain byte-exact, including append/flush semantics. A release invocation must execute tooling from the same checkout and supply the workflow's expected SHA-256 for the fixed versioned limits file.

One eligible timing rerun repeats ALL THREE original sealed shapes and BOTH comparisons in fresh processes/workload profiles, using the original sealed fixtures and all original bindings. It never regenerates different native actor bytes, cherry-picks action samples or repeats only until a ratio passes.

The shared validation workflow has a separate required Linux performance job; it is also required by signed-candidate checks. Its 65-minute whole-job bound includes native setup; the gate runs as the existing runner UID in a transient system-manager service with 55-minute runtime, 6 GiB physical-memory cap, no swap, 2 CPU quota and 128-task cap, plus bounded compile/generation/workload children. An outer timeout and exit/signal trap stop that exact service; actual cgroup bounds are recorded and required before release measurement. It retains preflight stderr/stdout, compile/generation logs, every timing attempt, paired comparisons, source/tool/fixture seals and per-size fixture contracts, including failures. Synthetic workspace payloads and local SQLite profiles are excluded from uploaded artifact paths. The committed initial calibrated limits are active and the workflow pins their exact SHA. Fresh exact-source enforcement is required after tooling or application changes; measure-only observations do not satisfy it. Food editor/controller construction/cancel/paint is explicitly a native-UI coverage gap; no storage-only number substitutes for it.

The initial calibration showed that the pre-existing task.title/notes/titleAndNotes and task.editorOpenCancel labels select the fixture's inherited recurring successor with a copied checklist, rather than an explicit Task birth. Those labels and observations are retained and their target is now asserted. Separate explicitTask.* cases add native-born ordinary Task title/Notes/both Save, Undo, editor preparation and complete native cancellation; they do not replace the inherited cases or excuse their scaling failures.

Manual development CI can explicitly request performance calibration while initial limits or a runner-class review is pending. This collects the same source-bound observations with releaseGateAccepted=false; it cannot satisfy release acceptance. Signed-candidate validation explicitly fixes performance_calibration=false, and normal push/PR CI also defaults to the enforcing path. No calibration switch is exposed by candidate or promotion workflows.

## Initial performance acceptance

Choose each action's timing boundary and budget from its intended responsiveness
before accepting the implementation. Do not measure a slow first implementation
and add headroom to turn it into an approved baseline. Ordinary local actions
retain the below-100 ms objective for input to visible acknowledgment; a passing
storage-only measurement does not establish that outcome.

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
