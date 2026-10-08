# Unreleased production text checkpoint

All data/screenshots here are synthetic. Production app source is on
`experiment/text-activation-policy`; this is engineering evidence, not a release
acceptance receipt. These are chronological checkpoints; earlier passing counts
do not establish current acceptance. The latest Undo blocker and isolated
proposal are below. Original integrated Linux library SHA-256:
`892d5048fc30c615fd672a6d6e9a8000ca8fdf6723271e54317356debf9bc6b3`.

Verified locally with Flutter 3.47.5/Dart 3.13.4 and locked Yrs 0.28.0/Rust 1.99.0:

- 447 unit/widget tests with `TANDEMLOG_TEXT_LIBRARY` pointing to that SO,
  clean analysis and formatting, including the two local recurring-completion
  guard cases. Their related actual-library suite separately passes 41. The
  earlier 445-case aggregate log is retained as prior evidence.
- The actual GTK app flow in `integration_test/text_workflow_test.dart` passes:
  offline native capture/edit before legacy setup, peer changes during a private
  draft, merged Save, selective session Undo retaining peer work, legacy setup,
  narrow editor and restart persistence. Xvfb/Openbox, 1200px Light/100% and
  390px Dark/200%; five screenshots visually inspected. The previously clipped
  setup instruction now wraps below notes. Composition is injected, not an OS
  keyboard test. Debug timings in this log are not release cold-start results.
- Four offline exact-license tests and four packaging contract tests pass.
  Notice assets are in the actual Linux bundle; Windows/Android packaging and
  native installed lifecycle are not verified by this check.
- 98 Python native cases and two Rust cases passed on the same SO. Native
  admission/resource measurements, original failures and corrected fixture
  assumptions are retained in the nested HANDOFF files. Those subprocess
  measurements are not UI frame, Android-memory or end-to-end startup evidence.
- Current native Android arm64-v8a, x86_64 and armeabi-v7a release libraries
  cross-build offline with locked Cargo, Rust 1.99.0 and NDK 28.2/API 24;
  required exports and 16 KiB ELF alignment pass. Exact digests are in
  `android-engine-build.json`. Official standard-library targets were installed
  after an empty/stale target directory caused an explicit compiler failure;
  no alternate repository or network-policy workaround was used. This is not
  an APK packaging, installation or native Android runtime check.

The first native UI finder failure assumed Save leaves the editor open; the
assertion was corrected to the existing close-on-Save behavior. The first
combined test command had one incorrect filename; its log is retained alongside
the corrected passing command. The original historical benchmark remains
unchanged; later measurements live in this directory.

Pending: successor text agreement for concurrent recurring completion, complete
existing native workflow adaptation/aggregate, mandatory real-engine hosted CI,
Android APK packaging, installed native Windows and
exact signed Android acceptance, release performance and independent final
notes/media review. The current local recurrence guard rejects before receipt or
append and changes no historical replay. No new production release or main push
has occurred. Frozen stable v3 fixtures and canonical history are unchanged.

## Approved layout merge and release-mode startup checkpoint

At isolated production source `09a270153241c2a3d3a7382aa6720c413a59265c`, the
approved build45 date/time geometry is merged while native text gates and frozen
pending-command controls remain intact. All **448** unit/widget tests pass with
the actual Linux SO; `linux-unit-after45.txt` preserves literal output.
This is not main adoption of the native text engine.

The actual Linux release executable SHA-256 is
`99076ba62d994b044e7bcf7f65c960ad7ecf9eec8bf9c0577ea8db1873f1228f`;
its bundled engine remains
`892d5048fc30c615fd672a6d6e9a8000ca8fdf6723271e54317356debf9bc6b3`.
Native GTK/Xvfb, Flutter3.47.5, two separate process launches per workload:

| Synthetic workload | Rebuild loaded frame | Warm loaded frame | Rebuild/warm first frame |
| --- | ---: | ---: | ---: |
| 10 legacy tasks | 750ms | 679ms | 362/333ms |
| 2,000 legacy tasks | 1,102ms | 662ms | 339/324ms |
| 2,000 native-text tasks | 2,399ms | 688ms | 321/317ms |

These external timers run from process creation to a post-frame loaded-state
stdout marker, not physical presentation or first input. The first app frame
can precede task readiness. OS page caches are not flushed; parallel validation
work can contend for this cloud host. These are two samples, not percentiles,
phone measurements or comparative platform claims. Warm runs assert complete
projected task counts and zero canonical file-content reads. Native fresh replay
spends1,819ms in ingestion versus511ms for the legacy fixture; warm ingestion is
103/102ms. This identifies rebuild work rather than routine startup replay.

