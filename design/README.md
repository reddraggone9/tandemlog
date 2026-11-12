# Design map

Stable 2026.11.1/build116 is Latest; `main` has no unreleased app changes
(checked 2026-11-12). [status.md](status.md) says what that release contains.

Stack (Lee, 2026-09-30, [ADR0001](decisions/0001-client-and-storage.md)):
Flutter/Dart, a private SQLite cache and canonical per-installation JSON logs in
one shared household folder synced by any file-sync tool (Syncthing, Dropbox).
Each subject below has one source of truth; link to it rather than repeating it.

## Read first

- [status.md](status.md): what is released, what is on `main` unreleased, build/test
  commands, known limitations.
- [../AGENTS.md](../AGENTS.md): repository working rules.
- [ux-principles.md](ux-principles.md): Lee's UI rules; every UX brief and
  screenshot review checks against it.

## Product

- [product-behavior.md](product-behavior.md): product behavior and milestones.
- [future-modules.md](future-modules.md) and [time-tracking-deferred.md](time-tracking-deferred.md):
  deferred directions, not commitments.
- Feature designs, all released: [time-driven-task-view.md](time-driven-task-view.md)
  (timed task views), [food-products.md](food-products.md) (products, purchases,
  Running low, receipt import; 2026.10.9), [batch-selection.md](batch-selection.md)
  (Tasks/Food selection, bulk edit, Move some; 2026.10.10–10.11),
  [agent-interface.md](agent-interface.md) (agent CLI/MCP; 2026.10.10),
  [activity-log.md](activity-log.md) (Activity log; 2026.10.11, refined in 2026.11.0
  and 2026.11.1).
- [food-import-contract.md](food-import-contract.md): Food import contract v1.

## Architecture and storage

- [architecture.md](architecture.md): module boundaries and bounded debt.
- [storage-and-sync.md](storage-and-sync.md), [schema.md](schema.md) and
  [recovery.md](recovery.md): the unified action format released in 2026.10.7,
  its sync and admission rules, and manual recovery.
- [history-store.md](history-store.md): local decoded-history store and fast
  start; 2026.11.1.
- [task-latency-repair.md](task-latency-repair.md): how ordinary actions avoid
  re-decoding history.
- [tech-stack.md](tech-stack.md): stack details, text engine and agent CLI build.

## Decisions

[decisions/README.md](decisions/README.md) indexes ADR 0001–0037. Status lines
inside many ADRs predate their release; the release that shipped a feature is in
[releases.md](releases.md).

## Release and QA

- [releases.md](releases.md): CI gates, signed candidate, prerelease and stable
  workflows, RC handoff, signing, release-note policy; per-release record.
- [prerelease-notes.md](prerelease-notes.md) and [stable-notes.md](stable-notes.md):
  release-note bodies the publish workflows read; images in `media/`.
- [runtime-qa.md](runtime-qa.md): QA method, environments and what counts as
  native evidence.
- [performance-gate.md](performance-gate.md), [ADR0032](decisions/0032-release-performance-gate.md),
  [performance-reference-qualification.md](performance-reference-qualification.md)
  and [ADR0033](decisions/0033-controlled-reference-performance.md): performance
  budgets and how a candidate qualifies.
- [dependencies.md](dependencies.md), [android-toolchain-maintenance.md](android-toolchain-maintenance.md)
  and [ADR0020](decisions/0020-build-dependency-repository-routing.md): dependency
  inventory, update review and Android build routing.

## History

Historical records, kept unchanged in [archive/](archive/). Not requirements;
later decisions supersede them. Their relative links were written for `design/`.

- Logs: [status-history.md](archive/status-history.md),
  [runtime-qa-history.md](archive/runtime-qa-history.md).
- Earlier specs: [product-behavior](archive/product-behavior.md),
  [storage-and-sync](archive/storage-and-sync.md), [tech-stack](archive/tech-stack.md),
  [storage](archive/storage-and-sync-before-coordinated-cutover.md),
  [schema](archive/schema-before-coordinated-cutover.md) and
  [recovery](archive/recovery-before-coordinated-cutover.md) before the cutover;
  [review.md](archive/review.md) (2026-09-30 architecture review);
  [next-task-parity-draft.md](archive/next-task-parity-draft.md).
- Proposals and investigations: text merge ([investigation](archive/text-merge-investigation.md),
  [prototype](archive/text-merge-prototype.md), [options](archive/text-merge-adoption-options.md)),
  [unified-log-adoption-proposal](archive/unified-log-adoption-proposal.md),
  [agent-interface-feasibility](archive/agent-interface-feasibility.md),
  [date-time-layout-investigation](archive/date-time-layout-investigation.md),
  [android-reconciliation-review](archive/android-reconciliation-review.md),
  [historical-recurring-text-policy](archive/historical-recurring-text-policy.md),
  [bulk-stale-warning-visibility](archive/bulk-stale-warning-visibility.md),
  [followon-20261031](archive/followon-20261031.md), [ux-improvements-20261026](archive/ux-improvements-20261026.md).
- Readiness and UX audits: [stable-readiness](archive/stable-readiness.md),
  [stable-readiness-review-2026-10-02](archive/stable-readiness-review-2026-10-02.md),
  UX audits [rc2](archive/ux-audit-rc2.md), [rc3](archive/ux-audit-rc3.md), [rc4](archive/ux-audit-rc4.md).
- Candidate handoffs and native acceptance: [android-text-preview-qa](archive/android-text-preview-qa.md),
  [checklist](archive/checklist-native-acceptance.md), [historical checklist](archive/historical-checklist-native-acceptance.md),
  [shared history](archive/shared-history-native-acceptance.md), [shared tag](archive/shared-tag-native-acceptance.md),
  [local DB](archive/local-db-native-acceptance.md), [Food](archive/food-native-acceptance.md),
  [Food RC3](archive/food-rc3-native-acceptance.md), [final preview](archive/final-preview-acceptance.md),
  [final preview debug QA](archive/final-preview-debug-native-qa.md), [rc4 build47](archive/rc4-build47-replacement.md),
  [frozen stable checkout](archive/frozen-stable-checkout.md).
- Dependency and release one-offs: [dependency patches 10-11](archive/dependency-patches-2026-10-11.md),
  [PR8 disposition](archive/pr8-dependency-release-disposition.md),
  [Kotlin 2.4.20](archive/kotlin-2.4.20-remediation.md), release notes
  [2026.10.3](archive/release-notes-2026.10.3.md), [2026.10.4](archive/release-notes-2026.10.4.md),
  [date-layout preview](archive/date-layout-preview-notes.md).
