# Isolated test-first text-merging spike

2026-10-04. Synthetic disposable data only. This separate experimental crate
is not linked into Tandemlog and has no application dependency, protocol,
fixture, signing, cache or live-data changes. A manual read-only hosted workflow
tests native Linux/Windows and cross-builds Android; it cannot publish anything.

Before implementation: `python3 -m unittest discover -s tests -v` must fail
because the native library is absent. Freeze the tests/cases hashes and record
the failed baseline. Each implementation result must reference those hashes.
Expected assertions must not be relaxed merely to make an engine pass; any
clarification receives a separate, explained test revision.

`tests/test_contract.py` exercises the proposed narrow JSON C ABI, not a public
Tandemlog API. Tests use explicit stable seed bytes, distinct replica client IDs,
UTF-16 offsets, captured-baseline draft documents and exact opaque updates. The
additional gates in `tests/cases.json` record production compatibility, native
packaging/runtime and adversarial admission work separately. Do not describe
not-run gates as passed or adopt this code based only on a green engine suite.

The first test-only standalone commit and hashes are preserved in evidence/;
the original red log is retained in the private standalone handoff. Review-driven
ownership cases were separately recorded red before their implementation fixes.
Run `cargo +1.99.0 build --release --locked`, then select the library with
`SPIKE_LIBRARY` and run `python -m unittest discover -s tests -v` and
`dart bin/ffi_smoke.dart`. Windows uses the release DLL; Linux uses the release SO.
Gate results and scope limitations are in the linked design prototype report.

Status/report files belong under evidence/. Real user task text, credentials and
private Markdown sources are excluded.

Admission hardening: tests/test_admission.py was recorded red before the narrow
pinned-Yrs-v1 allow-list in src/admission.rs. It rejects generic shared/rich-text
payloads and actor/seed identity conflicts before apply/new/restore. Deleted
strings are retained with skip_gc for comparison; this is bounded prototype
policy, not production compaction. Field routing/actor allocation and Android
runtime/editor gates remain open. See evidence/admission-test-first.json and
results.json for exact current versus baseline coverage.

Verified hardened source5470384080f56e03a209f991af6745a941d3b559:
run37216546987 passes52 tests + Dart FFI on native Linux/Windows and cross-builds
Android ARM64/x86_64. Additional gates8pass/0fail/4not-run remain separately
reported. Test-first commit cac56d3 precedes src/admission.rs (16:15:02 vs
16:17:29UTC). All original assertion hashes are unchanged.

The [isolated activation coordinator](activation_lab/README.md) subsequently
tests approved legacy text exclusion, a proposed shared baseline and captured
draft handling against actual production decoder/projection/native APIs.
Its30 Linux tests and stronger recovery checks have separate frozen expectations
and [results](evidence/activation-results.json). No production adoption, bootstrap
UX, new Android/Windows coordinator acceptance or crash-safe Undo is claimed.
