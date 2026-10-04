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
