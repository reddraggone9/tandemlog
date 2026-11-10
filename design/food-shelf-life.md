# Food shelf life ("Keeps for")

Status: **design proposal for Lee's OK; nothing implemented.** Branch
`vex/food-keeps-for-design`. Mock-ups: `design/mockups/food-shelf-life/`
(list at the end).

## Goal (Lee, 2026-11-09)

Imported and hand-entered food arrives already dated from a per-product shelf
life, so Lee stops dating Inbox items by hand. Pot weights are not part of this.

Agreed shape (Lee 11-09 20:45 and 21:12, "that sounds like the right ballpark"):

- A product can have an optional **Keeps for** duration.
- Receipt imports arrive dated purchase day + Keeps for, marked **estimated**.
  Today they land undated in the Inbox.
- Keeps for is **learned** when Lee dates an Inbox item, and **offered for
  update** when he changes an estimate. It is seeded from his "How long food
  keeps" table in the vault note `Kitchen Reference.md`.
- v1 counts from the purchase day only.
- Cut, opened, cooked or frozen food is its own product with its own Keeps for,
  counted from the day it is entered by hand. Lee adds the new entry and removes
  the old one with the existing commands. So hand entry autofills the date too.

Everything below "Method" can change if a better way turns up; the goal and the
agreed shape change only with Lee.

## The one decision for Lee: usual location in v1?

**Recommendation: in.** A product remembers where its food usually goes, and
new containers of it get that location filled in: receipt imports and hand Add
alike. Oranges move to the fridge once, and every later orange import lands in
Fridge.

- **How:** no new field and no new screen. The usual location is the location of
  the product's most recently placed container (added, edited or moved with a
  non-empty Location; removed containers count, since eaten food still says
  where it lived). Changing where a product goes is just putting the next one
  somewhere else.
- **Cost:** about half a day to a day on top of Keeps for, because it rides the
  same import edit and the same Add autofill. No extra format change.
- **If out:** imports keep arriving with a blank Location, as today, and Lee
  sets it with the bulk editor or Move some. Nothing else changes, and it can be
  added later without a format change.
- **Rejected alternative:** a stored "Usual location" product field. It would
  sit next to the existing Location field (two controls for one job,
  ux-principles 13), needs its own format revision, and costs about a day more.

## UX brief

The product stays mostly invisible, as in [Food as products](food-products.md).
Nothing new appears for products without Keeps for.

### 1. Food list after a receipt import (Inbox and Stock)

- **Question it answers:** "What came home, and does anything still need me?"
- **Shown, in order:** Inbox first, holding only food that still has no date
  (its product has no Keeps for). Then Stock in its usual date order, where
  imported food with an estimated date sits like any other row. Its date reads
  `2026-11-30 est.`; the rest of the row is unchanged.
- **Left out:** no banner, no count of estimated items, no "review imports"
  step, no separate estimated section. Estimated rows group apart from
  hand-dated rows of the same product and date, so `est.` is always true for
  the whole row.
- **Next action:** date the few Inbox items (each one teaches its product), or
  nothing at all. Tapping an `est.` row opens the normal editor if a date looks
  wrong.

### 2. Row editor (one row)

- **Question:** "When does this go bad, and how long does this kind usually
  keep?"
