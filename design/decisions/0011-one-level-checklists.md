# One-level task checklists

Status: accepted product scope from Lee. The inline interaction revision was
approved on 2026-10-08 and is under independent/native acceptance on a separate
branch. Preview rc.4/build47 remains released unchanged; stable promotion remains
Lee's decision.

## Scope and interaction

A task can contain one level of checklist items. Each item has a title, optional
notes, a checkbox and shared order. Items cannot contain items, schedules, tags
or assignees. Checklist title and notes use the existing native collaborative
text adapter with an item-scoped UUID and the ordinary title/description field
identities. Item editing has explicit Save/Cancel; adding/editing an item is a
separate durable action from the parent task editor. Do not imply cross-entity
atomicity. Resolve private item drafts through Save/Discard/Cancel before leaving
or invoking task Undo. A saved item action participates in scoped session Undo;
creation follows existing capture semantics.

Warn before completing a task with unfinished items. Cancel writes nothing;
Complete anyway is explicit. Confirmation observes the actual checklist snapshot.
Refresh/reconcile before append; an incoming item/status change requires review
and renewed confirmation. Checkbox, keyboard and any future bulk completion must
use the same application path. Import/replay never invents a confirmation or
revalidates history against current UI/time.

## Inline interaction revision accepted 2026-10-08

Lee approved moving checklist controls out of the parent editor. A parent with
items shows completed/total plus disclosure and defaults to collapsed; its
expanded children are below the row, outside parent selection, keyboard focus
handling and task reorder/drop geometry. Item drag data is typed and scoped to
one parent, workspace instance, rendered revision and observed order. The
command refreshes and rejects a changed snapshot before preparing its receipt.
Items retain independent native draft/IME/receipt ownership and Save/Cancel.
Checkboxes, editable titles, optional one-line notes, confirmed direct Delete
with Undo, and a bottom Add item control have separate accessible hit targets.

The task menu is immediately left of the far-right parent drag handle. The same
Add checklist/Delete task menu is available through right-click and Context
Menu/Shift+F10. It always targets the invoked parent, preserving other selected
rows. Add checklist is present only when the parent has no items, including while
incoming changes arrive with a menu open. On an empty parent it opens an empty
block and focuses bottom
Add item, without creating a draft or canonical event. Deletion resolves private
drafts and confirms the named parent, preserving existing receipt and Undo rules.

The toolbar is an immediate next-action toggle: if any currently shown checklist
is expanded, collapse shown checklists; when all are closed, expand them. Its
icon and accessible tooltip say Expand shown checklists or Collapse shown
checklists. It follows filters, individual disclosures and incoming item changes;
hidden parents retain their local state. Sparse expanded-ID
entries live in the existing workspace SQLite metadata table; collapse removes
them, no new settings file/schema/version is introduced, and cache loss resets
the preference. Broader local-storage consolidation is queued for the next full
release, with inventory and migration review before implementation.

The earlier editor-only location hid item work behind parent editing and implied
an unnecessary ownership relationship. Always-expanded children would reduce
list density. A combined menu/drag hit target would make activation ambiguous;
separate controls keep touch and keyboard intent clear. Revisit density and
Android discoverability after bounded native use. The2026-10-09 follow-up matches
parent/child drag icons, removes child long-hold tooltips, aligns trailing targets,
and uses the actual available content width for compact rows/dividers below600px.
Disclosure content starts two pixels after the last body line; its visible arrow
edge starts at the text column. Lee approved a disclosure-specific compact target
on2026-10-09 to match the ordinary secondary-text bottom gap:2px above the count
and6px below it. Its minimum width remains48 logical pixels; its content-driven
height is about28 at normal text and48 at200% text. This is an intentional
exception to the engineering48px target policy, not a change to parent-body,
completion, menu, reorder or child-item targets. The arrow's visible left edge and
shared vertical center are retained; its internal count gap is tighter. Centered
rounded rectangular ink is painted independently of the nonoverlapping hit
rectangle. No hit area is borrowed from body text or another row. Revisit the
exception if native touch use exposes activation difficulty; exact native and
independent gates remain required before publication.

## Identity, persistence and recurrence

Required additive event types describe item creation, completion state, relative
movement and deletion. Released scalar v3 records, hashes, clocks, IDs and Undo
meanings remain unchanged. Unknown required types stop older peers explicitly.
Item creation names a parent task in the same space. Native item text uses the
unreleased field adapter's existing text-edit and selective-Undo records, with
item-kind admission restricting them to title/notes. All task-only operations
remain invalid on items. Missing remote parents/anchors remain dependencies;
known wrong kinds, nesting or cross-parent anchors are invalid transactionally.

`task.completedWithChecklist` carries the usual successor task snapshot and an
immutable observed-prefix checklist copy. Native parents additionally carry the
ordinary parent-text inheritance proof. Scalar parents retain scalar successor
initialization: native items do not silently require a shared parent baseline.
Each copied ID is UUIDv5(successor task ID, `checklist:<source item UUID>`). Each
copy starts unchecked and belongs to the successor. Its native field context
inherits the original source context and shares original operation references;
no growing packet arrays or full inherited BLOBs are embedded.

Verify exact visible source membership/order at the declared prefix, source
parentage, IDs, rendered text and native proofs. Reject duplicate/forged sources
and collisions with independent creations. Proofs support sources copied through
earlier generations. Concurrent completions produce one successor and one copy
per observed source, union observed native contributions and preserve successor
text/checks/deletes/moves. Later old-occurrence changes do not flow forward.
Undo does not unmerge inherited native text. Historical recompletion retains the
existing independently initialized child, including scalar-mode checklist
completions; it does not add another checklist copy.

Copied initial order derives deterministically from immutable completion
contributions, using the earliest total-order contribution as the primary list.
Items absent there join deterministically from later contributions. Apply
child-owned relative moves afterwards, including delayed same-parent anchors;
a late contribution cannot overwrite an acknowledged child move.

Untouched copies follow the existing conditional successor suppression policy.
Any durable child-item history protects the successor task, even when that item
action was later undone/deleted. Private drafts are resolved by the UI; they do
not become fictional canonical activity. Suppression/restoration of the task
governs visibility of its entire checklist.

Canonical records retain the existing one-MiB byte cap and bounded item/text
admission. Prevalidate aggregate copy bytes before a receipt is prepared.
Cache-only projection/index changes preserve canonical history and committed
byte/identity guards. Warm/cold rebuilds must agree with no canonical mutation.

## Alternatives and remaining gates

A single last-writer-wins checklist array would lose concurrent item edits and
make order/status writes replace unrelated content. Encoding checklist items as
ordinary independently listed tasks would leak task schedules/assignees/nesting.
Separate item identities reuse hardened text ownership without a generic module
framework. Atomic multi-entity editor Save would add a protocol transaction;
explicit item actions fit the existing independently durable command boundary.

Independent architecture preflight called out scalar-parent mode, strict kind
admission, descendant Undo protection, exact membership/proofs, historical
scalar-mode initialization and child-owned order preservation. Freeze those
gates before implementation. Final compatibility/security/correctness review,
native narrow/enlarged/themed inspection, pointer-visible Linux demonstration
and exact Android affected-flow acceptance remain required.

Owner: Tandemlog implementation coordinated with Lee. Revisit item/payload bounds
or editor interaction after actual native use, and before stable checklist
promotion. The existing quadratic prefix-processing debt remains separately
documented; do not start an open-ended optimization loop within this feature.
