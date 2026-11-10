# Food shelf life ("Keeps for")

Status: **design proposal for Lee's OK; nothing implemented.** Branch
`vex/food-keeps-for-design`. Mock-ups: `design/mockups/food-shelf-life/`
(list at the end).

## What Keeps for applies to

Keeps for is for fresh food with no printed date. A product has a Keeps for
only when:

1. it is one of the fresh foods seeded from Lee's `Kitchen Reference.md` table
   (he confirms that list before it is applied), or
2. he pressed **Remember** in the editor after dating it (one press, one
   product), or
3. he typed a Keeps for into the product's editor.

Nothing else ever sets it. Every other product, including all food with a
printed date, keeps arriving undated in the Inbox exactly as today, so Lee
reads the label. Dating an Inbox item never sets Keeps for by itself.

## Goal

Lee, 2026-11-09: imported and hand-entered fresh food arrives already dated
from a per-product shelf life, so he stops dating those Inbox items by hand.
Pot weights are not part of this.

Lee, 2026-11-10: "I primarily want it for fresh foods that aren't labeled with
an expiration date. In particular, I don't want labeled foods to skip the inbox
since they sometimes come in already expired, having sat on a store shelf for
months before we bought them. That said, I'm not sure having an approximate
date filled in for such foods is necessarily a *bad* idea; it could make entry
simpler." And on the editor: "Location definitely gets more manual edits and is
[...] one of the fields we edit on pretty much every item. [...] we'll pretty
much never edit the store link and rarely click its button from this screen.
In terms of use, I would expect something like: Location, Keep at least, Store
link." "I agree the imports (and manual entry) should fill in the location."

Agreed shape (Lee 11-09 20:45 and 21:12; 11-10 07:31):

- A product can have an optional **Keeps for** duration, limited as above.
- Receipt imports of a product with Keeps for arrive dated purchase day + Keeps
  for, marked **estimated**. Everything else arrives undated in the Inbox, as
  today.
- Keeps for is seeded from the "How long food keeps" table in the vault note
  `Kitchen Reference.md`, set by hand, or **remembered** when Lee presses the
  editor's Remember offer after dating an Inbox item. It is **offered for
  update** when he changes an estimate.
- v1 counts from the purchase day only.
- Cut, opened, cooked or frozen food is its own product with its own Keeps for,
  counted from the day it is entered by hand. Lee adds the new entry and removes
  the old one with the existing commands. So hand entry autofills the date too.
- **Usual location is in v1** (agreed by Lee 11-10): imports and hand entry fill
  in where the product's food usually goes.
- Labeled food stays in the Inbox, but dating it gets easier: the editor
  suggests a date from the product's earlier gap, never filled in until Lee
  picks it.
- In the editor, Location sits directly under Expiration and Store link is
  last.

Everything below "Method" can change if a better way turns up; the goal and the
agreed shape change only with Lee.

## UX brief

The product stays mostly invisible, as in [Food as products](food-products.md).
Nothing new appears for products without Keeps for, apart from the date
suggestion on Inbox items that have one.

### 1. Food list after a receipt import (Inbox and Stock)

- **Question it answers:** "What came home, and does anything still need me?"
- **Shown, in order:** Inbox first, holding every new item whose product has no
  Keeps for: labeled food (yogurt, milk, bagged greens) and fresh food not yet
  remembered. Then Stock in its usual date order, where imported food with an
  estimated date sits like any other row. Its date reads `2026-11-30 est.`; the
  rest of the row is unchanged. Imported rows of both kinds show the product's
  usual location when it has one; a product seen for the first time has none.
- **Left out:** no banner, no count of estimated items, no "review imports"
  step, no separate estimated section. Estimated rows group apart from
  hand-dated rows of the same product and date, so `est.` is always true for
  the whole row.
- **Next action:** date the Inbox items from their labels (or by eye for fresh
  food). Tapping an `est.` row opens the normal editor if a date looks wrong.

### 2. Row editor (one row)

- **Question:** "When does this go bad, and where is it?"
- **Shown, in order:** Food name, Brand, Expiration, Location, Keeps for,
  Container size, Keep at least, Store link, Retention reason. Location is
  directly under Expiration because it is edited on nearly every item; Store
  link is last because it is almost never edited. Keeps for and Keep at least
  have Container size between them, since the names are easy to mix up. The
  last-price line (`Last $2.98 · Walmart · Nov 7`) stays at the end of the
  product fields, now under Store link, next to the store it names.
