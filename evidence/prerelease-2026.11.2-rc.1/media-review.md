# Independent RC notes/media review — changes required

Reviewed 2026-11-13. Scope: RC only; no stable promotion or publication reviewed or performed. Reviewer did not author or modify notes, images, provenance or checkout.

## Exact range and method

- Baseline `v2026.11.1`: `ef71b8806fb93da3a9d2ce82f3610e86d044f05e`.
- Candidate HEAD: `5268ac336e37b093f48f042a48a10d8500b59122` on `vex/rc-20261113` in `/home/nibbler/tandemlog-rc-20261113`.
- Read current `design/releases.md` (including Release notes and media) and `design/ux-principles.md`; inspected exact range changed-file inventory, commit list and complete production `lib/` diff, plus recurrence regression diff and capture harness/recipe. Docs/tooling/receipt changes are not new end-user functionality.
- Read `notes.md` and `provenance.md`; visually inspected all seven composed PNGs (not just filenames or alt text).
- Independently compared reused food After rendering sources against candidate HEAD: food_page.dart, food_products.dart and shelf_life.dart are byte-identical; food_editor.dart differs only in the two comments disclosed in provenance. Existing editor Before/After provenance identifies stable-equivalent Before and final UI After.
- Quota policy checked: ChatGPT week remaining 94%, floor 30%; work allowed.

## Required fixes

### 1. Correct field-order wording and split independent changes

The bullet “Food editors put Location below Expiration and Store link last” joins two changes, contrary to one change per bullet, and “last” is inaccurate: Retention reason still follows Store link in the ordinary Edit dialog, visible in food-keeps-for.png and in the exact food_editor.dart field sequence. Use two precise bullets, for example:

- “Food editors put **Location** directly below **Expiration**.”
- “**Store link** now follows **Keep at least**.”

The existing food-keeps-for.png can illustrate both plus the last-price year; duplicating the same image is unnecessary.

### 2. Finish coverage of shelf-life UI changes and media

The current linked images show a stored Keeps for value, an estimate explanation, a remembered-date suggestion, and location prefill, but not automatic expiration prefill or remembering the newly entered duration. Those are distinct UI behaviors already claimed by bullet 1. Link the existing, inspected `food-autofill.png` and `food-remember.png` with descriptive alt text. Both are dark real-app Before/After pairs with matching synthetic records and readable text; no recapture is needed for them. They can be placed beside the corresponding shelf-life prose rather than leaving all media detached below the list.

The exact diff also introduces the Food list’s **est.** suffix for estimated dates (`lib/food/food_page.dart`). That meaningful user-visible distinction is absent from the notes and all linked crops (the full editor’s estimate explanation is not the list marker). Add a short separate change bullet and one tight dark stable/RC Before/After list-row crop, with matching data, source revisions, raw captures and recipe. The existing After source `artifacts/tandemlog-keeps-for/r3/linux/keeps-for-01-list.png` may be reusable; capture the matching stable Before if not already retained. Do not relabel an editor crop as list evidence.

### 3. Avoid two overly broad editor claims

- Titles now grow to **six lines**, not indefinitely (`task_editor.dart` maxLines = 6). “Long task titles expand instead of being cut off” overpromises for longer text. Suggested: “Long task titles can use up to six lines in the editor.” Existing title crop is appropriate.
- Save receives a full-width row only when the measured labels do not fit, not on every large-text window. Suggested: “When editor buttons need more room, **Save changes** gets its own full-width row.” Existing actions crop is appropriate.

## Passed checks / no additional note required

- Repeat list separator claim matches weekday and month parser changes and accepted examples. A still would add no useful explanation; prose is sufficient.
- Startup wording is appropriately limited to shorter pauses during normal reopening, not a claim that all startup freezes are fixed. No still is needed for animation timing.
- Price-year change is accurate and visible in food-keeps-for.png.
- All inspected media are dark, labeled with centered Before/After, readable, tightly framed at native scale and show synthetic foods/tasks only. No visible private data, credentials, UUIDs or household workspace paths. Minor slivers of underlying synthetic content at full-dialog crop edges are not privacy blockers.
- Notes contain no QA, signing, installer-archive or routine update-warning boilerplate. No routine format-warning should be added.

## Integration checks before publication

The handoff intentionally uses local relative image links. As provenance already says, selected images must be committed into the repository and the integrated notes must use exact-commit image URLs, not local artifact paths or moving branch URLs; images are not release assets. Record the final covered source range and this review plus recheck outcome with candidate evidence. These are integration tasks, not an assertion that a local handoff must already have a public commit.

## Outcome

**Changes required, not a publication pass.** Recheck revised prose, the newly linked supplemental pairs and the added list-row pair before publication. No draft or release checkout changes were made by this reviewer. No application execution/testing was needed for this editorial review.
