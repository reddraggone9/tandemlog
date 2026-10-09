# Food inventory: proposal for review

Status: planning only. No food implementation or private vault records in this change. Single-DB persistence remains the primary implementation work.

## Established behavior

Main inventory displays dated entries in expiration order, with initially collapsed groups. Undated entries remain visible in a needs-expiration inbox; moving into main inventory requires a known or estimated date. A retention reason hides an entry from the normal list even before it expires. Search ignores the normal assignment/reason filters, matches all terms, and surfaces retained active entries. Assignment and reason filtering should use the shared task-tag-style autocomplete.

Deleted is a separate durable view, newest deletion first, without a short cutoff. Delete records `deletedAt`; Restore clears it across days and restarts. Session Undo complements this durable restore. Active search excludes deleted entries by default; search within Deleted is explicit and never restores matching records. Retained active entries remain part of active stock; deleted entries do not. No consumed/discarded distinction is introduced in this version.

## Small data model and proposed controls

Keep an inventory entry's identity, display name, created timestamp, calendar expiration (including the existing datetime case), estimate status, retention reason, assignment, optional location and deletion state. Preserve imported source identity and distinct source entries, including repeated names with different expirations. Expiration-ordered rows are a projection requirement; they do not require one underlying record per container or a product catalog.

Keep **container count** separate from **size per container**: `3 bags × 3 pounds` is count 3, optional container label bags, and decimal size 3 pounds. Neither is inferred from the other. New-entry proposal: default to one container, with label and size optional. Unknown imported quantity remains unspecified until normalization/review supplies it; do not invent a batch count or package units. This default still needs review.

Proposed Add/Remove controls adjust whole-container counts using uniquely identified additive operations. Offline adjustments count once each; concurrent overdraw is visible for reconciliation rather than silently clamped. A count correction records its observed baseline so unseen concurrent adjustments survive. Metadata editing follows explicit field rules; it must not replace the adjustment ledger.

Leave room for multiple expiration cohorts and eventually partial containers. Future nutrition logging would decrement contents, probably from earliest expiration, and must distinguish container removal from contents consumption. It needs explicit allocation/remaining-content semantics before implementation; never reinterpret historical container adjustments as mass. No recipes, nutrition engine, catalog abstraction, receipt parsing or automatic unit conversion in the first version.

## Import and decisions before implementation

The one-time importer and private normalization artifacts stay outside the repo. Parent found 119 clear per-container size candidates and 37 ambiguous entries among 399 active entries. Whether `xN` means whole containers, or an absent suffix means one, remains unanswered: do not infer either. The proposed optional source fields are `containerCount`, `containerSize`, `containerSizeUnit`; original per-container size is distinct from remaining contents. Keep source names intact in staging and strip only confirmed quantity text at cutover.

Use the approved normalized names/fields, preserve source IDs, created times, calendar expiration and retention, and import all nondeleted entries without merging lots by name. Deleted notes and physical trash are excluded. Known versus estimated expiration is unknown for legacy data unless normalization supplies evidence. The existing source Duplicate action does not copy the new optional fields; account for that during the freeze/reconciliation. Proposed new-app Duplicate copies confirmed count/size alongside name/date, creates a fresh identity and clears retention/deletion state; this extension needs review.

Before cutover: freeze source editing, snapshot, reconcile counts and every normalized field, then verify idempotent source-ID mapping. Decisions still required: the new-entry one-container default, ambiguous normalized quantities/units, grouping presentation, and the exact concurrent correction/deletion conflict rules. Reviewed storage must use a separate canonical food namespace while preserving released task records.
