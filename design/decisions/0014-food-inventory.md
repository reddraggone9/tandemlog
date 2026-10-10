# Food inventory alongside tasks

Status: Lee approved phased implementation on the stable2026.10.3 base and an
early working preview before layout freeze. Product scope below is accepted;
row density and partial-stock wording remain provisional. The first slice is
synthetic and process-local. Production durability and release gates remain open.

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
third-full container: `7 full + ⅓ remaining`, with eight physical IDs visible in
inspection. Exact fractions and measured amounts retain their units. No automatic
unit conversion or quantity redistribution is approved. Concurrent contents
alternatives remain visible until an observed resolution.

Assignees, catalogs, nutrition calculations, receipt AI and Duplicate are outside
this implementation. Import is private and separately controlled: only approved
whole-container suffixes and the exact approved literal brand list may be
extracted. Preserve all other source text/fields and source identity. A
deterministic source-ID/container-ordinal mapping makes retries idempotent.
The contract, whitelist, staging originals and private source data stay outside
Git. No live import or synced user-data operation is authorized here.

## First slice and provisional UX

`lib/food/inventory.dart` is a pure operation/projection model, independent of
transport, SQLite, wall time and UI. It handles observed deletion/Restore,
per-field descriptive changes, exact contents alternatives and duplicate or
reordered delivery. Its DTO is a prototype, not an accepted canonical wire format.

`lib/food/food_page.dart` captures observed targets and delegates changes to its
host. `tool/food_preview.dart` supplies synthetic process-local stock, bounded
command batches and session Undo. It opens no profile or sync folder. The preview
offers full, half, third, quarter and unknown contents. Arbitrary measured-amount
editing and production navigation remain later implementation.

Cards currently show name, metadata, contents and expiry with inspection for
physical selection. Wide density, expiry scan emphasis and partial-stock wording
remain review questions. The [early preview evidence](../../evidence/food-inventory-first-slice/README.md)
records actual narrow/wide Linux pixels and tested workflows before layout freeze.

## Planned storage boundary; not yet implemented

Keep food streams outside the task reader's `*.jsonl` namespace. Reviewed
direction: `food-<writer>.foodlog` containing closed, versioned, hashed records
with a distinct module hash domain. Derive a separate stable module writer from
the installation writer with one fixed UUID-v5 name. Bind operation identity
and order to verified record writer, sequence and clock, rather than trusting
DTO fields.

Use `LocalProfileDatabase`'s owning connection, queue and a separate food location
lease. Add protected exact pending food receipts and stream authority with a
checked schema migration preserving existing protected task state. Reserve and
freeze exact bytes before append. Retire them only with exact admitted canonical
read-back in the owning transaction; rebuild only derived food state.

Production admission must bound records/delivery, validate causal and target
references, retain unresolved references explicitly, reject aliases/duplicate
streams and inconsistent actor chains, and recover ambiguous append outcomes.
The task reader's conservative synced-conflict handling may still block the
workspace. This plan does not promise complete module fault isolation.

## Validation and remaining gates

Focused domain/widget regressions cover physical identity, partial grouping,
observed targets, concurrent deletes/Restore, reordered/duplicate replay, field
merging, contents conflicts, retention search and draft safety. Independent
architecture/correctness/security/UX reviews distinguish first-slice acceptance
from production durability.

Before publication: durable storage/recovery and compatibility fixtures,
production host/workspace/draft boundaries, both themes and large text, keyboard
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

Revisit density/wording after early feedback and larger-inventory trials. Revisit
record/receipt boundaries if crash, replay or native-provider evidence requires
change before the unreleased format is frozen.
