# RC4 build47 replacement preparation

Parent authorized integrating the independently reviewed bulk-warning fix and
preparing a main-only signed replacement on 2026-10-08. Publication and stable
promotion remain unauthorized; Lee's decision concerning Windows manual
interaction and Android spoken-accessibility gaps is still pending.

Fresh GitHub reads found main `3111dd94510a8f77e6978aa177e8d9b44fd7607c`,
34 successful signed main candidate sources with maximum build46, published
preview `v2026.10.2-rc.3` at build45, stable `v2026.10.1`, and no RC4 tag.
The replacement version is `2026.10.2-rc.4+47`. Existing workflow, signer pin,
dependency, domain, native and durable v3 inputs remain unchanged. The reviewed
production delta is one file, `lib/presentation/task_editor.dart`; the remaining
integration delta is focused tests, recorded evidence, documentation and version
metadata. The branch retains linear history from main and every original fix
commit. See [the reviewed fix](bulk-stale-warning-visibility.md).

## Preserve the previous candidate

Run `37819214432`, source `77a5f2dfde4ea914e7f2cf09dcbf77ee738056cc`,
build46 remains a preserved, superseded candidate. Its Android-release artifact
is `11569174876`, outer ZIP SHA-256
`08d2f8c157f27140aef448d5d33b1492b85b606f7d53a91caf39f16c42d7b58a`.
Parent accepted its exact APK SHA-256
`465c123d91be4465296945aa6d576545cd17dd05329da338c013dd069f4a7a1d`.
Its Windows artifact `11568777570` and Linux artifact `11568853640` remain bound
to that same source/run. Do not use these artifacts or their acceptance as
replacement-build evidence. Preserve the acceptance packet Library
`libfile_2254ff7abc188191b4075b190a0e4823` and the original receipts, source and
media. No original artifact, task, file, tag or release is deleted or modified.

## Integration and renewed acceptance

Review the integrated source and the actual published-rc3→replacement diff,
including the revised draft notes. The new compact warning is explained by one
bullet; the existing tag image remains byte-identical. A new release-note image
is optional because the bullet explains this small correction; native before
and after pixels remain available in engineering evidence.

Run full Linux, Windows and Android platform CI at the exact integrated source.
After those gates pass, verify remote main equals that source and invoke the
existing main-only signed candidate workflow. It retains its full reusable
platform checks and owner signing gate. Record exact source/run/artifact IDs,
outer digests, expiry, version and inner payload/checksum/package/signer bindings.
No publication workflow is invoked.

Renew native acceptance around the changed bulk-modal behavior: a bottom-scrolled
draft, delayed incoming peer change, visible rejection beside recovery actions,
retained draft/caret/focus/form position, repeat rejection with no canonical log
writes, and Cancel→Discard. Cover narrow dark/light, enlarged text, and actual
Android keyboard geometry. Add essential exact-package identity/signature,
non-debuggable build47 install/upgrade/launch, retained synthetic data and cold
restart smoke checks. Existing accepted build46 CRDT/checklist/v3 regression
evidence remains attributed to build46; this plan does not repeat that whole
matrix or relabel it as replacement evidence.

The extreme 160px editor limitation remains tracked in the visibility handoff.
Actual Windows manual interaction and Android spoken accessibility remain
unverified unless separately performed. Lee owns the decision about disclosure
versus holding preview delivery. Fresh quota must be checked before any later
publication; the last parent read was 63% at 19:11:15 UTC, reset
2026-10-14 10:33:41 UTC.
