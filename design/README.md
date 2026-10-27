# Design map

Current stable2026.10.6/build85 is [published Latest](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.6) after exact native acceptance and independently reviewed [public-byte verification](../evidence/stable-2026.10.6/publication/README.md).

## Current source of truth

Previous stable 2026.10.5/build81 remains [available](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.5) with the accepted RC1-RC4 scope. [Publication receipts](../evidence/stable-2026.10.5/publication/README.md) bind exact source `bfb17ed71e0ed7953cc32c8f77a8907e7fdb337d`, candidate 38782112182, promotion 38792894635 and anonymous public bytes. Existing native coverage qualifications remain explicit.

Lee approved Flutter/Dart + SQLite cache + canonical per-device JSON logs on 2026-09-30. File-based provider-independent serverless sync is foundational. Default household data is shared within one space. Tasks are released; Food is released as a separate module in stable2026.10.4/build71; [publication receipts](../evidence/stable-2026.10.4/publication/README.md) record exact native acceptance and public verification.

1. [Status, commands and limitations](status.md)
2. [Product and milestone](product-behavior.md)
3. [Onboarding and everyday UI rationale](decisions/0002-onboarding-and-everyday-interface.md), [approved stack decision](decisions/0001-client-and-storage.md) and [stack](tech-stack.md)
4. [Architecture](architecture.md)
5. [Storage design](storage-and-sync.md), [implemented schema](schema.md), [recovery](recovery.md)
6. [Runtime/visual QA](runtime-qa.md) and [current task-based UX audit](ux-audit-rc4.md) ([rc3 history](ux-audit-rc3.md), [rc2 history](ux-audit-rc2.md))
7. [Deferred modules](future-modules.md)
8. [Repository rules](../AGENTS.md)

The [initial review](review.md) is historical rationale; later accepted decisions supersede its recommendations. Original [product](archive/product-behavior.md), [storage](archive/storage-and-sync.md), and [stack](archive/tech-stack.md) documents are archived, not active requirements. Obsolete `data-model.md` was removed as requested; recover it from Git if needed.

Each subject has one source of truth. Keep status/evidence current; link rather than duplicate specifications. New consequential choices receive an ADR and explicit accepted/proposed status.

- [Builds and releases](releases.md): CI gates, test installation and signing limitations.
- [Dependency inventory and review](dependencies.md): resolved versions, native/build provenance and bounded update PRs.
- [Android repository routing](decisions/0020-build-dependency-repository-routing.md): reviewed TLS-fallback mitigation and remaining trusted-host/toolchain boundary.

## Current milestone and supporting research

- [Food as products](food-products.md): proposed (not accepted) design for Product and Purchase records, implicit products for existing containers, merge-as-alias, keep-in-stock minimums and receipt import; open decisions for Lee. No implementation.

- [Release performance gate](performance-gate.md) and [ADR0032](decisions/0032-release-performance-gate.md): approved synthetic AOT regression budgets, bounded noise handling and separate native UI acceptance; initial calibrated AOT limits are active; fresh exact-source enforcement and native UI acceptance remain separate requirements.

- [Controlled reference performance](decisions/0033-controlled-reference-performance.md): Lee-approved prospective Farnsworth absolute/growth qualification with unchanged budgets,mandatory hosted correctness and advisory hosted timing;[operating protocol](performance-reference-qualification.md),fresh enforcing receipt and exact-source CI required. No persistent runner or multiplier.

- [Task latency repair](task-latency-repair.md): bounded exact-byte decode reuse and disposable projection indexes address RC4 startup/edit/Save/Undo/completion pauses; development validation and private-copy benchmarks are separate from future native candidate acceptance.

- [Coordinated unified-only cutover](decisions/0031-coordinated-unified-cutover.md): approved successor to the transition mechanisms below. Current action records, required revisions on first persistence, settings-only local reset and external normalization have passed [qualified development validation](../evidence/coordinated-cutover-build99/README.md). Actual physical mapping and fresh frozen real-copy replay remain cutover prerequisites. No live conversion or release is implied; earlier build98 evidence retains its original attribution.

- [Required support for additional time zone names](decisions/0030-required-time-zone-reader-capability.md):
  accepted explicit reader-floor design with exact legacy rules and owned
  recovery. Implemented and accepted in [RC.3/build98](../evidence/prerelease-2026.10.7-rc.3/publication/README.md),
  including explicit activation and the reader floor. Build98's local journal uses
  forward-only profile schema5.


