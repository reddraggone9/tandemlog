> Historical review. Lee subsequently approved Flutter/Dart and portable file synchronization; see [ADR 0001](decisions/0001-client-and-storage.md). Open questions here may be superseded.

# Architecture review — 2026-09-30

**Proposal for Lee; no application implementation or stack commitment made.**

## Recommendation

Build a modular local-first application, beginning with tasks. Keep Rust for deterministic domain rules and persistence. Provisionally retain Dioxus's WebView renderer to honor the existing Rust direction, but gate adoption on a narrow Android storage/lifecycle and Windows runtime spike. Do not choose a UI framework as if it solves synchronization. If fastest polished mobile delivery matters more than a mostly Rust codebase, prefer Flutter with a single Dart domain implementation and SQLite; do not add Rust FFI merely to preserve a language choice.

Retain external Syncthing only if separate setup and a trusted household folder are acceptable and actual Android devices pass the shared-folder test. Keep logs canonical and use one private SQLite cache. Remove the independently persisted JSON snapshot until measurements justify it. Browser preview is useful, but a production web storage/sync implementation should not be a prerequisite for native testing.

## Conflicts and important gaps in the original documents

| Original assumption | Assessment and proposed correction |
| --- | --- |
| Tasks and time define the product; timers come next and dominate Home | Superseded. Tasks are the first module; time tracking has no scheduled milestone. No timer UI now. |
| Initial version includes recurrence, sophisticated dates and shared ordering | Too broad for the accepted persistence slice. Preserve ideas in archive; add them in later reviewed increments. |
| Any existing folder is valid; no further onboarding | Not a cross-platform promise. Validate app-owned namespace, format, write capabilities and access; Syncthing pairing is separate setup. |
| Thin OS code | Good boundary, unjustified effort estimate. SAF, grants, lifecycle, camera/voice and notifications can need substantial native work. |
| Per-node files plus total order settle conflicts | They help transport and repeatability. They do not define correct undo, recurrence, quantities, restore, or multi-entity atomicity. |
| Snapshot offsets and SQLite history persist independently | Crash can make them disagree. Transactionally store history, projections and checkpoints in one SQLite cache. |
| Invalid final line can be truncated | Only a proven incomplete owned tail after exclusive access; a complete malformed event needs visible recovery, not silent deletion. |
| Delete is terminal; undo recreates identical data | Same ID stays deleted; a new ID breaks references. Defer deletion and explicitly design restore before adding it. |
| Nanosecond clock identifies events and provides recency | Deterministic but vulnerable to bad future clocks, cache rollback, overflow, and JS precision. Separate durable event identity, logical ordering, and displayed wall time. |
| Rebuild only each touched entity | Fine for isolated tasks; future food/inventory commands require dependency-aware or transactional projection updates. |
| Unknown event prevents all initialization | Too coarse for independent future modules. Preserve raw data and fail closed for unsupported required semantics; show safe read-only/recovery information. |
| Web OPFS implies access to Syncthing folder | OPFS and user-selected external folders are different APIs. Defer production web sync. |

## Hard constraints versus preferences

**Hard technical constraints:** Android SAF is URI-based and restricts selectable locations; universal arbitrary-folder support is false. Fully independent offline consumers cannot guarantee a globally nonnegative stock balance without coordination or preallocated rights. A shared plaintext folder is not per-user access control. Native runtime verification requires a native runtime.

**Feasibility gates, not proven impossibilities:** Android shared-folder interoperability after replacement/reboot; selected Android Syncthing wrapper maintenance and setup; Dioxus native integration; Windows packaging and actual UI behavior. This environment cannot currently satisfy native QA gates.

**Preferences:** Rust versus Dart, Dioxus versus Flutter, external sync versus a small service, one-file logs versus sealed batches. Their costs deserve explicit choices rather than being disguised as requirements.

## Decisions for Lee

1. Is direct phone-to-phone, no-server operation a hard requirement, and is separately configuring a maintained Syncthing client acceptable? Recommend retaining it conditionally. If not, revisit an authenticated outbox push/pull service; that changes availability/operations and cannot silently replace offline hotspot exchange.
2. Is a mostly Rust codebase a priority worth Android adapter work, or is shortest path to a polished mobile app the priority? Recommend Rust/Dioxus only with the device spike; otherwise Flutter/Dart. No dual UI implementation.
3. Are all household members trusted to read every module's data? Recommend explicit shared-workspace semantics for tasks, but do not assume food/weight records may be shared. Also clarify whether “MacroFactor-like” includes adaptive expenditure/coaching or mainly logging/search/weight trends; this does not block the task milestone.

The reviewed first milestone and evidence gates are in [product behavior](product-behavior.md). Future module semantics must be reviewed before their schemas, not implemented preemptively.