`startup/` contains the raw phase samples and fixture/runner sources. Native
fixture creation uses the production event encoder/decoder and real engine seed
API for every `task.createdWithText`; it is not a legacy-only workload relabeled
as native. It creates a fresh private synthetic folder, and the preserved runner
reuses those exact events without regenerating or changing their history. SQLite
is opened read-only after exit to verify the complete projected task count.
No real data, history compaction or metadata timestamp rewriting is involved.


## Native ordering regression and platform gate checkpoint

The adapted native matrix found a genuine omission: `projectOrder` treated only
scalar creations as chronological actions, appending native creations after moves.
Two pure cases and an actual mixed TaskStore/cached-reopen/rebuild regression fail
before the correction. Native creations now participate at their event position;
historical scalar ordering and accepted fixture bytes are unchanged. Reopening a
revision2 positions cache repairs it from already-cached canonical events using
revision3, without shared-log contents or canonical-byte changes. No new SQLite
schema version, full replay, writer reset or durable operation rewrite is needed.
Red and green logs are retained in `platform-gates/`.

The app Android debug build initially failed before compilation because AGP9.1
rejects a Directory Provider passed to legacy JNI SourceSet. The concrete File
binding retains the explicit producer-task dependency; an actual offline Gradle
graph check and the subsequent APK build pass. The unpublished debug APK SHA256
is `c7588bb95833b5bfcfc13a0a5396b6d19152d5c090dc99e5f6c2228ad7efc295`.
It was built before the ordering correction and is packaging-only evidence,
**not a candidate for user acceptance, not owner-signed and not build45's APK**.
All3 native ABI payloads/exports,64-bit RELRO/16KiB LOAD, APK ZIP alignment and
byte-identical full notices pass. Linux release bundle ABI/notices also pass.
The failed build log and successful payload logs are preserved separately.

Mandatory hosted gates now bootstrap hash-pinned official rustup1.29.1/Rust1.99
outside app builds, fetch locked Cargo dependencies, and build the production
engine offline. Linux/Windows unit jobs must load the actual SO/DLL before tests;
missing native support cannot silently skip coverage. The98 frozen native
admission/worker cases and Rust cases also run against that production library.
All existing installed desktop lifecycle and Android signature gates remain.
Android uses the already-approved exact NDK28.2 with its three std targets. Signed
publication still consumes accepted artifacts without rebuilding. No secrets,
permissions, runner costs or accepted build45 binaries changed. Hosted Windows
and final Android runtime acceptance remain pending until their exact runs pass.

The native aggregate at the first adapted snapshot finishes48/50. One failure is
an obsolete scalar whole-text conflict assertion, corrected to exercise incoming
nontext metadata while the captured native draft stays intact. The other is an
actual session-Undo expectation under investigation; no assertion is relaxed or
release/CI success claimed from this run. The native mixed-order workflow passes
with the corrected projector in its compiled kernel. All451 unit/widget tests
pass after the cached-order revision adjustment; the prior obsolete cache-marker
expectation and updated passing run are preserved. Final affected native and
hosted aggregate results will be recorded separately.


## Extended Undo lifecycle: blocked, isolated repair reviewed

The shared named-operation owner corrects `Review → Check → Plan → Undo → Undo`
without duplicating restored identities. Native GTK 1200×800 Dark confirms the
restored title, preserved unsent capture draft, notes and date. An independent
adapter review also found that requesting another operation while Undo was
pending returned the first preparation; the checked native operation binding is
now always consulted. Both original failing regressions and passing focused runs
are retained in [undo/](undo/README.md). Native Undo's contextual newer-change
status now includes active later native edits, with a red/green store regression.

The longer save/Undo/close/new-owner cycle exposes a remaining genuine blocker:
`commit_undo` can reject `session Undo replay differs from live state`. Its
canonical compensation is already durable, so the preparation remains retained;
a later Save accurately reports its unavailable Undo registration. The current
unpatched SO is `1663b44d9c3f3712e58792f0bd6cd51dd861f8c072184a685e8442d7b635f0f1`.
The earlier453-case unit pass predates the expanded lifecycle assertion; it must
not be presented as a green current aggregate.

An isolated official-source copy changes only Yrs's three-line restoration loop
to sort immutable IDs before assigning new identities. It passes the expanded
lifecycle,50 actual-library application/FFI/session/coordinator cases,98 frozen
native cases and4 Rust tests. Exact source archive checksums, the proposed patch
and independent review are in `undo/`. Repo Cargo/lock files are unchanged; the
patch is **not adopted or shipped**. Maintaining the pinned patch versus changing
snapshot ownership is a pending technical decision. Hosted CRDT CI has not been
dispatched against a known failing dependency, and no Windows/Android runtime
acceptance or preview publication is claimed.

A separate safety regression now blocks Undo against an acknowledged but
unregistered local Save in the same field. It appends no compensation, keeps
canonical bytes unchanged, and supports exact registration retry with the retained
capture. Closed-capture session history clears on restart, preserving saved tasks.
Frozen stable v3 fixture bytes and all real data remain untouched.