- [Observable workspace state](decisions/0029-observable-workspace-state.md):
  approved correction for indirect-admission Task staleness, shared reconciliation
  and selective derived views. Implemented and accepted in
  [RC.3/build98](../evidence/prerelease-2026.10.7-rc.3/publication/README.md); candidate97
  keeps its original source/artifact attribution.


- [App-owned workspace upgrade](decisions/0028-app-owned-workspace-upgrade.md): approved replacement for RC.2's engineering-only activation. Explicit device consent, protected snapshots, coordinated freeze and resumable SAF activation are implemented; source, qualified native and release gates passed for [RC.3/build98](../evidence/prerelease-2026.10.7-rc.3/publication/README.md). No production conversion has occurred.

- [Unified writer history and optional installation names](decisions/0027-unified-writer-history.md): implementation authorized on isolated disposable trials. Published experimentally as 2026.10.7-rc.2/build91 after exact native acceptance and independent review; [candidate and publication receipts](../evidence/prerelease-2026.10.7-rc.2/publication/README.md) retain coverage and the forward-only local-profile upgrade limit. Production conversion and adoption/consolidation remain deferred.

- [Field help, form validation and occurrence Due conversion](decisions/0026-field-help-validation-and-occurrence-due.md): published experimentally as 2026.10.7-rc.1/build86 after exact native acceptance and independent review. Draft-only dependent clearing was explicitly accepted on October 17. See [candidate acceptance](../evidence/prerelease-2026.10.7-rc.1/candidate86/README.md) and [public verification](../evidence/prerelease-2026.10.7-rc.1/publication/README.md).

- [Responsive Food editor pane](decisions/0025-food-responsive-editor-pane.md): approved wide Edit/Add/Add another and guarded narrow dialogs; [stable2026.10.6/build85](../evidence/stable-2026.10.6/publication/README.md) is published Latest after exact native acceptance, authorized promotion and independent public-byte verification. [RC.1/build84](../evidence/prerelease-2026.10.6-rc.1/publication/README.md) remains available.

- [Visible task drop gaps](decisions/0024-visible-task-drop-gaps.md): accepted rule for shared visible destinations, no-op writes and fresh inferred-neighbor guards; published experimentally as [2026.10.5-rc.4/build80](../evidence/prerelease-2026.10.5-rc.4/publication/README.md) after exact-source native acceptance.

- [Shared Tasks/Food row surfaces](decisions/0023-shared-list-row-surfaces.md): compact flat surfaces, consistent feedback and canonical drag insertion paint, published experimentally as [2026.10.5-rc.3/build79](../evidence/prerelease-2026.10.5-rc.3/publication/README.md) after exact-source native acceptance.

- [Food whole-container rows](decisions/0022-food-whole-container-rows.md): accepted flat editing, symmetric Remove one/Restore one buttons and group menus; supersedes older expanded contents UI. Published experimentally as [2026.10.5-rc.2/build76](../evidence/prerelease-2026.10.5-rc.2/publication/README.md) after exact-candidate native acceptance.

- [Local section memory and Android launcher shortcuts](decisions/0021-local-sections-and-launcher-shortcuts.md): released in experimental 2026.10.5-rc.1/build75, with Food filter/retention/presentation refinements and shared icons; [publication receipts](../evidence/prerelease-2026.10.5-rc.1/publication/README.md) retain source/artifact binding and acceptance qualifications.

- [Food field editing and Full defaults](decisions/0019-food-field-editing-and-contents-defaults.md): approved suggestions/multiple filters/exact-container Brand/Location bulk editing, conservative expanded-row cleanup and removal of RC-only unspecified contents; accepted RC3/build70 native evidence retains its original attribution.


- [Food import contract v1](food-import-contract.md): bounded reviewed staging, explicit official commit and exact-byte retry; private extraction/data remain external.

- [Food inventory](decisions/0014-food-inventory.md): physical-container scope and separately coordinated private import boundary; Food is released in stable2026.10.4/build71.

- [Food Stock and toolbar refinements](decisions/0017-food-stock-and-toolbar-refinements.md): combined Stock/Inbox, local date urgency and filter/account parity, released in stable2026.10.4/build71 with source-bound native qualifications.