- **Shown, in order:** today's fields, with **Keeps for** directly under
  Expiration (they answer one question together). For an estimated row,
  Expiration's helper line says where the date came from: `Estimated: bought
  2026-11-07 + 3 weeks`. Keeps for shows `3 weeks`; it is a product field like
  Store link and Keep at least, so the existing "Also changes N other
  containers" scope rule does not apply to it (it changes no container).
- **Left out:** no explanation paragraph, no "confirm estimate" button (the date
  stays estimated until Lee changes it, which is harmless), no unit picker
  (one text field takes `5 days`, `2 weeks`, `3 months`).
- **Next action:** fix the date, Save.

### 3. Learning and the update offer (inside the row editor)

- **Question:** "Should this product remember what I just did?"
- **Learn:** Lee dates an Inbox item whose product has no Keeps for, and the
  container came from a receipt (so the purchase day is known). Keeps for fills
  itself in as he picks the date (`12 days`, helper `Learned from purchase
  on 2026-11-07`).
  It is an ordinary field: he can clear or change it before Save. Save writes
  the date and the product's Keeps for in one action, one Undo.
- **Offer to update:** Lee changes an estimated date, or the autofilled date in
  Add, and the new date implies a different duration than the product's Keeps
  for. Under Keeps for, one text button appears: `Use 5 days instead`. Not
  pressing it changes nothing.
- **How it avoids nagging:** no dialog, no second step, nothing after Save; the
  offer is off by default and disappears when the dates agree again; it never
  appears in the bulk editor, for Retained or deleted rows, or when the purchase
  day is unknown.

### 4. Add food and Add another (hand entry)

- **Question:** "What did I just put away?"
- **Shown:** as today. When the name matches a product with Keeps for (picked
  from suggestions, or typed exactly), Expiration fills in as today + Keeps for
  with helper `Keeps 2 weeks from today`. With usual location in, a blank
  Location fills in too. Add another (row menu) prefills both instead of
  leaving Expiration blank. A date Lee typed himself is never overwritten.
- **Left out:** no `est.` on hand entries (Lee saw and accepted the date), and
  no learning from brand new products in v1 (see "Out of v1").
- **Next action:** Add.

## Method: data model

| Where | What | Format |
|---|---|---|
| Product | `keepsFor`: `{"count": n, "unit": "day" \| "week" \| "month"}` or null | new field in `product.edit` **revision 2** |
| Container | `estimated: true` on dated imports | existing container field, written by `container.edit` r1 |
| Usual location (if in) | derived from the product's containers | nothing stored |

- **Keeps for** keeps Lee's own unit, so "1 month" displays as "1 month" and
  adds a calendar month (Jan 31 + 1 month = Feb 28/29). Bounds: count 1 to 999;
  months at most 120. Per-field last writer wins, like the other product fields.
  Setting it on an implicit product is that product's first `product.edit`, which
  also carries name/brand/size (the existing rule).
- **Estimated** reuses the container's retained `estimated` flag (today
  deprecated in the UI and always false on new records). Display grouping adds
  it back to the row key, so estimated and hand-dated containers form separate
  rows. Any saved Expiration change writes `estimated: false`.
- **Sync and compatibility:** one release that both reads and writes, per the
  format rule (Lee 10-27, 11-02). `product.edit` r2 is the only new revision.
  Older installs meeting it stop with "Update the app; history was preserved",
  the existing fail-closed path, and write nothing. Estimated containers alone
  are readable by older installs (they show the date and ignore the flag), but
  in practice the first Keeps for value stops them anyway. No migration: every
  existing product simply has no Keeps for.
- **Merging products:** if the target has no Keeps for and the source has one,
  the merge action carries it over (a `product.edit` in the same action, one
  Undo, as for kept name fields today).

## Method: receipt import

- The import plan format does not change. The app computes dates at commit from
  the current products, so Vex's YNAB workflow needs no change.
- Each line: hand entries matched to the purchase keep their own dates. New
  containers are born exactly as today (undated Inbox defaults), and **the same
  import action** also carries one `container.edit` per new container setting
  `expiry` = purchase date + Keeps for, `estimated: true`, and (if in) the usual
  location. Keeping the births unchanged keeps the concurrent-receipt claim check
  ("unmodified Inbox creation defaults") valid as it is.
  - *To verify first in the build:* that one record may carry a birth and an
    edit of the same new container. Fallback: `container.add` r3 carrying the
    three values, with the claim check comparing everything except them.
- Products without Keeps for: unchanged, undated in the Inbox.
- The dry run reports, per line, the estimated date (or "no date") and the
  location it will use.
- Two devices importing the same receipt offline with different Keeps for:
  both edits apply, last writer wins, as for any concurrent edit.
- Undo of the import retracts the dates with the containers (one action).

## Method: hand entry

- Add and Add another fill Expiration = device's local today + Keeps for when
  the field is empty or still holds a previous autofill. Picking another product
  replaces an autofill, never a typed date.
- Saved hand entries are not estimated.
- Transformed food: "Carrots, cut" is an ordinary product. Lee adds it (date
  fills from today + 2 weeks) and removes the whole-carrots container with
  Remove one. Nothing links the two.

## Method: learning and updates (exact rules)

Purchase day = the date of the container's linked purchase. Containers without
a purchase link (hand entries, older imports) have no purchase day, so they
never learn and never get an update offer from the row editor.

- **Learn** when all hold: single-row editor; the row is in the Inbox (no date,
  not retained, not deleted); the product has no Keeps for; purchase day known;
  the picked date is after the purchase day. Keeps for fills with the day
  difference, shown as weeks when it divides by 7, otherwise days.
- **Offer update** when all hold: single-row editor on an estimated row, or Add
  with an autofilled date; the product has Keeps for; Lee changed the date; the
  new date is after the start day; it implies a different duration. Button text
  `Use N days instead` (weeks when divisible by 7).
- Months are never inferred; a learned value is always days or weeks.
- Changing Keeps for never re-dates existing containers, estimated or not. It
  applies to the next import or Add.

## Seed data

Source: `Kitchen Reference.md`, "How long food keeps" (36 entries). Lee's real
product list stays private, so Vex matches it on a private copy and sends Lee
the proposed list before applying. Applying is one action (one Undo) through the
agent CLI: a `product.edit` per matched product, plus new empty products for
transformed foods that don't exist yet, so Add suggests them.

Straight matches (purchase-day entries; apply to every product whose name
matches, any brand or size): Grapes 2 weeks, Cucumbers (whole) 1 week, Carrots
(whole) 1 month, Cilantro 2 weeks, Parsley 2 weeks, Basil 2 weeks, Peppers 1
week, Tomatoes 2 weeks, Strawberries 1 week, Bell peppers 2 weeks, Cabbage
(whole) 1 month, Green onions 2 weeks, Broccoli 5 days, Cauliflower 2 weeks,
Blueberries 2 weeks, Blackberries 5 days, Romaine lettuce (whole) 2 weeks,
Bananas (fresh whole) 5 days, Onions 3 months, Celery 2 weeks, Peaches (fridge)
5 days, Potatoes 3 months, Garlic (whole, fridge) 2 months.

Entries that need a call (Vex's proposal in brackets; Lee confirms with the
list):

- **Counted from cutting, opening, cooking or freezing**, so they become their
  own products: Carrots, cut 2 weeks; Cabbage, cut 5 days; Ginger, frozen whole
  6 months; Banana, frozen whole 3 months; Cooked sausage 4 days; Cooked Bacon 1
  week; Refrigerated tofu, opened 2 weeks. [Create each as a product named as in
  the table. The unopened tofu product gets no Keeps for.]
- **Cupboard vs fridge:** Oranges 1 week cupboard / 3 weeks fridge; Limes 1
  week / 3 weeks; Apples only listed for the cupboard (2 weeks). [Oranges and
  limes 3 weeks, since they go in the fridge now; Apples 2 weeks until Lee has a
  fridge number.] v1 has one Keeps for per product, not per location.
- **Possibly bought ready-made:** Coleslaw 5 days, Cooked sausage 4 days.
  [Coleslaw counts from purchase if bought as a bag or tub; if he makes it, it's
  a hand-entered product counted from that day, which is the same rule.]
- **Generic names covering several products** (for example cherry and Roma
  tomatoes, red and green grapes, "Peppers" vs "Bell peppers"): [apply to all
  name matches; "Peppers" only where the name isn't "Bell peppers"]; the list
  Lee sees names each product.

## Edge cases

- **No Keeps for:** behavior identical to today.
- **No purchase date:** hand entries and older imports have none, so no learning
  or update offer from them (above). Imports always have one.
- **Keeps for changed while containers exist:** existing containers keep their
  dates; only new imports and Adds use the new value.
- **Late import of an old receipt:** the estimate may already be past and shows
  as expired, which is the honest result.
- **Bulk editor and Move some:** unchanged; they don't touch dates or
  `estimated`.
- **Product merged while an import is in flight on another device:** the import's
  edits target containers, not the product, so they land normally.
- **Daylight saving and time zones:** all arithmetic is on civil dates (the
  purchase date as recorded; local today for hand entry).
- **Agent CLI and MCP:** read and set Keeps for, and show `estimated` in food
  listings and import dry runs. That interface is Vex's; no UI.

## Out of v1

- Counting from opening/cutting on the same container (transformed food is its
  own product instead).
- Different Keeps for per location (cupboard vs fridge).
- Learning from a brand new product's first hand-entered date.
- Re-dating existing estimated containers after Keeps for changes.
- A "confirm estimate" action, notifications or reminders about expiring food.
- Pot weights and food logging.

## Test plan

- Format: `product.edit` r2 round-trip, validation bounds, unit parsing and
  display; an r1-only build stops with "Update the app" and writes nothing
  (frozen reader fixture, as with RC109).
- Date arithmetic: days, weeks, month-end clamping, leap years.
- Import: dated estimated containers from purchase date; undated when no Keeps
  for; matched hand entries untouched; concurrent duplicate receipt claims still
  admitted; retry no-op; Undo removes containers and dates; dry run report.
- Grouping: estimated and hand-dated rows stay separate; editing the date clears
  `est.` and moves the container into the plain row.
- Editor: learn fills Keeps for only under the exact conditions; update offer
  appears and disappears with the date; one Save = one Undo for date + product.
- Add and Add another autofill; typed dates never overwritten; location
  autofill if in.
- UI at phone width, 2x text and wide pane; dark theme captures; independent UX
  review against this brief and `ux-principles.md`.
- Performance: import and product-edit actions keep their budgets under the
  performance gate's coverage contract.
- Native acceptance on Linux and Android, and an RC side by side on Lee's phone.

## Rough build size

About 6 to 7 working days for Keeps for: product field and format (1), import
estimating and claim compatibility (1.5), `est.` display and grouping (0.5),
learning and update offer (1), Add autofill (0.5), agent CLI and seed (1), tests,
performance coverage, captures and native acceptance (1.5). Usual location adds
half a day to a day.

## Mock-ups

Widget-test captures (labelled as such per ux-principles 25): the real Food page
and editor with the production dark theme, phone width 412 dp, rendered by
`flutter test` with a throwaway prototype of the new parts. Prototype branch
`vex/food-keeps-for-mockup-proto` (never merged; `test/shelf_life_mockup_capture_test.dart`).
Synthetic data: a Walmart receipt from 2026-11-07, viewed on 2026-11-09.

1. `01-food-list-after-import.png`: Inbox holds only the two products without
   Keeps for; imported rows sit in Stock with `est.`.
2. `02-product-editor-keeps-for.png`, `-2x-text.png`, `-2x-text-scrolled.png`:
   row editor on an estimated row; 2x text keeps the title on one line and
   Cancel/Save side by side.
3. `03-inbox-dating-learns-keeps-for.png` (and 2x): dating Mango fills Keeps for
   with 12 days.
4. `04-changed-estimate-offers-update.png` (and 2x): moving the strawberries'
   estimate two days earlier offers `Use 5 days instead`.
5. `05-add-autofills-date-and-location.png` (and 2x): picking "Carrots, cut" in
   Add fills Expiration (today + 2 weeks) and Location (Fridge).

Self-review against this brief and `ux-principles.md`: fixed a centered helper
line under Expiration and awkward helper wording. Known and unchanged by this
feature: the dialog's tight side padding at 2x and Food name autofocus in the
row editor (both existing app behavior; the padding is already on the open UX
list). "Keeps for" and "Keep at least" sit four fields apart and read
differently in context; if Lee finds them confusable, the fallback label is
"Shelf life".
