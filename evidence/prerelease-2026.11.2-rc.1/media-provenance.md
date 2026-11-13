# RC117 notes and media provenance

Prepared for 2026.11.2-rc.1 / build117. This directory is a handoff, not a release-tree change or publication. Editorial review is still the parent's independent step. `notes.md` uses relative image links for review; at integration, move selected PNGs into the repository and replace links with raw.githubusercontent.com links pinned to the commit containing those images. No images become release assets.

## Coverage

Previous stable: `v2026.11.1` / `ef71b88` (build116). Feature tips: food `b38528ba1ff46eea7117b823e09323fb216f6123`; startup/editor `b31b23abe9b09eabcc7959acbca5f5d6253a94e8`; repeat `91ad0dd`. Diff review should use stable to final integrated candidate, including any extra changes made by the parent. Notes cover these assigned branches only. They do not claim full first-launch freeze removal: the uncached validator still has a long stall. No timing, QA, packaging or Windows ZIP boilerplate is in the notes.

## Food Before: actual previous stable, newly captured

Native Linux GTK debug build from stable `v2026.11.1`, not r2 or an abandoned mock-up. Isolated checkout `/home/lee/.cache/tandemlog-rc-media/repo`; only untracked `integration_test/zz_rc_media_test.dart` added, no production file edits. Reproduction harness copied here as `zz_rc_media_test.dart`; private Xvfb/D-Bus runner `native-run.sh`. Run `RUN=2 bash /home/lee/.cache/tandemlog-rc-media/native-run.sh`. Output `/home/lee/.cache/tandemlog-rc-media/run-2/shots`, copied to `raw/before/`; passing log `stable-capture.log` (1 native capture case). First attempt failed because the new `prefill` link property does not exist in stable; it produced no captures and is retained in cache `run-1`. Corrected harness removes that property and Keeps for product metadata, leaving the same synthetic foods, purchase dates, prior expiration history and locations. The Strawberries expiration already exists in both captures; this comparison shows the editor/estimate explanation, **not** proof of old receipt import behavior.

Dark production Tandemlog theme, 412×892 logical/physical pixels, DPR1, text scale1, date fixed 2026-11-09. Synthetic names only; no real household food records, devices or synced data.

## Food After: final matching native captures reused

Source `/home/lee/sync/wiki/vex/artifacts/tandemlog-keeps-for/r3/linux/keeps-for-{01-list,02-estimated-row,04-remember,05-like-last-time,06-add-autofill}.png`, copied to `raw/after/`. Native GTK, same dark production theme, fixture, viewport and scale as Before. Those captures came from `/home/lee/.cache/kf-native/repo`, base `dcc75a4` plus uncommitted r3 feature changes. Compared production files to final `b38528b`: food_page.dart, food_products.dart, shelf_life.dart, civil_date_input.dart byte-identical; food_editor.dart differs only in two comments (old wording about offers and sample price date). Thus these are final behavior, not prototypes. See original `r3/FINAL.md`, `r3/logs/linux-workflow.log`, cache `run-r3-evidence/test.log` and native harness. Supplemental disclosure changes do not affect these default-scale captures.

## Editor: existing native pairs reused

Original files `artifacts/tandemlog-startup-20261113/before-after-{title,actions}.png`, copied to `raw/editor-*-pair.png`. Each 716px-wide source has Before left358 / After right358, GTK dark 390×850 at 200% text; identical synthetic title “Plan the weekend trip to the lake with everyone”. Before source `99d8bc5` (stable116 + docs/tooling); verified `git diff v2026.11.1 99d8bc5 -- lib/presentation/task_editor.dart` is empty. After UI source `e456dfe`, unchanged through `b31b23a`. This is shipped-stable-equivalent Before, not a discarded feature implementation.

Original uncut screenshots: `artifacts/tandemlog-startup-20261113/{before,after}/editor-{top,actions}-390-dark-200.png`. Capture harness: `investigations/tandemlog-coldstart-20261113/zz_editor_2x_test.dart.txt`; final five-variant harness is retained untracked in `/home/nibbler/tandemlog-startup-20261113/repo/integration_test/zz_editor_2x_test.dart`. Source details and native review in that investigation's CHECKPOINT.md.

