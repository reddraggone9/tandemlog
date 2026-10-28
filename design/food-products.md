# Food as products

Status: **Settled design; implementation in progress on `vex/food-products`.**
Lee settled every open decision on 2026-10-27 (section 8). Nothing here is
released. This page records the goals and the decisions, which change only with
Lee, separately from the method, which can change when a better one turns up.
Once released, the behavior moves into [product-behavior.md](product-behavior.md),
[schema.md](schema.md) and [storage-and-sync.md](storage-and-sync.md), and this
page becomes rationale.

## 1. Goals (Lee, 2026-10-27)

- Unify containers that are the same SKU.
- Link what was paid (receipt prices) to the inventory, so that cost per meal is
  possible once consumption logging exists.
- Link an item to its store page (for example Walmart).
- Keep staples in stock (milk, frozen ground turkey, protein bars), with a
  low-stock alert.
- Keep the existing Food UX ("less is more"). Change only what these goals need.

## 2. Requirements and decisions (change only with Lee)

Product model:
- A **Product** describes a SKU. Containers belong to a product.
- **Prices belong to Purchases, not Products.** A Purchase is one receipt line:
  date, store, price paid and quantity. It links to its Product and to the
  containers it produced. One container is the unit the store sells (a 15-bar
  box is one container); container cost = line price / receipt quantity.
- Keep-in-stock minimums are **per Product**, with no groups.
- "Container size" moves to the Product **unchanged** (freeform text). It gets
  restructured only together with consumption logging.
- Products show only derived money figures (last and typical price).
- Meal cost and partial containers wait for consumption logging. Cost per meal
  will use the consumed container's own Purchase, and estimate from recent
  Purchases only when none is linked.
- Receipts arrive through Vex's YNAB itemization workflow. Tandemlog doesn't parse
  receipts.

Settled decisions (numbers match the proposal Lee answered):
1. **Existing containers migrate by derivation.** Nothing is written at upgrade.
2. **Name, Brand and Container size are product-level.** Editing them in any row
   changes every container of that SKU.
3. **Scope line:** the editor shows "Also changes N other containers" only when
   such containers exist.
4. **Renaming into an existing product merges the two.** There is no separate
   Unmerge command; Undo covers mistakes.
5. **On hand** = every non-deleted container of the product (Stock, Inbox and
   Retained, expired or not).
6. **The low-stock alert is in the app only:** a Running low group. No
   notifications and no background work. Vex can read the synced folder if Lee
   later wants alerts outside the app.
7. **Receipt imports create containers.** An import creates each purchased
   container in the Food Inbox (no expiration yet; Lee dates it there). It does
   **not** duplicate a container already entered by hand: recent hand entries of
   the same product are linked to the purchase instead. A container entered by
   hand never links itself to a purchase silently. Hand entry stays the route for
   purchases Vex never sees.
8. **One release.** Products ship in one release that both reads and writes them.
   Older installations fail closed ("Update the app; history was preserved")
   until they are updated. Backward compatibility is required; forward
   compatibility isn't.
9. **No category field** until a feature uses it.
10. **Typical price** = median unit cost of the newest 5 purchases in the last 12
    months, shown once there are at least 2. The editor offers one store link;
    the protocol allows up to 4 for later.

Also in scope (Lee, 2026-10-27; see [batch selection](batch-selection.md)):
- (j) Food rows get arrow-key row navigation, and Shift+Arrow range selection,
  like Tasks.
- (k) On wide windows a Food selection opens the bulk editor in the side pane,
  like Tasks. Narrow widths keep the dialog.

## 3. Method: data model

| Record | Identity | Fields | Merging |
|---|---|---|---|
| Product | UUID: random, or derived (implicit) | name, brand, size, links, minimum | per-field last writer wins; merge alias |
| Purchase | UUID: derived from the receipt line for imports | product, date, store, amount, currency, quantity, source, voided | per-field last writer wins |
| Container (existing) | existing UUID | expiry, retention, location, legacy contents; **new:** product, purchase links | existing rules; links per-field last writer wins |

Product → Product only through a merge alias. Container → Product: exactly one,
explicit or implicit. Container → Purchase: optional. Purchase → Product: one.

