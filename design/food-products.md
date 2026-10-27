# Food as products — design proposal

Status: **Proposed, not accepted.** Design only; nothing here is implemented,
scheduled or released. Lee's 2026-10-27 decisions are the requirements; the
choices that still need him are collected under [Open decisions](#open-decisions).
Once accepted, the consequential parts become an ADR and the behavior moves into
[product-behavior.md](product-behavior.md), [schema.md](schema.md) and
[storage-and-sync.md](storage-and-sync.md); this page then becomes rationale.

## Goals and fixed requirements

Goals (Lee, 2026-10-27): unify containers that are the same SKU; link receipt
prices to inventory and, once consumption logging exists, cost per meal; link an
item to its store page; keep staples in stock with a low-stock alert. Keep the
existing Food UX ("less is more"); change only what these goals need.

Already decided by Lee, not reopened here:

- A **Product** record describes a SKU. Containers point to it.
- **Prices belong to Purchases, not Products.** A Purchase is one receipt line:
  date, store, price paid and quantity. It links to its Product and to the
  containers it produced. One container is the unit the store sells (a 15-bar
  box is one container); container cost = line price / receipt quantity.
- Keep-in-stock minimums are **per Product**, with no groups.
- "Container size" moves to the Product **unchanged** (freeform text). It is
  restructured only with consumption logging.
- Products show only derived money figures (last and typical price).
- Meal cost and partial containers wait for consumption logging. Cost per meal
  will use the consumed container's own Purchase and estimate from recent
  Purchases only when none is linked.
- Receipts arrive through Vex's YNAB itemization workflow; Tandemlog does not
  parse receipts.

## 1. Data model

| Record | Identity | Fields | Changes how |
|---|---|---|---|
| Product | UUID | name, brand, size ("Container size"), store links, keep-at-least minimum | per-field last-writer-wins; merge alias |
| Purchase | UUID (deterministic for imports) | product, date, store, price paid, quantity, source, voided | per-field last-writer-wins |
| Container (existing) | existing UUID | expiry, retention, location, legacy contents; **new:** product, purchase | existing rules; new link fields last-writer-wins |

Relationships: Container → Product (exactly one, explicit or implicit); Container
→ Purchase (optional); Purchase → Product (one). Several containers can share one
Purchase. Product → Product only through a merge alias.

### Which fields move

- **name, brand, size** describe the SKU and move to the Product. For a linked
  container the Product's values are authoritative. The container's own
  descriptive values from history stay readable and unchanged; they are simply
  not displayed while a Product supplies them.
- **expiry, retention, location** stay on the container. They are facts about one
  physical item.
- **contents** (legacy fractions/amounts, no UI since ADR0022) and the legacy
  `estimated` flag stay on the container with their original meaning.
- Category is not added (see open decision 9).

### Implicit products for existing containers

Every container that has no explicit product link belongs to an **implicit
product** whose ID is derived, not stored:
`UUIDv5(space, "tandemlog:food-product:implicit:v1\n" + canonical JSON [name, brand, size])`
over the container's own current descriptive fields. Its fields are those same
values. Containers with identical name/brand/size therefore share one product,
exactly as they share rows today (the current row key is these fields plus
expiry/retention/location).

An implicit product needs no record until someone changes something that
belongs to the product (rename, store link, minimum, merge), or until a new
container or Purchase links to it explicitly. That change first
**materializes** it with a `product.create` carrying the derived ID and derived
fields. Two peers materializing the same implicit product write byte-equivalent
values, so the duplicate is harmless (see conflict rules). This is what makes
migration free; see [section 3](#3-migration-of-existing-containers).

## 2. Sync-log protocol changes

All new records are ordinary Food operations inside the existing unified action
([schema.md](schema.md)): same envelope (`tandemlog.operation` format 1), same
hash domains, same per-writer chain, observed frontier, size limits and admission.
One user action is still one physical record. New semantics are new **required
operation families**, the mechanism ADR0035 used for completion revision 3.

### New and revised families (module `food`)

- `product.create` r1: `product`, `name`, `brand`, `size`, `links`, `minimum`.
- `product.edit` r1: `product`, `fields` (subset of name/brand/size/links/minimum)
  and their values. Same shape as today's container details edit.
- `product.merge` r1: `source`, `target`. An alias, not a rewrite: it lists no
  containers or purchases.
- `purchase.record` r1: `purchase`, `product`, `date` (civil YYYY-MM-DD), `store`,
  `amount` (integer minor units), `currency` (ISO 4217; UI is USD-only),
  `quantity` (integer containers on the line, 1–1000), optional `source`
  (`{kind, key}`, e.g. YNAB transaction + line).
- `purchase.edit` r1: per-field changes, including `voided` for a wrong line.
- `container.add` r2: as r1, plus `product` and optional `purchase`; descriptive
  name/brand/size are omitted when `product` is present.
- `container.link` r1: `targets`, `fields` (subset of product/purchase), values;
  `null` clears a purchase link. Used for linking existing containers to a
  Purchase and by import tooling.
- `container.undo` r2: the existing additive retraction, allowed to target the
  new families. It retracts an exact operation by reference; Undo of one user
  action still retracts every effect of that action.

`container.edit` r1 stays for expiry/retention/location. The new app never emits
container name/brand/size edits; it edits the Product instead. Existing r1
records keep their meaning.

Bounds (validated before append like today's): text fields keep current limits
(name 500, others 200 characters); up to 4 links, each an `http`/`https` URL of at
most 2,048 bytes; minimum 0–999 or null; amount 0–10^9; at most 100,000 products
and 200,000 purchases per space (same order as the container cap).

### Versioning and older apps

- No manifest change, no new epoch, no conversion: the protocol-5 manifest and
  operation format 1 stay. The new families are required capabilities in the
  same sense as revision 3: a current app that meets an unknown complete family
  stops admission in both Tasks and Food, keeps its last good state and says
  "Update the app; history was preserved" (existing `FoodRecord.decode` path).
- Release notes record this as the next log-protocol level (protocol 5 + "Food
  products" families); the name/number is open decision 8.
- Because one product write stops every not-yet-updated installation, rollout
  is **reader first** (open decision 8): release N ships decoders, projection and
  tests with no way to write the new families; release N+1 enables writing once
  all five installations run N. Release N+1 is format-changing and follows the
  standing rule for those (isolated test workspace on Leela first).
- An offline old installation can keep appending r1 container records. They stay
  valid: their containers fall into implicit products by description.

### Conflicts and merging across peers

Ordering is the existing canonical order (clock, writer, sequence).

- **Product fields, link fields, purchase fields:** per-field last-writer-wins,
  the same whole-field rule Food uses for name/brand/location today.
- **Duplicate `product.create`:** allowed only with identical values (the
  implicit-materialization case). Different values for one product ID are
  corruption and fail closed, like conflicting container births.
- **Merge:** a product's effective identity is found by following non-retracted
  merge aliases in canonical order. A merge whose target currently resolves to
  its source (A→B racing B→A) is ignored, so every peer resolves the same way.
  Chains resolve transitively (A→B, then B→C sends A's containers to C).
- Because a merge is an alias, containers or purchases added to the source
  product on another offline device **still land in the target** when they sync.
  Concurrent edits to a merged-away product's fields are retained but not shown;
  they reappear if the merge is undone.
- **Merge with field choice:** when the user keeps the source's name (or adds the
  source's store link), the same action also carries a `product.edit` on the
  target. One action, one Undo.
- **Merge Undo:** retracting the action retracts the alias and any accompanying
  edit; the source product reappears with all its containers and purchases. No
  container record is touched by a merge, so there is nothing else to restore.
- **Purchase import retries:** imported purchase IDs are
  `UUIDv5(space, "tandemlog:food-purchase:v1\n" + source.kind + source.key)`, so a
  retried or doubled import converges on the same Purchase (identical duplicate
  creates are idempotent; different values for the same source fail the import
  dry run before anything is written).

## 3. Migration of existing containers

**Proposal: write nothing.** The ~595 existing containers (count from Lee's
brief; not re-measured here because this pass touched no data) keep their bytes,
IDs and meaning. At upgrade each one belongs to its implicit product, so rows,
groups, search and filters look exactly as before.

- **No data loss:** no record is rewritten or reinterpreted; the descriptive
  fields remain on the containers.
- **Reversible:** until someone edits a product nothing new exists. Afterwards,
  every product change is an ordinary additive action with ordinary Undo, and
  dropping the feature would only mean ignoring the new families (their records
  remain in history, as all records do).
- **No coordination:** implicit IDs are a pure function of history, so every
  peer computes the same products with no conversion step, owner or race.
- Near-duplicate descriptions ("Milk" vs "milk 2%") stay separate products until
  Lee unifies them with batch edit or a rename (section 5).

Alternatives rejected: an eager one-time "create all products" action (595 links
written, coordination needed, nothing gained over derivation); leaving old
containers outside the product model (two code paths and two grouping rules
forever); an external ADR0031-style conversion (heavy and unnecessary for an
additive change).

## 4. Prices, derived figures and receipts

Money lives only on Purchases. A Product shows two derived figures, computed
from its non-voided purchases (merged products included):

- **Last:** unit cost of the newest purchase, with its date and store.
- **Typical:** median unit cost of the newest 5 purchases in the last 12 months,
  shown only when there are at least 2 (open decision 10).

Unit cost = amount / quantity. A container's cost is its own Purchase's unit
cost; future meal cost uses that, falling back to the product's recent purchases
only when the container has no Purchase.

### Receipt interface (YNAB itemization → Tandemlog)

Same shape as the existing [Food import contract](food-import-contract.md):
private tooling prepares an immutable reviewed plan, the app-side API dry-runs it,
then commits it as one action with `provenance.kind = "food.purchase-import"`.
Plan (v1, interface only):

- `v`, `space`, `importId`, `sourceSha256` as in Food import v1.
- `lines[]`: `source` (`{kind:"ynab", key:"<transaction id>#<line>"}`), `date`,
  `store`, `amount`, `currency`, `quantity`, and a product reference: either an
  existing product ID (explicit or implicit) or a new product's
  name/brand/size/links.
- Optional `containers[]` per line: existing container IDs to link.

The dry run reports per line: matched product, purchase already present
(unchanged / conflicting), and how many units remain unlinked. Vex's workflow does
the matching (it already reads receipts and YNAB); Tandemlog only validates and
commits. The importer never creates containers by default: expiry is required for
Stock, and receipts don't carry it.

Linking containers added later: Add (and Add another) of product P links the new
container to the newest non-voided Purchase of P that has fewer linked containers
than its quantity and is at most 14 days old (open decision 7). It's silent: the
editor shows nothing new, and the link is part of the same Add action.

## 5. Food UX

Principle: the product is mostly invisible. Rows, views and the everyday Add flow
look the same; new controls appear only where the goals need them.

### What does not change

Flat whole-container rows and their metadata; Stock/Retained/Deleted, Inbox,
filters (Brand values now come from products; Location from containers) and
their OR/AND rules; Search semantics (bypasses filters, includes Deleted at the
bottom); required expiry on manual Add; retention on Edit only; Add another
copying everything but expiry and retention; Remove one/Restore one; group menus;
the 50-action Undo stack; container identity and legacy contents.

### Changes

- **Grouping:** a row groups containers with the same *product* plus the same
  expiry, retention and location. For implicit products that is today's key, so
  no row changes at upgrade.
- **Add:** Name autocomplete also suggests existing products as "Name · Brand ·
  Size" (shared `free_text_autocomplete`). On Save, if the name/brand/size match
  an existing product (trimmed, case-insensitive; most recently used wins a tie),
  the containers join it; otherwise the Save creates a product in the same
  action. No new field or step.
- **Add another:** unchanged; it reuses the row's product.
- **Edit (single row):** Name, Brand and Container size now edit the *product*,
  so a typo fix reaches every container of that SKU. When the product has
  containers outside this row, a secondary line under those fields says "Also
  changes N other containers" (shown only then; open decision 3). Two optional
  fields follow Container size: **Store link** and **Keep at least**. When
  purchases exist, one read-only secondary line shows "Last $3.48 · Walmart ·
  Oct 20 · typical $3.30". The link has an open-in-browser icon button in the
  field.
- **Rename into an existing product = merge:** if an edit makes name/brand/size
  match another product exactly, Save merges this product into that one (one
  action, one Undo) and the secondary line says "Merges with N containers of …"
  (open decision 4).
- **Batch edit (unify):** the existing multiselect bulk editor gains a
  **Product** field beside Brand and Location, with the same Apply/Clear pattern.
  Applying a product (autocomplete over products, the selected rows' own
  products listed first) and saving merges every selected product into it. It
  merges whole products, including their deleted/hidden containers and their
  purchases, because "these are the same SKU" is a fact about the product. A
  secondary line states the scope ("Merges 3 products, 12 containers"). Bulk
  Brand now edits the selected products' brand. Bulk Location is unchanged.
- **Keep in stock / low stock:** products whose on-hand count is below their
  minimum appear in a **Running low** group at the top of Stock, above Inbox,
  using the same sticky group header. Each row: name · brand · size, "0 of 2",
  the store-link icon when set, and Add another. A product with no containers
  left still shows there, which is why this group exists. It is hidden while
  searching or filtering and absent when empty. On-hand counting is open
  decision 5; outside-app alerts are open decision 6.
- **Help:** the Food editor's on-demand ? help gains a short Products paragraph
  (what renaming and merging affect). No permanent explanatory text.

### Deliberately not added

No Products screen or product list; no product rows except Running low; no
"split" or "move container to another product" command (rare; Add another into
the right product plus Remove, the existing pattern for rare changes; wrong merges
use Undo); no Unmerge command after Undo is gone (open decision 4); no purchase
list or price-entry UI (receipts come through import); no store links on ordinary
rows; no product deletion (an unused product without a minimum simply isn't
shown); no category.

### Shared with Tasks

Autocomplete (`free_text_autocomplete`), the sticky group header used for Inbox
and task groups, the bulk Apply/Clear controls and compact selection actions,
field help and validation (ADR0026), and the responsive editor pane (ADR0025).
Nothing Food-specific is forked from a shared component.

## 6. Performance and energy

- **No idle or background cost.** Nothing is scheduled; there are no timers,
  notifications or background jobs. Running low and derived prices are computed
  during the admission that already runs on startup, poll and save.
- **Per-action cost independent of history.** Product state, merge resolution
  (union-find with path compression), per-product on-hand counts, the Running low
  set, and a bounded per-product ring of the newest 5 purchases are maintained in
  the incremental `appendReadyFoodRecords` path. A save touches only the affected
  products and containers. Implicit IDs are hashed once per container when it is
  admitted or its description changes, never per frame or search.
- **Merge is O(1) to write** (one alias, regardless of container count). Applying
  it in the projection re-keys the source product's containers once.
- **Startup:** no extra full pass; the existing full-admission fallback gains the
  same incremental structures, not a second scan of history.
- **Gate coverage:** merge, product edit, Add with product reuse/creation,
  Running low updates and purchase import get budgets, correctness assertions and
  history-growth cases under the [performance coverage contract](performance-gate.md#maintaining-action-coverage)
  before acceptance, including a large-history case with many products,
  purchases and merges.

## Open decisions

1. **Migration by implicit products.** Recommend: yes. Nothing is written at
   upgrade; products materialize on first product edit.
2. **Name/Brand/Container size become product-level.** Editing them in any row
   changes every container of that SKU. Recommend: yes; it is what unification
   means.
3. **Scope line in the editor** ("Also changes N other containers") shown only
   when other containers exist. Recommend: yes; it is contextual, not permanent.
4. **Rename into an existing product merges them; no separate Unmerge command.**
   Recommend: yes; Undo covers mistakes within the session, Add another + Remove
   covers later fixes. Revisit if wrong merges show up after restarts.
5. **What counts as on hand** for minimums. Recommend: every non-deleted
   container of the product (Stock, Inbox and Retained, expired or not). It's
   predictable, and deleting eaten food is already the habit.
6. **Low-stock alert surface.** Recommend: in-app Running low group only (no push
   notifications, no background work). If Lee wants it outside the app, Vex can
   read the synced folder and add low items to a shopping list or daily note;
   that is Vex-side and costs the app nothing.
7. **Auto-link new containers to a recent Purchase** of the same product with
   unlinked units (14-day window). Recommend: yes, silent; otherwise most
   containers never get a cost. Alternative: linking only through import tooling.
8. **Rollout and protocol naming.** Recommend: additive required families under
   the unchanged protocol-5 manifest, called "protocol 5, Food products" in notes;
   reader-first release, then a writer release once all five installations have
   updated, tested first in an isolated Leela workspace. Alternative: one
   release with all devices updated together (faster, and any lagging device
   stops until updated).
9. **Category field.** Recommend: omit until a feature uses it (filters already
   cover Brand/Location).
10. **Typical price** = median unit cost of the newest 5 purchases in 12 months,
    shown from 2 purchases. Recommend: yes. Store links: one visible field, up to
    4 in the protocol for later.

## Verification and evidence

This proposal is grounded in the code at `main` `ca76e2d`: `lib/food/inventory.dart`
(container details, grouping key, per-field edits, additive Undo),
`lib/food/food_record.dart` (current-operation families `container.<action>`
revision 1; unknown families fail with the update message),
`lib/food/food_admission.dart` (incremental admission index),
`lib/food/food_store.dart` (one action per Save, batches of 100 targets) and
`lib/domain/current_operation.dart` (required revisions). The sizes of real
product/purchase counts, the number of distinct implicit products in Lee's data,
and actual timings were not measured: this pass used no copy of real data and ran
no benchmarks.
