# Review before stable 0.1.0

Status: required review, not authorization for stable publication, source cutover, deletion or history repair. Markdown remains authoritative through prereleases. Test contents are disposable; the sync path/share remains permanent. Coordinate the latest source freeze, backups, device/app handling, fresh import and independent validation before a final handoff.

Before promising stable compatibility, review these hard-to-change data decisions with Lee against real workflows and test evidence:

- Event admission/version evolution: closed required schemas, additive peer-update behavior, supported historical fixtures, explicit unsupported records and cache-only migrations.
- Identity and attribution: writer/device versus active person, Lee chose device-only event attribution. Review writer/device permanence, optional advisory device-to-person naming, display-name resolution and user rename/deletion/history retention. Current data has no acting-user field, and none is planned for this candidate. Attribution is a claim, not authentication or tamper protection; never infer historic actors from assignees. Device-signed logs are a future idea only: key lifecycle, integrity, deletion and rollback detection need separate design/authorization; no keys or signing infrastructure are implemented.
- Total ordering/clock/conflicts: approved exact wall-clock/causal scalar, observed-causality guarantees, immutable imported timestamps, skew warnings and concurrent register/tag/order/completion behavior. Coordinated history repair remains a deferred decision.
- Undo/reversal: named contribution retraction, independent later writes and recurring successors, partial durable confirmation, session boundary and unsupported older-peer behavior. Cross-restart action history, redo and audit rollback remain deferred.
- Recovery/backup: full canonical-folder backups, writer/profile isolation, known-cache rebuild guards, altered/deleted log detection, interruption and restore/rejoin paths, signing identity and uninstall/installability.
- Validation: exact installed candidates, native Android lifecycle/SAF/provider and desktop coverage, task-based UX review, retained tests for convergence and crash/recovery, documented limits and Lee's acceptance.

Record each accepted compatibility promise and unresolved gap before stable gates. Do not turn this checklist into speculative implementation or change prerelease data without an explicit action.

The [2026-10-02 independent review](stable-readiness-review-2026-10-02.md) records concrete durable-creation and conditional SAF-name findings, remaining provider/restore evidence, the actual review mechanism and the conditional version-only stable promotion path. RC7 remains an experimental candidate pending its exact gates; the review does not authorize a cutover.