**Implicit products.** A container with no explicit product link belongs to the
product whose ID is
`UUIDv5(N, "tandemlog:food-product:implicit:v1\n" + canonical JSON [name, brand, size])`
with the fixed namespace N = `5b0e8a52-3c4d-4f71-9a2e-6d1c7b9f0e34`
(`foodProductNamespace`; the projection doesn't need the space to derive it)
of its own current descriptive fields. Containers with identical
name/brand/size therefore share one product, exactly as they share rows today,
and the migration writes nothing. An implicit product's base fields are the
description it was derived from; product edits override them field by field.

**Which fields belong where.** name, brand and size are read from the product.
The container's own descriptive values stay in history unchanged; they're used
to derive the implicit product and as a fallback, not displayed while a product
supplies them. expiry, retention and location stay per container. The legacy
contents and `estimated` values keep their meaning.

**Adding.** When the typed name/brand/size match an existing product (trimmed,
case-insensitive), the new containers join it. Otherwise they form a new
product. A plain Add whose description already derives the matched product (or a
new one) writes the existing `container.add` revision 1, so ordinary Adds stay
readable by older installs. Only an Add that must point elsewhere (an existing
renamed or explicit product, or a new product whose derived ID is already taken
by a renamed one) writes revision 2 with an explicit product link.

## 4. Method: sync-log protocol

All new records are ordinary Food operations in the existing unified action:
same envelope (`tandemlog.operation` format 1), hash domains, per-writer chain,
observed frontier, size limits and admission. One user action is still one
physical record, and one Undo. No manifest change, no epoch, no conversion.

New and revised families (module `food`):
- `product.edit` r1: `targets` = [product], `fields` ⊆ name/brand/size/links/
  minimum, `product` values. The first edit of an implicit product also carries
  its current name/brand/size, so it no longer depends on any container's
  description. A new explicit product is created by an edit carrying all fields.
- `product.merge` r1: `targets` = [source], `into` = target product. An alias;
  it names no containers or purchases.
- `purchase.record` r1: `targets` = [purchase], `purchase` = product, date (civil
  YYYY-MM-DD), store, amount (integer minor units), currency (ISO 4217; the UI
  shows USD), quantity (1–1000), optional source `{kind, key}`.
- `purchase.edit` r1: per-field changes, including `voided` for a wrong line.
- `container.add` r2: r1 plus an explicit `link` (product, optional purchase).
- `container.link` r1: `targets` = containers, `fields` ⊆ product/purchase, `link`
  values (`null` clears a purchase).
- `container.undo` r1 (unchanged) retracts the new families too. Undo of a
  product or purchase operation carries no container creation basis.

Bounds, validated before append: name 500 characters, other text 200; at most 4
links, each `http`/`https`, at most 2,048 bytes; minimum 0–999 or none; amount
0–10^9; at most 100,000 products and 200,000 purchases per space.

**Older installations fail closed.** Every new family, and `container.add` r2,
reaches a pre-products app as an unknown family or required revision. Its
decoder raises "Update the app; history was preserved", and the unified
admission stops Tasks and Food at the last good state without writing. This
is the existing path (ADR0035 used it for completion revision 3). Reproduced
2026-10-28: the published `865f945` refused to open a workspace written by this
branch ("record 3 … Unknown Food operation. Update the app; history was
preserved."), wrote nothing, and still opened and wrote to the same workspace
before its first product record (only revision-1 Adds).

**Conflicts.** Canonical order (clock, writer, sequence) decides.
- Product, purchase and link fields: per-field last writer wins, the rule Food
  already uses for whole-field values.
- Merge: a merge sends its source's current root into its target's current root.
  It is ignored when both already resolve to the same root (A→B racing B→A
  resolves the same way on every peer). Chains resolve transitively.
  Containers and purchases added to a merged-away product on another device land
  in the target when they sync. Edits to a merged-away product are kept but not
  shown; they come back if the merge is undone.
- Merge with field choice: if the user keeps the source's fields, the same action
  also carries a `product.edit` on the target. One action, one Undo.
- Import retries: imported purchase IDs are
  `UUIDv5(N, "tandemlog:food-purchase:v1\n" + source.kind + "\n" + source.key)`;
  a retried import finds its purchases already present and writes nothing new.

## 5. Method: prices and receipt import

Money lives only on Purchases. A product shows, from its non-voided purchases
(merged products included):
- **Last:** unit cost of the newest purchase, with its date and store.
- **Typical:** decision 10.

Unit cost = amount / quantity. A container's cost is its own Purchase's unit cost.

**Purchase import** (Vex's YNAB workflow → app API), shaped like the
[Food import contract](food-import-contract.md): a reviewed immutable plan is
dry-run, then committed as one action with
`provenance.kind = "food.purchase-import"`.
- Plan v1: `v`, `space`, `importId`, `sourceSha256`, `lines[]`. Each line: `source`
  `{kind, key}`, `date`, `store`, `amount`, `currency`, `quantity`, and a product:
  an existing product ID (explicit or implicit), or name/brand/size/link for a
  product matched or created by description.
- For each line the import links up to `quantity` **recent hand entries** of the
  same product (after merges): containers with no purchase link, not created by
  an import, created from the day before the purchase date through 14 days
  after it, oldest first, deleted ones included (an eaten hand entry is still
  that receipt's container). It creates the remaining units as new containers
  in the Inbox, linked to the product and the purchase.
- The dry run reports per line: product, purchase present or new, containers
  matched and containers to create. A purchase already present with the same
  values is skipped; different values for the same source fail the dry run.

## 6. Method: Food UX

The product stays mostly invisible. Rows, views and the everyday Add flow look
the same.

Unchanged: flat whole-container rows and their metadata; Stock/Retained/Deleted,
Inbox, filters (Brand values now come from products) and their OR/AND rules;
Search (bypasses filters, includes Deleted at the bottom); required expiration on
manual Add; retention on Edit only; Add another; Remove one/Restore one; group
menus; the 50-action Undo stack.

Changes:
- **Grouping:** a row groups containers of one product with the same expiry,
  retention and location. For implicit products that's today's key, so no row
  changes at upgrade.
- **Add:** Food name suggests existing products ("Name · Brand · Size"); picking
  one fills Brand and Container size. Matching rules in section 3.
- **Edit (one row):** Name, Brand and Container size edit the product. When the
  product has containers outside this row: "Also changes N other containers".
  Two optional fields follow Container size: **Store link** (with an open-link
  button) and **Keep at least**. With purchases, one read-only line shows "Last
  $3.48 · Walmart · Oct 20 · typical $3.30".
- **Rename into an existing product = merge:** when the edited name/brand/size
  exactly match another product, Save merges this product into it. The scope line
  says "Merges with N containers of …".
- **Bulk editor (unify):** Food name, Brand and Container size edit the selected
  containers' products, with the same Apply pattern as today. Products whose
  resulting name/brand/size coincide, with each other or with another product,
  merge, by the same rule as a single rename. That is the unification tool: select
  the rows, apply one name. It merges whole products, including their containers
  outside the selection, because "same SKU" is a fact about the product; the scope
  line states it ("Merges 3 products, 12 containers"). Location and Retention
  reason stay per container.
- **Running low:** products below their minimum appear in a Running low group at
  the top of Stock, above Inbox: name · brand · size, "0 of 2", the store-link
  button when set, and Add another. A product with no containers left still
  shows there. Hidden while searching or filtering; absent when empty.
- **Keyboard (j):** Up/Down move focus between Food rows; Shift+Up/Down extend
  the selection from the anchor, using the shared selection rules.
- **Wide selection (k):** at pane widths a selection opens the bulk editor in the
  side pane, as on Tasks; narrowing back to one whole row returns to the single
  editor. Narrow widths keep Edit → dialog.
- **Help:** the Food editor's on-demand help gains a short Products paragraph.

Deliberately not added: a Products screen or list; product rows outside Running
low; a split or "move container" command; Unmerge; a purchase list or price
entry; store links on ordinary rows; product deletion; a category.

Shared with Tasks: autocomplete, the sticky group header, bulk Apply controls,
selection rules (`list_selection.dart`), field help and validation, and the
responsive editor pane.

## 7. Method: performance and energy

- No idle or background cost: no timers, notifications or jobs. Running low and
  derived prices are computed in the admission that already runs on startup,
  poll and save.
- Incremental admission keeps per-product and per-purchase operation histories
  (the existing per-target index), so a save re-folds only the products and
  purchases it touches. Merges re-resolve the (small) alias set. Per-product
  views (row overlay, on-hand counts, Running low) are one pass over the
  projected containers, like the existing per-save container sort.
- A merge writes one alias regardless of container count.
- New actions (product edit, merge, purchase import) get budgets and
  correctness assertions under the
  [performance coverage contract](performance-gate.md#maintaining-action-coverage)
  before release; the enforcing qualification runs once at RC time.

## 8. Decision record

The proposal (`vex/food-products-design-20261027`, 65b957e) listed ten
decisions. Lee, 2026-10-27: 1–6, 9 and 10 as recommended. #7 changed (19:45):
imports create Inbox containers and match recent hand entries, instead of new
hand entries silently linking to recent purchases. #8 changed (19:52): one
release, older installs fail closed. (j) and (k) were added the same evening.

Method changes from the proposal, made while implementing (no goal changes):
- No `product.create`. A product is created by its first `product.edit`; this
  removes the "conflicting create" corruption case.
- No `container.undo` r2. The existing Undo already retracts any operation by
  reference, and an older app has already stopped at the retracted record.
- `container.add` r2 keeps name/brand/size on the container as written, as a
  fallback when a product is unknown. Plain Adds keep writing r1.
- No silent purchase auto-link on Add (decision 7).