- [Food session Undo](decisions/0018-food-session-undo.md): accepted50-action stack and selective additive v2 retractions, released in stable2026.10.4/build71 with reviewed native/hosted coverage.

- [Task Search and Add input](decisions/0016-task-search-and-add-input.md): default Search, released in stable2026.10.4/build71; the newer carried-text policy is implemented locally in ADR0034.

- [Toolbar section navigation](decisions/0015-toolbar-section-navigation.md): approved Tasks/Food dropdown in the existing section identity, responsive labels and protected drafts.

- [Task parity decisions](decisions/0003-task-parity-and-prerelease-boundary.md): authorized scope, time semantics and prerelease compatibility boundary.

- [Editing, bulk actions and installers](decisions/0004-editing-bulk-actions-and-installers.md): RC4 rationale.

- [Next task parity draft](next-task-parity-draft.md): research and source inventory underpinning the authorized parity milestone; ADR 0003 supersedes its earlier planning-only status.

- [Session Undo and toolbar fit](decisions/0005-session-undo-and-toolbar.md): RC5 rationale and conflict boundaries.

- [Stable readiness review](stable-readiness.md): required durable-data decisions before the first stable release.

- [Installation identity and locking](decisions/0006-installation-identity-and-instance-lock.md): one preferences-root lease, settings-owned writer UUID and local migration/reset.
- [Android reconciliation review](android-reconciliation-review.md): accepted checkpoint policy, SAF notification capabilities, measurements and limits.
- [Canonical record chains and integrity checks](decisions/0007-canonical-history-integrity.md): approved v3 wire contract, Settings audit, compatibility and trusted-head limits.
- [Calendar versions and promotion](decisions/0008-calver-and-release-promotion.md): approved naming, monotonic builds, resource bounds and separate stable acceptance.
- [Separate date and optional-time rows](decisions/0009-date-and-optional-time-rows.md): compact time entry, precision and responsive layout.
- [Collaborative text adoption](decisions/0010-collaborative-text-adoption.md): released in stable2026.10.2/build53, with existing-field shared baseline and offline new-task exception. [Investigation](text-merge-investigation.md), [test-first prototype](text-merge-prototype.md) and [adoption alternatives](text-merge-adoption-options.md) preserve earlier research and evidence.

- [Android text-preview QA](android-text-preview-qa.md): exact synthetic test package and native workflow instructions.
- [Historical recurring-text policy](historical-recurring-text-policy.md): released historical recompletion preserves the independently initialized child; earlier implementation checkpoints remain attributed.
- [Shared-history native acceptance](shared-history-native-acceptance.md): exact artifact identity, synthetic fixture and Windows/Android affected-flow contract after independent implementation review.
- [One-level checklists](decisions/0011-one-level-checklists.md): released item/recurrence and inline interaction policy in stable2026.10.2/build53;[stable acceptance](../evidence/stable-2026.10.2/README.md).
- [Checklist native acceptance](checklist-native-acceptance.md): exact candidate/fixture contract, platform workflow gates and current Linux evidence.
- [Composed final preview](final-preview-acceptance.md): reviewed component/source bindings, rc.4/build46 and remaining exact-artifact/native/publication gates.
- [Shared tag input](decisions/0012-shared-tag-input.md): Lee-approved B-style control across task editing, bulk Add/Remove and Filter, released in stable2026.10.2/build53.
- [Shared tag native acceptance](shared-tag-native-acceptance.md): historical synthetic fixture and exact source binding; completed device acceptance is recorded in the stable2026.10.2 receipt.

- [One app-wide local DB](decisions/0013-app-wide-local-database.md): approved single permanent DB and temporary recovery-file exception; published stable2026.10.3/build56 with verified import, activation, cleanup and startup/switch wiring. [Native handoff](local-db-native-acceptance.md) records completed bounded Windows/Android acceptance; [release receipts](../evidence/stable-2026.10.3/README.md) bind final native/artifact and public verification.

- [UX refinements2026-10-26](ux-improvements-20261026.md) and [ADR0034](decisions/0034-bounded-ux-refinements.md): local implementation, focused/full development checks; native/runtime/performance acceptance remains separate.

See [ADR0035](decisions/0035-exact-completion-instants.md) for required revision3 completion instants, offline cutover approximation, viewer-local Completed/search chronology, and unchanged recurrence/Undo.
