# Independent RC notes/media recheck — editorial pass

Reviewed 2026-11-13. **Publication editorial pass: all material findings in review.md are resolved.** This is a notes/media review, not candidate qualification, native artifact acceptance, authorization to promote stable, or a claim that publication has occurred. No draft, media, provenance, application source or release checkout was edited by this reviewer; only this report was written.

## Exact range and independence

- Previous stable build116: `v2026.11.1`, `ef71b8806fb93da3a9d2ce82f3610e86d044f05e`.
- Current release checkout HEAD: `02cb56e5d3f9028860f140d00602deabfa781675`, `/home/nibbler/tandemlog-rc-20261113`.
- Prior review HEAD: `5268ac336e37b093f48f042a48a10d8500b59122`. The committed delta since that review changes only `tool/qualification/prepare.sh` and `tool/test_release_tooling.py`. Independently checked `git diff 5268ac3 -- lib`: empty, including current working-tree application files. Existing uncommitted release-policy/tooling/evidence changes are not new end-user features and were not edited here.
- Read actual revised notes.md, provenance.md, previous review.md, crop recipe, stable capture fixture/log, current release-notes/media rules and UX principles. Checked stable-to-current inventory and the relevant production diffs; the prior complete production-diff review remains applicable because application source is unchanged.
- Worker quota checked using `worker-quota-policy.py --running-on chatgpt --chatgpt-only`: CONTINUE, ChatGPT week94%, floor30%.

## Finding-by-finding result

1. **Field order: resolved.** Location directly below Expiration and Store link following Keep at least are separate precise bullets. Neither claims Store link is last. Last-price year remains a separate bullet and is visible in the shared full editor comparison.
2. **Shelf-life behavior/media coverage: resolved.** Setting Keeps for and remembering a newly entered duration now have separate bullets. The real automatic-prefill and Remember duration pairs are linked with accurate alt text beside the respective prose. The added list-marker bullet has its own genuine list-row comparison, not an editor substituted for list evidence.
3. **Bounded title and conditional actions claims: resolved.** Notes specify up to six title lines and give Save changes a full-width row only when editor buttons need more room; these match the current maxLines and width-measurement branches.
4. **One change per bullet: passed.** Receipt imports and new entries describe the same expiration/location defaults in their applicable entry paths, not unrelated changes hidden together. Other meaningful changes remain separately listed; no QA, implementation, signing, routine update-warning or portable-ZIP boilerplate was introduced. Repeat-list grammar and the deliberately limited normal-reopening animation claim remain accurate.

## New list-row evidence and image verification

- Visually inspected all eight final composites at native scale, including the new food-estimated-list.png and newly linked food-autofill.png / food-remember.png. All are readable, real-app dark comparisons with centered Before/After labels, matching synthetic records and no visible private data, credentials, UUIDs or household paths. Minor underlying synthetic dialog-edge slivers remain non-blocking, as in the previous review.
- New list pair shows the same Strawberries row, `2026-11-14`, Fridge and unchanged quantity/actions; After visibly adds `est.`. The stable-to-current food_page.dart diff implements that suffix for estimated groups. This comparison correctly demonstrates the marker, not old receipt-import estimation behavior.
- Stable raw list SHA256 is `a766d6a4e57fec89a570a64e747679992a60a18a96eef6e2cca28b0923fea5e3`, independently identical to the retained actual stable run-2 capture. Stable capture checkout still resolves to the exact stable SHA, with only the untracked capture harness and no tracked edits. The retained passing native log and harness explicitly cover the list capture.
- After raw list is byte-identical to retained r3 `keeps-for-01-list.png` (SHA256 `8a3d371eb4035a36bf9844fd7f0f2a589905ce479efeeeeeb4a95e926aaa0cac`). Compared cached After rendering sources with current release: food_page.dart, food_products.dart, shelf_life.dart and civil_date_input.dart are identical; food_editor.dart differs only in the two disclosed comments. These are final rendering behavior, not a mock-up.
- Independently extracted and compared both new composite app regions to their raw `(412,58,0,394)` crops: exact RGBA pixel matches, no scaling or retouching. Fixture/recipe/provenance document matched dark 412×892, DPR1, text scale1, fixed date and synthetic data.
- All eight notes image links resolve. All eight final image checksums pass `sha256sum -c artifacts/tandemlog-rc-20261113/SHA256SUMS` from the workspace root.

## Integration handoff

No required editorial fixes remain. Preserve the approved prose/images; integrate selected PNGs into the repository, replace local relative review links with exact-commit image URLs, and record this recheck plus the covered range with candidate evidence before publication. These are the already documented integration steps, not a reason to withhold the editorial pass from this local handoff. Publication gates and stable acceptance remain outside this review.
