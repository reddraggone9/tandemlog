# Isolated activation coordinator

Synthetic data only; not an adopted Tandemlog protocol. This package exercises
the approved policy that uncovered legacy whole-field text writes lose after
activation while their original records remain. It tests the proposed common
baseline, editing gates and explicit captured-draft behavior. Bootstrap UX has
not been approved or implemented in the app.

## Evidence

The original 18-case policy matrix and four-case draft extension are immutable
pre-implementation records. Their historical `not-run` entries remain intact;
[current results](../evidence/activation-results.json) report execution separately.
Commit `bc43c9b` froze 22 policy tests and four native preparation tests before
the coordinator existed. The initial failure was a test-loading error plus four
unknown-native-command failures, not 22 executed assertion failures. Commit
`2330222` froze four stronger recovery tests before their fixes. Three reproduced
failures; the actual native-checkpoint-restore assertion already passed.

All 30 activation tests pass on Linux x64. The original 52 native assertions,
ten editor session/widget tests, Linux Dart FFI, seven production clock tests,
one production future-clock warning test and activation analysis also pass.
Frozen current and original acceptance hashes were verified unchanged.
Five reproduced defects were fixed: retry cleanup, restored field handle,
missing historical dependency, duplicate append after an unknown receipt, and
writing after an incomplete journal tail. Saved red/green logs are in `evidence/`.

These tests call the production event decoder and pure projection. B01 also
opens the frozen stable-v3 fixture through actual TaskStore/SQLite and verifies
unchanged canonical hashes, writer identity and cache-hit reopen. B14 checks
old-reader rejection without checkpoint advancement. B13 actually restores a
pending native checkpoint and compares journal-only replay in a fresh Dart OS
process. B03 checks all 120 permutations of five supplied records plus duplicate
delivery; this is a bounded scenario, not proof over all histories.

## Run

Use the repository's locked Flutter dependencies and the isolated locked crate.
From the repository root, after `flutter pub get --enforce-lockfile`:

```sh
CARGO_TARGET_DIR=/tmp/tandemlog-activation-native-target \
  cargo +1.99.0 build --release --locked \
  --manifest-path experiments/yrs-spike/Cargo.toml
export SPIKE_LIBRARY=/tmp/tandemlog-activation-native-target/release/libtandemlog_yrs_spike.so
export DART_EXECUTABLE="$(command -v dart)"
flutter test --no-pub experiments/yrs-spike/activation_lab/test --reporter expanded
dart analyze --fatal-infos experiments/yrs-spike/activation_lab
python3 -m unittest discover -s experiments/yrs-spike/tests -v
dart experiments/yrs-spike/bin/ffi_smoke.dart
flutter test --no-pub experiments/yrs-spike/editor_lab/test --reporter expanded
```

The library path above is Linux-specific. The new coordinator/commands were not
run on Windows or Android in this iteration. The old native hosted results and
separate Android editor APK do not cover these changes. Tests use temporary
synthetic directories; they never access a configured household folder.

## What the prototype establishes

`LabConfig` supplies one agreed space, issuer and activation reference. The
baseline lists exact included writer sequence/hash frontiers, preserves original
v3 projection/Undo for that prefix, and binds lazy native fields to
space/entity/field/reference/codec/seed. Uncovered scalar text values lose;
supported nontext effects retain their original projection. Missing referenced
history gates editing. An incompatible second root preserves evidence and blocks
instead of electing a winner or dropping acknowledged upgraded edits.

Earlier scalar drafts retain their captured base and editing value, including
selection/composition. Neither activation arrival nor string equality attaches
them to native state. An explicit new session captures the verified native basis.
Its controller edits affect a private native draft; Save is blocked during
composition and never copies the old entire string into the live document.

Save uses nonmutating native preparation, an immutable prepared outbox record,
flushed journal append, exact receipt, then local native application. Sampled
interruption/restart/retry cases preserve exact bytes and append once. An
incomplete owned tail is retained and blocks writes. Full-state checkpoints
retain pending dependencies and invalid/unknown disposable checkpoints rebuild
from untouched journal records.

## Boundaries still open

- Explicit test configuration is not a mechanism for agreeing on an issuer in a
  serverless household. Bootstrap procedure and user experience remain a decision.
- Private POSIX `records.jsonl` and `cache.json` are synthetic journal/cache
  stand-ins. Production remains canonical per-device logs plus rebuildable SQLite;
  no JSON snapshot cache or new wire protocol has been adopted. SAF, Syncthing and
  concurrent process locking are outside this coordinator test.
- Happy-path selective Undo appends compensation and preserves remote work.
  Interrupted Undo is **not crash-safe**: the prototype applies native Undo before
  appending its compensation. Save durability tests do not prove Undo durability.
- The per-batch 53-bit actor digest is not a durable actor ownership/collision
  registry. Native thread-local test handles, lifetime/call serialization, resource
  budgets and adversarial parser isolation need production design and verification.
- Cache digests/frontiers detect sampled invalid disposable caches; they are not
  an authentication proof against malicious recomputed private cache contents.
  Historical-dependency checks are bounded helpers, not the complete production
  semantic validator for every possible record graph.
- No automatic incompatible-root merge, general process-death durability for
  unsaved drafts, new platform/runtime acceptance or native UI is claimed.

Main app imports, protocol3, cache13, schedules, signing and published artifacts
remain unchanged. The new Rust commands are isolated experimental ABI additions.