- For an estimated row, Expiration's helper line says where the date came from:
  `Estimated: bought 2026-11-07 + 3 weeks`. It hides once Expiration changes,
  since Save then makes the date Lee's own. Keeps for shows `3 weeks`; it is a
  product field like Store link and Keep at least, so the existing "Also changes
  N other containers" scope rule does not apply to it (it changes no container).
- **Left out:** no explanation paragraph, no "confirm estimate" button (the date
  stays estimated until Lee changes it, which is harmless), no unit picker
  (one text field takes `5 days`, `2 weeks`, `3 months`).
- **Next action:** fix the date or location, Save.

### 3. Offers under Expiration (row editor)

One kind of offer, in one place: a quiet text button directly under
Expiration, which does nothing unless pressed. At most one shows at a time,
and only while it applies.

- **Remember** (`Remember: keeps 12 days`): Lee has picked a date for an Inbox
  item whose product has no Keeps for, and the purchase day is known. Pressing
  it puts `12 days` into Keeps for; Save writes the date and the product's Keeps
  for in one action, one Undo, and he can clear Keeps for again before Save. Not
  pressing it changes nothing: the date is saved, and the product's next import
  arrives undated in the Inbox again. So a labeled product never gains a Keeps
  for by being dated, however often that happens. Remember is offered only the
  first time a product is dated: once it has a suggested date (below), dating it
  shows no Remember, so labeled food is asked once and never again. Typing
  Keeps for by hand always works.
- **Update** (`Remember: keeps 5 days`): Lee changes an estimated date in the
  row editor, and the new date implies a different duration than the product's
  Keeps for. Pressing it replaces Keeps for (`1 week` → `5 days`). Same wording
  as Remember, since it does the same thing. Add makes no offer: it has no
  product fields, so a changed date there is just that container's date.
- **Suggested date** (`Like last time: 2026-12-04`): an Inbox item whose
  Expiration is still empty, whose product has no Keeps for, and which has an
  earlier container with a purchase day and a date Lee set himself. The date is
  this purchase day + that earlier gap. Pressing it types the date into
  Expiration, where Lee checks it against the label and edits it like any typed
  date. The calendar button opens on the same date instead of today. Nothing is
  filled in or saved until he presses or picks. Once Expiration has any text,
  the suggestion goes away and nothing replaces it.
- **Why no pre-filled date on labeled food:** a store can sell food that sat on
  its shelf for months, so a date from the usual gap would be confidently wrong
  for exactly the items that most need checking, and nothing would prompt Lee to
  read the label. Leaving them undated also keeps the Inbox meaning "no date
  yet". The suggestion keeps the shortcut without that risk: it is only a
  button, and the item stays in the Inbox until he dates it.
- **How the offers avoid nagging:** no dialog, no second step, nothing after
  Save; each disappears when it no longer applies; none appears in the bulk
  editor or Add, for Retained or deleted rows, or when the purchase day is
  unknown.
- **Narrow screens and large text:** an offer label wraps to a second line
  rather than clipping; at 2x text on 412 dp all three fit on one line.

### 4. Add food and Add another (hand entry)

- **Question:** "What did I just put away?"
- **Shown:** today's Add fields in the new order: Food name, Brand, Expiration,
  Location, Container size, Containers to add (Add has no product fields, as
  today). When the name matches a product with Keeps for (picked from
  suggestions, or typed exactly), Expiration fills in as today + Keeps for with
  helper `Keeps 2 weeks from today`. A blank Location fills in with the
  product's usual location. Add another (row menu) prefills both instead of
  leaving Expiration blank. A date or location Lee typed himself is never
  overwritten. If he changes the autofilled date, the helper line goes away and
  nothing else happens.
- **Left out:** no `est.` on hand entries (Lee saw and accepted the date), and
  no Keeps for for brand new products in v1 (see "Out of v1").
- **Next action:** Add.

## Method: data model

| Where | What | Format |
|---|---|---|
| Product | `keepsFor`: `{"count": n, "unit": "day" \| "week" \| "month"}` or null | new field in `product.edit` **revision 2** |
| Container | `estimated: true` on dated imports | existing container field, written by `container.edit` r1 |
| Usual location | derived from the product's containers | nothing stored |
| Suggested date | derived from the product's containers | nothing stored |

