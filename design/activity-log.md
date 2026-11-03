# Activity log — next release design (2026-10-30)

Accepted scope: Lee requested a visible, read-only cross-writer Activity log,
interleaved by occurrence, with user/device attribution. This supersedes only
the browsable-audit exclusion in agent-interface.md §6; cross-writer Undo stays
excluded. Bulk-editor Cancel continues to exit selection.

## Canonical derivation and attribution

Use published UnifiedSnapshot records (sequence at or below the per-writer
published frontier; dependency-blocked validated records are omitted), not directory modification times, receipt
arrival or a new log. One atomic record is one activity; historical envelopes
retain their original semantic writer and clock. Canonical history records the
writing installation, not the active person, and the app does not start
recording one (Lee 11-02): rows show the device only, with no repeated
"user not recorded" line. Names are advisory, not authenticated identities;
assignees are not actors.

## Values (Lee 11-02)

Goal: the log says what changed in plain terms. Rows and details name the item
as the action recorded it (food name and brand, task title, person name) and
list each changed field as `Field: old → new`. Details show no UUIDs; an
unnamed device keeps its installation ID, the only way to tell it apart.

Method (`lib/application/activity_values.dart`, derived on demand per visible
row or opened details, never during list derivation):
- Old value = the field's value in the action's causal past: writes it observed
  through its record's `observed` frontier. Imported historical records have no
  frontier; their app replayed in clock order, so that order is their history.
- Only the new value is shown when the prior value is not single and certain:
  another device wrote the same field concurrently, the observed latest writes
  disagree, or an Undo/completion changed it without a readable value. A write
  that keeps the observed value is not listed.
- Native title/notes edits replay shared text for the causal prefix with a
  disposable resolver over already admitted events (`RecurringTextInput
  .fromAdmitted`; no memo, receipt or write). Visible rows resolve one per frame
  after first paint; details resolve on open. Long or multi-line text shows the
  changed part with context.
- Measured on a private copy of real history (1,990 records): row values for all
  records 10 ms in total, text replay 3–32 ms per action.

## UX brief: list, details and Open (Lee 11-02 23:20–23:31)

Checked against [ux-principles.md](ux-principles.md).

**List.** Answers "what changed lately, on which device, and to what?"
- Day headings: Today, Yesterday, then `Monday · 2026-10-26` (the Tasks
  heading format). Rows don't repeat the date.
- Row: line 1 is the event and its item (`Food edited: Oat milk (Dairy Co)`).
  Then up to 3 change lines (`Location: Pantry → Fridge`, field label medium
  weight), then `+N more`. Last is a muted meta line: `23:09:27 · Kitchen tablet`.
  A UTC offset appears only when the entry's offset differs from the device's
  current one (DST, travel). An unnamed device shows `Unnamed device · 1a2b3c4d`.
- Device renamed reads like any other edit: `Name: Old name → New name`.
- Left out: full dates on rows, user line, IDs, action codes, shared-text
  setup records (bookkeeping, not an action), filtering and search (deferred
  until real logs prove too long to scan).
- A deleted task keeps its name: the title as of the deletion, replayed when
  only native text holds it.
- Next action: tap a row for details.

**Details dialog.** Answers "what exactly did this do, and where is that item now?"
- Title: the row's line 1. No generic "Activity details" title, no repeated
  first line.
- Changes: every change, one per line, label column then `old → new`; long
  values wrap under their own value column.
- Footer: one muted line in the row's meta format with the full date,
  `2026-11-02 23:09:27 · Kitchen tablet`; a second muted line `Now named X`
  only when the item has since been renamed.
- Spacing: tight within a group, one even gap between title, changes and footer.
- Left out: "Imported historical record" (help covers imported history), IDs.
- Phone widths (<600) use 16px dialog margins instead of 40. Changes use a
  label column unless a typical label ("Expiration") would take over 40% of the
  width, then each value stacks under its label; the rule is the same for every
  dialog at a given width and text size.

Independent screenshot review (2026-11-03, 30 native GTK captures, dark/light,
1000/390 px, 1x/2x) found first device naming without an old value, the
shared-text setup row, a smaller footer than the row meta, an oversized title,
food and task dialogs laying out changes differently at 390 px 2x, wide margins
at phone width, and an unnamed deleted task; all fixed. Not changed here:
Material shrinks dialog padding at large text app-wide, and icons don't scale
with text (both app-wide); the editors' Title field and buttons at 2x are
pre-existing and queued separately.
- Next action: **Open** jumps to the food or task (its editor, clearing search
  and filters that would hide it). Hidden when the event has no single item or
  the item no longer exists (a removed food still exists, in Deleted). Close.

## UX brief: dialog height, batched entries, store links (Lee 11-03)

