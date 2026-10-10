# Food inventory alongside tasks

Status: Lee approved phased implementation on the stable2026.10.3 base and an
early working preview before layout freeze. Product scope below is accepted;
visual refinements remain provisional. The original slice is synthetic and
process-local; the durable implementation now uses production navigation and the
shared profile DB. This is unreleased work, with native and release gates open.

## Context and accepted scope

Food is a second capability alongside tasks with Tandemlog's visual language.
It must work offline, preserve all released task v3 records, hashes, clocks,
IDs and meanings, and use the established app-wide local DB.

Ordinary dated stock has one globally expiration-ordered list. Identical name,
brand, expiration, estimate status, retention reason, location and nominal size
can form a display group. Grouping never replaces physical identities. Each
container has its own stable ID and remaining contents. Count is derived, not
an editable quantity. Add N creates N fresh identities; different dates or
descriptive fields remain separate rows.

Undated food stays in a needs-expiration Inbox until a known or estimated date
is supplied. A retention reason hides food from ordinary stock even before
expiry. Retained reason sections start collapsed. Assigning and filtering
reasons reuse the shared tag-style autocomplete. Active search matches all
terms across descriptive fields and bypasses normal view/reason filters.
Deleted search is explicit and never restores results.

Deleted containers remain available without an age cutoff. Restore preserves
identity and contents across days and restarts; session Undo complements it.
Removal captures observed physical targets. An unseen concurrent container is
not removed, two removals of one ID count once, and Restore of observed deletion
tokens does not undo an unseen concurrent deletion. Quick Remove one is
available only for identical full containers. Different or partial contents
require explicit selection; whole-group removal shows its observed composition
and target count before confirmation.

Brand is separate; location and nominal size are optional. Remaining contents
are per container. The provisional example is seven full containers plus one
third-full container: `7 full + 1 container ⅓ full`, with eight physical IDs visible in
inspection. Exact fractions and measured amounts retain their units. No automatic
unit conversion or quantity redistribution is approved. Concurrent contents
alternatives remain visible until an observed resolution.

Assignees, catalogs, nutrition calculations, receipt AI and Duplicate are outside
this implementation. Import is private and separately controlled: only approved
whole-container suffixes and the exact approved literal brand list may be
extracted. Preserve all other source text/fields and source identity. A
deterministic source-ID/container-ordinal mapping makes retries idempotent.
The [generic app-side v1 contract](../food-import-contract.md) is authorized in
Git; private extraction rules, whitelist, staging originals and private source
data stay outside Git. No live import or synced user-data operation is authorized here.

## First slice and provisional UX

`lib/food/inventory.dart` is a pure operation/projection model, independent of
transport, SQLite, wall time and UI. It handles observed deletion/Restore,
per-field descriptive changes, exact contents alternatives and duplicate or
reordered delivery. Its DTO is a prototype, not an accepted canonical wire format.

`lib/food/food_page.dart` captures observed targets and delegates changes to its
host. `tool/food_preview.dart` supplies synthetic process-local stock, bounded
command batches and session Undo. It opens no profile or sync folder. The preview
offers full, half, third, quarter and unknown contents. Arbitrary measured-amount
editing remains later implementation. Production navigation now offers Tasks and
Food in the same selected workspace. Container inspection labels use stable ID
suffixes rather than list positions. The wide Food surface caps at900px and expiry
has a stronger scan emphasis.

Lee's early-preview feedback requested materially shorter rows. Collapsed rows
now pair name and stock summary, then expiration and brand. Size, location,
physical count and group-detail/whole-group actions appear after Inspect; quick
Remove one remains directly available for identical full containers. No text size
was reduced. Food action targets now explicitly measure48px (the previous
inherited icon style measured40px). In the same12-group Linux fixture, normal
rows including their margins are64px versus112px before; fully visible groups
increase from5 to10 at390×850 and6 to10 at1200×850. The wide surface stays900px.
Both themes and200% text grow naturally without overlap. This is an automated
native layout result, not Android/Windows or human-user acceptance. The [early preview evidence](../../evidence/food-inventory-first-slice/README.md)
records actual narrow/wide Linux pixels and tested workflows before layout freeze.

## Implemented storage boundary; unreleased

Food streams use `food-<writer>.foodlog`, outside the task reader's `*.jsonl`
namespace. Closed version1 envelopes bind workspace, writer, sequence, exact
signed64 clock, operation, target creation basis, predecessor and SHA256 digest.
Canonical record JSON is bounded to256KiB. The module hash domain is
`tandemlog:food-record:v1\n`; sequence0 uses the existing workspace/writer genesis
hash. The food writer is UUID-v5 of the installation writer and the fixed name
`tandemlog:food:v1`. Neither this identity nor Food clocks enter task v3 streams.

Schema3 adds exact protected Food intents, stream heads and location bindings to
`LocalProfileDatabase`'s owning connection. Frozen schema2 fixtures verify existing
protected task/settings/cache bytes and rollback of a partial upgrade. The module
uses the owner's queue and a separate food-location lease; it opens no second DB.
Reserve writer authority and exact recovery bytes in one transaction before
provider append. Retire only the exact admitted read-back in the acknowledgement
transaction. A durable own-writer initialization witness prevents a missing guard
from being silently treated as new. SQL contains recovery authority; derived food
state is rebuilt in memory from verified canonical history.