- **Keeps for** keeps Lee's own unit, so "1 month" displays as "1 month" and
  adds a calendar month (Jan 31 + 1 month = Feb 28/29). Bounds: count 1 to 999;
  months at most 120. Per-field last writer wins, like the other product fields.
  Setting it on an implicit product is that product's first `product.edit`, which
  also carries name/brand/size (the existing rule).
- **Estimated** reuses the container's retained `estimated` flag (today
  deprecated in the UI and always false on new records). Display grouping adds
  it back to the row key, so estimated and hand-dated containers form separate
  rows. Any saved Expiration change writes `estimated: false`.
- **Usual location:** the location of the product's most recently placed
  container (added, edited or moved with a non-empty Location; removed
  containers count, since eaten food still says where it lived). Changing where
  a product goes is just putting the next one somewhere else. A stored "Usual
  location" product field was rejected: it would sit next to Location (two
  controls for one job, ux-principles 13) and need its own format revision.
- **Suggested date:** from the product's most recent container that has a
  purchase day, a date, and `estimated` false: its date minus its purchase day,
  in days, added to this container's purchase day. Only gaps of 1 day or more
  count.
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

- The import plan format does not change. The app computes dates and locations
  at commit from the current products, so Vex's YNAB workflow needs no change.
- Each line: hand entries matched to the purchase keep their own dates. New
  containers are born exactly as today (undated Inbox defaults), and **the same
  import action** also carries one `container.edit` per new container setting
  the usual location (when the product has one) and, only when the product has
  Keeps for, `expiry` = purchase date + Keeps for with `estimated: true`.
  Keeping the births unchanged keeps the concurrent-receipt claim check
  ("unmodified Inbox creation defaults") valid as it is.
  - *To verify first in the build:* that one record may carry a birth and an
    edit of the same new container. Fallback: `container.add` r3 carrying the
    three values, with the claim check comparing everything except them.
- Products without Keeps for: undated in the Inbox, with the usual location.
- The dry run reports, per line, the estimated date (or "no date") and the
  location it will use.
- Two devices importing the same receipt offline with different Keeps for:
  both edits apply, last writer wins, as for any concurrent edit.
- Undo of the import retracts the dates and locations with the containers (one
  action).

## Method: hand entry

- Add and Add another fill Expiration = device's local today + Keeps for when
  the field is empty or still holds a previous autofill, and Location with the
  usual location when Location is empty or still holds a previous autofill.
  Picking another product replaces an autofill, never typed text.
- Saved hand entries are not estimated.
- Transformed food: "Carrots, cut" is an ordinary product. Lee adds it (date
  fills from today + 2 weeks, location from where cut carrots went last) and
  removes the whole-carrots container with Remove one. Nothing links the two.

## Method: field order

- Row editor: Food name, Brand, Expiration, Location, Keeps for, Container size,
  Keep at least, Store link, Retention reason. Add: Food name, Brand,
  Expiration, Location, Container size, Containers to add. Bulk editor: Food
  name, Brand, Location, Container size, Retention reason (it has no Expiration
  or product fields, as today).
- The form is one column, so Tab order and the first-error focus order follow
  the same list. Helper lines stay with their field: the estimate helper and the
  offers under Expiration, the "Also changes N other containers" scope line
  under Container size, the last-price line under Store link.

## Method: offers (exact rules)

Purchase day = the date of the container's linked purchase. Containers without
a purchase link (hand entries, older imports) have no purchase day, so the row
editor never offers Remember, Update or a suggested date for them.

- **Remember** shows when all hold: single-row editor; the row was in the Inbox
  when opened (no date, not retained, not deleted); the product has no Keeps
  for; purchase day known; the current Expiration is a valid date after the
  purchase day; Keeps for in the form is empty or differs from that duration;
  no suggested date exists for the row (the product has not been dated from a
  purchase before).
  Text `Remember: keeps N days`, as weeks when the day difference divides by 7.
- **Update** shows when all hold: single-row editor on an estimated row; the
  product has Keeps for; Lee changed the date; the new date is after the
  purchase day; it implies a different duration than Keeps for in the form.
  Same text as Remember.