## Crop recipe and media selection

`python3 compose.py` reproduces all eight PNGs using ImageMagick and Noto Sans. It records exact (width,height,x,y) tuples for every crop. No app pixels resized, redrawn, altered or retyped. It crops authentic captures, adds 1px #46504c edges, top-aligns on #1b211e canvas, adds centered Before/After labels (18px), then an 8px outer margin. Different dialog heights are retained.

- `food-estimated-list.png`: one matching Strawberries list row, date 2026-11-14, Fridge, quantity and actions unchanged; After adds **est.**. Both crops are (412,58,0,394), including row dividers but no adjacent food rows.
- `food-keeps-for.png`: full Strawberries dialog, also explains field reordering and full last-price date. Linked once in notes; the field-order and price-year changes do not need duplicate images.
- `food-usual-location.png`: same Carrots, cut Add dialog's Location field before/after. Separate tight crop for this independent change.
- `food-date-suggestion.png`: same Greek yogurt dialog header through Expiration before/after. Dimmed date is a suggestion, not applied data.
- `editor-title.png` and `editor-actions.png`: separate crops for the two large-text UI changes.
- `food-remember.png`: linked full Mango dialog with Remember duration offer (entered expiration 2026-11-19 both sides).
- `food-autofill.png`: linked full Carrots, cut Add dialog, blank expiration before vs 2026-11-23 after (two weeks from fixed today). Linked beside Keeps for prose to show automatic expiration prefill separately from the stored duration.

No still image for shorter startup pauses (a still cannot demonstrate animation timing), nor repeat parsing (the UI layout did not change; the concrete accepted phrase is clearer in prose). Native screenshots are lab builds, not screenshots of the eventual exact candidate bytes. Independent editorial review remains pending.

## Author visual check

Viewed all seven original composites at initial delivery: both labels centered, readable native text/icons, dark theme and matching scale, no private records. Native stable capture case and process exited0. Reused After app differences are comments only for the affected rendering. Startup note deliberately says shorter normal-reopen pauses, not faster startup or no freeze. Quota checked repeatedly during preparation; latest ChatGPT remaining week94%, above floor30%.


## Editorial corrections after review.md

Applied the required wording corrections: Location directly below Expiration and Store link following Keep at least are separate bullets; title growth is bounded to six lines; the full-width Save row is conditional on buttons needing space. Split setting Keeps for and remembering a newly entered duration, linked both existing automatic-prefill and Remember duration comparisons beside their prose, and added the independent list **est.** bullet with `food-estimated-list.png`.

The new pair uses the **already retained actual stable native list capture** `raw/before/list.png`, not a reconstructed or edited row. It is byte-identical (SHA256 a766d6a4e57fec89a570a64e747679992a60a18a96eef6e2cca28b0923fea5e3) to `/home/lee/.cache/tandemlog-rc-media/run-2/shots/list.png`; stable checkout HEAD was rechecked as `ef71b8806fb93da3a9d2ce82f3610e86d044f05e` with no tracked edits. The existing retained harness and `stable-capture.log` cover this list capture. No recapture or production edit was necessary. After is the existing matching r3 `keeps-for-01-list.png`, retained in full as `raw/after/01-list.png`, with the same revision equivalence to final food tip described above. Matching synthetic Strawberries row: expiry 2026-11-14, estimated flag true, Fridge, full quantity, fixed today 2026-11-09. Native dark 412×892, DPR1 and text scale1 on both sides. Neither crop contains another record or private data. Recipe adds labels/edges only; no app pixel retouching or resizing.

Only this artifact handoff was changed; no release checkout was changed. Independent parent recheck remains required; this author correction is not a publication pass. Worker quota rechecked with `worker-quota-policy.py --running-on chatgpt --chatgpt-only`: week94%, floor30%, CONTINUE.

Author correction check: visually inspected the new list pair and both newly linked supplemental pairs; the list pair is a single readable matching row with centered Before/After labels. All eight note image links resolve; all eight final PNG checksums are refreshed in `SHA256SUMS`. The full original stable list capture is preserved unchanged.