Reads require a bounded transport, with limits of256 streams,16MiB per stream,
32MiB total,50000 records and100000 physical containers. Local and Android reads
bound allocation before delivery. Canonical names, actor chains, hashes, clocks,
creation identity and observed references are checked before head advancement.
Missing dependencies remain explicitly pending and block commands. Invalid known
references reject the candidate view. Restore and contents edits capture observed
references; large sets use bounded reference chunks without expanding observation.
An interrupted append retains its immutable bytes and only its exact missing
suffix may be retried, with the same limits as a new append. Neither startup nor
refresh automatically creates new inventory or retries a write.

All protected authority is validated before a remote history failure can be
classified as isolated; the own guard and trusted head must align exactly. Every
refresh rechecks shared identity before returning a module-only failure.

Editor Save awaits durable command admission and retains a failed draft. A
prepared Save freezes its fields for exact retry; it cannot open another Add/Edit
instead. Closing a changed draft requires a decision. Host callbacks retain their
rendered workspace origin, and handle close drains admitted work even when the
profile owner is poisoned. Session Undo applies only admitted local removal tokens.
Legacy expiration certainty may remain unknown (`null`); no source import occurs.

Startup distinguishes isolated Food history/transport admission failures from
shared safety faults. The former leave Tasks usable with a Food error surface and
explicit retry; the latter prevent opening the workspace. Food writes require a
fully admitted handle. Runtime refresh keeps module projections independent and
preserves each last good view. Canonical manifest changes, invalid installation
identity and shared DB failures are never downgraded to a Food-only warning. A
hard foreground failure stops new host commands and preserves the mounted editor
behind a recovery overlay; existing private drafts stay in memory. Commands
waiting for refresh and retained Save callbacks recheck safety before admission.
The recovery panel scrolls at enlarged text and keeps Retry reachable. Explicit
Retry keeps writes blocked while revalidating the same profile, installation
writer and workspace, then Tasks, Food and Tasks again. It neither appends nor
retries prepared operations. Exact restored identity can resume the existing
draft; lost guards/receipts or a poisoned owner remain blocked. Existing Food
handles and observed pending intents survive an isolated history failure.
The first-name setup form alone preserves local typing and focus during a stop;
its diagnostic is bounded and scrollable. Continue preserves the pending user
identity and performs the same bound read-only admission before user creation.
The existing-user picker and all other command callbacks remain blocked. On
phones the module selector yields space while a Task editor's software keyboard
is visible, preserving the existing caret viewport and touch targets.

The expiration editor uses a short permanent "Expiration" label and a wrapping
helper containing the calendar format and blank-date Inbox destination. Native
320dp/200% acceptance found that the former long label and two-line helper hid
both instructions. Allowing helper growth inside the existing scrollable form
preserves font size and touch targets; shrinking text or redesigning unrelated
fields is unnecessary. Add/Edit share the same decoration and validation.

A second actual320dp/200% Gboard-open check showed that even the two-line
Edit1 title could consume all available space when held outside the field
scroller. The title and fields now share AlertDialog's constrained scroller,
with actions outside it; shortening the title alone would leave the same combined
IME/large-text failure. Dirty-close confirmation uses the same bounded pattern.
The obscured page and closing-keyboard transition keep their geometry stable;
the current page resizes while an attached text input has focus. A dialog-scoped
viewport-change notification reveals its own focused input after animated insets
finish resizing. It neither changes user text nor forces focus. Tests require
an already-focused editable line to remain visible before manual scrolling,
and preserve draft, error and observed-target Save behavior. A disconnected focus
element is rejected before ancestor traversal. Revisit this bounded mechanism if
real keyboard timing or pending-save/recovery overlay evidence reveals a gap.

## Validation and remaining gates

Focused domain/widget regressions cover physical identity, partial grouping,
observed targets, concurrent deletes/Restore, reordered/duplicate replay, field
merging, contents conflicts, retention search and draft safety. Independent
architecture/correctness/security/UX reviews distinguish first-slice acceptance
from production durability.

Before publication: final storage/recovery and production host acceptance, both themes and large text, keyboard
and touch flows, exact artifacts, actual Windows/Android affected workflows and
visible-input demos, and independent notes/media review. Linux narrow captures
do not establish Android acceptance. Lee's quota overrides apply only to this
food release; quality, security and artifact gates remain mandatory.

## Alternatives, consequences and revisit trigger

A mutable aggregate quantity cannot identify one physical container across
offline removal/Restore or preserve partial contents. Physical IDs make these
operations explicit; grouping keeps everyday scanning compact. A separate food
database would violate the app-wide local DB direction. Routing food through task
JSONL would break existing task stream discovery.

Revisit density/wording after the denser preview and larger real inventories.
The menu behind Inspect trades direct secondary-action discovery for compact
everyday scanning; retain this as provisional until Lee sees the revised preview. Revisit
record/receipt boundaries if crash, replay or native-provider evidence requires
change before the unreleased format is frozen.