- **Suggested date** shows when all hold: single-row editor; the row was in the
  Inbox when opened; Expiration is empty; the product has no Keeps for; purchase
  day known; a suggested date exists (data model above). Text `Like last time:
  YYYY-MM-DD`. The calendar opens on it while Expiration is empty.
- Pressing an offer changes only the form. Save is the only write; one Save is
  one Undo.
- Months are never inferred; a remembered value is always days or weeks.
- Changing Keeps for never re-dates existing containers, estimated or not. It
  applies to the next import or Add.

## Seed data

Source: `Kitchen Reference.md`, "How long food keeps" (36 entries, all fresh
food without a printed date). Lee's real product list stays private, so Vex
matches it on a private copy and sends Lee the proposed list before applying.
Applying is one action (one Undo) through the agent CLI: a `product.edit` per
matched product, plus new empty products for transformed foods that don't exist
yet, so Add suggests them. Packaged products that merely share a name with a
table entry (for example a dated bag of salad) are left out of the proposal.

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
  the table. The unopened tofu product gets no Keeps for; it has a printed
  date.]
- **Cupboard vs fridge:** Oranges 1 week cupboard / 3 weeks fridge; Limes 1
  week / 3 weeks; Apples only listed for the cupboard (2 weeks). [Oranges and
  limes 3 weeks, since they go in the fridge now; Apples 2 weeks until Lee has a
  fridge number.] v1 has one Keeps for per product, not per location.
- **Possibly bought ready-made:** Coleslaw 5 days, Cooked sausage 4 days.
  [A bagged or tubbed coleslaw has a printed date, so it gets no Keeps for; the
  Coleslaw entry applies only to a hand-entered product for coleslaw he makes,
  counted from that day. Cooked sausage likewise applies only to sausage he
  cooks.]
- **Generic names covering several products** (for example cherry and Roma
  tomatoes, red and green grapes, "Peppers" vs "Bell peppers"): [apply to all
  name matches; "Peppers" only where the name isn't "Bell peppers"]; the list
  Lee sees names each product.

## Edge cases

- **No Keeps for:** behavior identical to today, plus the usual location on
  imports and Add, and the suggested-date offer on Inbox items.
- **Labeled food that arrives already expired:** it is in the Inbox, undated;
  Lee dates it from the label, so it shows as expired. The suggested date may be
  later than the label; it is only a button and he checks it against the label.
- **Labeled food dated repeatedly:** Remember is offered the first time only.
  From the second time on he gets `Like last time` and no Remember; the product
  keeps arriving in the Inbox.
- **Fresh food where he skipped Remember the first time:** later imports offer
  `Like last time` (one press). To stop it coming to the Inbox he types Keeps
  for in the editor.
- **Remembered by mistake:** clear Keeps for in the product's editor; the next
  import arrives undated. Containers already estimated keep their dates.
- **No purchase date:** hand entries and older imports have none, so no offers
  from the row editor (above). Imports always have one.
- **Keeps for changed while containers exist:** existing containers keep their
  dates; only new imports and Adds use the new value.
- **Late import of an old receipt:** the estimate may already be past and shows
  as expired, which is the honest result.
- **Bulk editor and Move some:** they don't touch dates or `estimated`, show no
  offers, and follow the new field order.
- **Product merged while an import is in flight on another device:** the import's
  edits target containers, not the product, so they land normally.
- **Daylight saving and time zones:** all arithmetic is on civil dates (the
  purchase date as recorded; local today for hand entry).
- **Agent CLI and MCP:** read and set Keeps for, and show `estimated` and the
  usual location in food listings and import dry runs. That interface is Vex's;
  no UI.

## Out of v1

- Counting from opening/cutting on the same container (transformed food is its
  own product instead).
- Different Keeps for per location (cupboard vs fridge).
- Keeps for on a brand new product's first hand entry (set it in the editor
  once the product exists).
- Re-dating existing estimated containers after Keeps for changes.
- A "confirm estimate" action, notifications or reminders about expiring food.
- Pot weights and food logging.

## Test plan

- Format: `product.edit` r2 round-trip, validation bounds, unit parsing and
  display; an r1-only build stops with "Update the app" and writes nothing
  (frozen reader fixture, as with RC109).