Checked against [ux-principles.md](ux-principles.md).

**Height.** The log uses the window's height (dialog insets only), keeping its
640 px maximum width; no fixed 480 px box with empty space around it.

**Batched entries.** Answers "what did that import (or bulk edit) do, item by
item?" One record can hold several separate changes: a receipt import adds a
food per line, a bulk edit changes several foods.
- What counts as one change: the effects for one item. A task's add and its
  positioning are one change; a product or purchase that exists only for a food
  add (or link) belongs to that food. A food operation over several containers
  stays one change (`Beans ×3`) when every container got the same values, and
  splits per container when their values differ (different old locations).
- A record with one change looks exactly as before.
- A record with several: line 1 is a summary by the dominant change, counted
  in the rows it expands to: `6 foods added from a Walmart purchase` (store
  only when the record's purchases share one), `3 foods edited`, then
  `, 2 other changes` when kinds are mixed. Below it the first item names
  (`Oat milk, Beans and 4 more`) and the usual meta line. A trailing chevron
  shows it expands.
- Tap (or Enter) expands it inline; the parts appear indented under it, each a
  normal row built by the same row/details code as a single-change record.
  Parts leave out the meta line: time and device are the parent's (a heading
  states what's shared). Tapping a part opens the ordinary details dialog for
  just that change, with Open. Tap the parent again to collapse.
- Left out: a special batch dialog, per-part times, purchase bookkeeping lines.
- Product name/brand/size lines that only repeat a new food's own description
  are left out of a food add; store link and Keep at least stay.

**Store links.** Show the store's name as the link text (`Walmart`), not the
URL: Activity change lines, and the Running low and row menu actions
(`Open Walmart link`). Known stores by domain; else the domain without `www.`.

Independent screenshot review (2026-11-03, 24 native GTK captures, dark/light,
1000/390 px, 1x/2x): fixed the item-names line losing its count at 2x (now
every name when three or fewer, and it wraps), change lines cut at 390 px 2x,
the chevron squeezing the summary (it now shares line 1) and even spacing inside
an expanded group (parts sit tighter). Judgment calls left for Lee: "Store link:
Walmart" on every part of a Walmart purchase, the pale notice bar in light theme
(app-wide), title and icon sizing at 2x (app-wide).

**Completion notice.** `Completed 1 task. Next due 2026-11-10.` (or `Next
starts …`; `Next occurrence scheduled.` without a date or for several).

## Ordering and clock skew

Newest recorded occurrence first, based on the existing wall-time-informed
causal clock; ties break deterministically by semantic reference stream, sequence and ID. Current installation labels are
advisory and may differ from the name at the time of the action.
Historical envelopes use the original effect clock, not migration time. These
clocks are max(wall time, observed + 1), so causal observation and future device
skew can move displayed timestamps forward. Without independent clock evidence,
true physical occurrence across offline devices cannot be recovered. Explain
this in on-demand help: recorded device time, affected by clock skew, not arrival
order. Never silently clamp, rewrite clocks, or claim exact real-world ordering.

## UI and cost

Activity log is reached from the existing toolbar menu alongside Settings;
read-only, lazy rows, details on demand, narrow/wide layouts and large text.
No replay or canonical writes just to browse; refresh uses admitted snapshot
notifications. Empty/loading/error states remain explicit. Attribution and
refresh-error copy scroll with the lazy history rows, so large text and short
windows cannot collapse the retained history viewport; no error copy or
attribution is removed to make rows fit. Build derived rows
only while the log is open and only when its admitted revision changes. Opening
and scrolling need bounded visible-response review with realistic history growth;
`activity.read.derive` is registered before measurement at 15ms median / 30ms
maximum on all three matched-history shapes, using the unchanged ordinary
paired-growth rules. No existing limit changes. That label bounds derivation and
sorting, which lazy rows don't. It doesn't bound what a person sees: native
first-visible, scrolling, details and incoming refresh have no numeric budget and
no timed gate, and must be reviewed natively before acceptance, on realistic history.

## Other next-release fixes

Suppress the Food recovery banner for healthy in-flight writes, retaining it for
unresolved reservations/failures. Constrain Move some title/content at 200% text
with keyboard and allow Enter in its free-text location without bypassing an
active autocomplete selection. Increase the slow Windows CLI integration test
margin only (not product/performance budgets), retaining finite timeouts.

## Verification / release

Focused invariant/widget tests, independent code/design/editorial review, dark
native GTK and Android workflow/media, current-source unchanged-budget reference
qualification and mandatory hosted correctness/build/signing/install gates.
Publish an immutable signed prerelease, never Latest; no stable promotion or live
household data. Identity limitation above must remain explicit in evidence.