- Date arithmetic: days, weeks, month-end clamping, leap years.
- Import: dated estimated containers from purchase date only for products with
  Keeps for; undated Inbox items for all others; usual location on both; matched
  hand entries untouched; concurrent duplicate receipt claims still admitted;
  retry no-op; Undo removes containers, dates and locations; dry run report.
- Limits: dating an Inbox item and saving without pressing Remember leaves the
  product's Keeps for empty, and its next import lands in the Inbox; pressing
  Remember then Save sets it (one Undo); clearing it after pressing saves none;
  a product with a suggested date never shows Remember.
- Grouping: estimated and hand-dated rows stay separate; editing the date clears
  `est.` and moves the container into the plain row.
- Offers: Remember, Update and suggested date each appear only under their exact
  rules, never together, and disappear when they stop applying; pressing one
  changes only the form; the calendar opens on the suggested date while
  Expiration is empty and on today otherwise.
- Field order: row editor, Add and bulk editor render in the new order; Tab
  moves through fields in that order; the first invalid field gets focus in
  that order.
- Add and Add another autofill date and location; typed text never overwritten;
  changing the autofilled date hides its helper and offers nothing.
- UI at phone width (412 and 360 dp), 2x text and wide pane, including the
  longest offer label (`Remember: keeps 10 weeks`) wrapping cleanly; dark theme
  captures; independent UX
  review against this brief and `ux-principles.md`.
- Performance: import and product-edit actions keep their budgets under the
  performance gate's coverage contract.
- Native acceptance on Linux and Android, and an RC side by side on Lee's phone.

## Rough build size

About 7 to 8 working days in all: product field and format (1), import
estimating, usual location and claim compatibility (2), `est.` display and
grouping (0.5), the three offers and the calendar start date (1.5), Add autofill
of date and location (0.5), field order (0.25), agent CLI and seed (1), tests,
performance coverage, captures and native acceptance (1.5).

## Mock-ups

Widget-test captures (labelled as such per ux-principles 25): the real Food page
and editor with the production dark theme, phone width 412 dp, rendered by
`flutter test` with a throwaway prototype of the new parts. Prototype branch
`vex/food-keeps-for-mockup-proto` (never merged; `test/shelf_life_mockup_capture_test.dart`).
Synthetic data: a Walmart receipt from 2026-11-07, viewed on 2026-11-09; an
earlier synthetic receipt from 2026-10-24 supplies the yogurt's last gap. No
prices are seeded, so the last-price line (now under Store link) does not
appear.

1. `01-food-list-after-import.png`: Inbox holds the three items without Keeps
   for, including labeled Greek yogurt (with its usual location; Mango and
   spinach are new, so none); imported fresh food sits in Stock with `est.`.
2. `02-product-editor-keeps-for.png`, `-2x-text.png`, `-2x-text-scrolled.png`:
   row editor on an estimated row in the new field order; 2x text keeps the
   title on one line and Cancel/Save side by side.
3. `03-inbox-dating-offers-remember.png` (and 2x): after dating Mango, Keeps
   for is still empty and `Remember: keeps 12 days` sits under Expiration.
4. `04-changed-estimate-offers-update.png` (and 2x): moving the strawberries'
   estimate two days earlier offers `Remember: keeps 5 days`.
5. `05-add-autofills-date-and-location.png` (and 2x): picking "Carrots, cut" in
   Add fills Expiration (today + 2 weeks) and Location (Fridge).
6. `06-labeled-inbox-item-suggests-date.png` (and 2x): the undated yogurt
   offers `Like last time: 2026-12-04` with Expiration still empty.
7. `07-calendar-opens-on-suggested-date.png`: the yogurt's calendar opens on
   2026-12-04 instead of today; OK picks it, Cancel leaves Expiration empty.
8. `08-field-order-before-after.png`: cropped Before (r1 draft) | After (r2)
   of the row editor: Location moves up under Expiration, Store link goes last,
   Container size sits between Keeps for and Keep at least.

Known and unchanged by this feature: the dialog's tight side padding at 2x,
Food name autofocus in the row editor, and the centered "Also changes N other
containers" line (all existing app behavior; the padding is already on the open
UX list). If Lee finds "Keeps for" and "Keep at least"
confusable even apart, the fallback label is "Shelf life".
