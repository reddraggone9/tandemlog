# Independent RC.5 editorial/media review

## Outcome: HOLD — nine priority comparisons accepted; complete task not approved

Independent read-only review of the actual draft notes, final PNGs, provenance and exact covered source range. The nine priority comparisons are honest, useful native media for their stated scope. They and concise prose satisfy the repository's ordinary editorial screenshot policy. They do **not** satisfy the direct task's stricter per-UI-change requirement: two editor regression fixes still lack reliable native Before/After contrasts. There is also an actionable compatibility omission in the proposed public notes. Material revisions require a recheck; this is not publication or signed-candidate acceptance.

## Must address

1. **Per-UI-change evidence gap: search reset and Undo after Cancel.** The last draft bullet claims both fixes. The exact source diff supports their intended repair: stable list mounting in `EditorSurface`/Tasks and `setState` around `closingEditor`. None of the nine final comparisons depicts either regression. The gallery honestly says earlier native attempts retain the query on both revisions and usually repaint baseline Undo after Cancel. Those exploratory screens are not evidence of a Before failure and cannot be promoted into approved comparisons. Finish the separate reliable native reproduction/comparisons, or explicitly leave this direct-task coverage pending. Ordinary policy allows prose-only small fixes; that exception cannot silently override the direct request. Removing the bullet alone would not prove a changed workflow.

2. **Restore the exceptional converted-workspace requirement for public notes, unless the author can establish it no longer applies.** Candidate-source `design/prerelease-notes.md` explicitly states: “This preview requires a converted unified workspace. Use your migrated test copy; it does not convert older workspaces.” The proposed notes omit this entirely. Candidate `design/schema.md` says old wire decoders are absent; `design/status.md` identifies RC.4/build99 as unpublished, while RC.3/build98 remains the published preview. This is an unsupported upgrade/manual preparation boundary, not routine cross-device-update boilerplate. Retain one concise actionable sentence or a clearly linked instruction, without implementation/QA exposition. Do not restore generic signing, preservation, reader-revision, or multi-device warnings.

## Policy and covered-diff assessment

Read source `AGENTS.md`, `design/README.md`, and the current editorial rules in `design/releases.md` (especially lines 86–92). Rules require accurate change coverage, honest matched native captures, useful crops/alt text, private-data exclusion and a distinct review; screenshots remain optional when prose suffices under the general policy. The direct assignment is stricter and takes precedence.

Exact range: Before `137313d23386cfd73aff5c6128bee3122da829aa` (RC.4/build99) → After `41b8f21ec1d487597233d79293dbd394f0f36591` (RC.5/build100), one covered commit. Independently regenerated read-only `git diff -- lib linux` is byte-identical to `covered-production-ui-domain.patch`. Inspected actual UI/domain hunks, range/file inventory and relevant full-Git-diff follow-ups: completed-instant/group/order logic, Today horizon, Tasks carry/focus/editor changes, Food gestures/deleted editor guards, date picker/hint, shutdown UI, Android bounded reads, metadata and design/schema notes. This is an editorial impact review, not a full integrity/code acceptance audit.

- The main prose accurately covers the meaningful visible changes: Today horizon, newest-first viewer-local completion chronology including search, Search/Add text and selection carry, active Food long-press selection, editing deleted Food, month/year jumps and narrow large-text hint wrapping.
- The broad performance sentence describes the direction of substantial cache/projection/native-text changes without inventing measured speedups. Static PNGs do not establish latency or release performance acceptance; those gates remain separate.
- Completed drag restriction is consistent with the new chronological ordering and visible removal of handles; no repetitive QA reassurance is needed in public prose.
- The nine-image gallery is complete for the named priority set. Proposed notes use seven of them; keeping completed-search and enlarged-year supplements engineering-side is reasonable under general policy, since each illustrates the same already-represented change. If the direct requirement is intended to require every priority image inline in public notes, that selection must be reconciled explicitly rather than calling the public draft nine images.
- The public draft contains no implementation transcript, testing assertions, signing/history boilerplate or blanket preservation assurances. “Faster” claims remain subject to independent performance/native acceptance, not established by this review.
- **Do not re-add a Linux shutdown-fix claim.** It is absent from both drafts, correctly. The covered diff adds a `Closing…` UI state, but none of these nine comparisons verifies it or resolves the separately open intermittent abort. It remains outside the accepted priority media, not an implied fixed/accepted shutdown workflow.
- Relative `media/...` paths are valid inside this private review bundle. Before any eventual public handoff, use exact-commit repository URLs or supported attachment hosting as required by policy; no hosting or publishing was performed here.

## Actual visual inspection of every final PNG

Opened and rendered all nine `media/*.png` through image-capable `read`: took the returned PNG data URL and passed it to the image helper. This was direct image inspection, not reliance on manifest descriptions or author self-review.

| Final image | Observation and assessment |
| --- | --- |
| 01-today | Same Mail a letter and Morning appointment, same viewport/theme. Actual old day headings versus new Today heading; tomorrow's full due date remains visible. Readable and sufficiently contextual. The fixed fixture is 09:00 local with the next appointment 08:00 tomorrow, inside 24 hours. |
| 02-completed | Same three synthetic completed tasks; old due-date/manual order versus new completion-local dates and reversed/newest-first order. Full toolbar and list context retained, no fabricated per-row date badge. |
| 03-completed-search | Same Water plants query/result; old scheduled-date heading versus actual completion date. Query and Completed heading are visible and readable. Useful supplemental evidence. |
| 04-search-add | Same actual mode switch: old Add entry empty, new Buy envelopes retained with envelopes selected. Control identity/mode, content and selection are legible. |
| 05-food-longpress | Genuine old long-press resolves to the editor; new long-press produces one selected container and highlight. Unequal crop heights legitimately retain each result's identifying context without resizing. Partial old editor is sufficient to establish that an editor, not selection, opened. |
| 06-food-deleted-edit | Same Beans search/deleted result. Before leaves the tombstoned row; After shows the ordinary complete editor. The dim old row behind the After modal is real modal dimming, not recoloring. No claim that a screenshot by itself proves successful persistence. |
| 07-calendar-month | Same pending February 29, 2028, 320×850 viewport, normal text. Actual old calendar navigation versus new twelve-month body. Both complete dialogs retained; labels readable. |
| 08-calendar-year | Both 200% text at the same narrow viewport. Legacy chooser really initially shows 1968–1979 while its header says February 2028; new chooser includes selected 2028. Harness opens the relevant controls without scrolling the old list. Do not generalize this into a claim that the old picker never supports year selection; 100% baseline evidence is retained. |
| 09-narrow-hint | Same blank focused Expiration input, 320px width and 200% text; actual truncated hint versus complete two-line YYYY-MM-DD. Tight crop retains field label and calendar affordance. |

All use Dark within each matched pair. Tasks and component fixtures use different theme palettes across different pairs, not mismatched themes within a pair. Canvas has subtle dark contrast; only centered Before/After labels are added. Product pixels remain 1:1. Long-press/modal examples retain necessary whitespace/context rather than compress or recolor product UI. Descriptive alt text is present and accurate. No private names, inventory, paths, notifications or credentials appear; Alex Example, Beans and generic task text are synthetic.

## Provenance independently checked

- Tasks: full `TandemlogApp` with isolated profile/shared-folder fixtures, production stores and fixed view clock. Food: production `FoodInventoryPage` mounted in private native integration fixture with synthetic projected operations; no-op callbacks mean these editor images do not establish durable Save behavior. Calendar: production `CivilDateInput` in a private native MaterialApp fixture. These are live native GTK screenshots, not browser/widget-raster substitutes or complete signed installers.
- Tasks/Food use 800×850, device scale1, text scale1; calendar uses 320×850, device scale1, normal month and 200% year/hint. Inputs and action paths match within each pair; calendar's new-only Month/year step is necessary because that control did not exist Before.
- Independently checked both private Tasks/Food and calendar HEAD identities, clean tracked production paths, identical paired harness hashes, and all recorded native bundle file hashes. Tasks/Food receipt script/log hashes matched. Calendar provenance's listed raw/crop/final/script/log file hashes matched. The reused text library is explicitly disclosed and bound to identical `native/text_engine` source trees, not falsely presented as a fresh signed build.
- Independently decoded raw, crop and embedded composite panels with ImageMagick and compared RGB bytes: all eighteen native panels match the stated crops exactly. Verified all three calendar final files are byte-identical to corresponding `media/07..09` copies. No resizing/recoloring or fake pre-image found.
- Native integration logs are existing author capture evidence; no test/build was launched by this reviewer. No source file, production profile, source Git state, release or hosting was changed. Only this review report was written.

## Frozen reviewed SHA-256 snapshot

Review recorded 2026-10-27T04:29:37.656570+00:00. Hashes below identify the actual rendered final files and the reviewed inputs; any material replacement is outside this outcome until rechecked.

### Nine final images

```text
c3e18c8dd6e009047953553e466d579be7adca43c597aa9a1f5b7af50630e6a2  media/01-today.png
06d734ec05b07f9b88e8db6408a849484535a6baaf494fd00db2cb591f0cf1f2  media/02-completed.png
7e27dc3d0c6e1b2e49100ea7a068871b873d1f0bb09a9e0474c57788a415fcf3  media/03-completed-search.png
13ec2c9f43ea134ee091007b91393c463c341589edf506cb2069e8a131b3710f  media/04-search-add.png
e271acf52c128afab0b05db0de5bb91050b73c208f5e98d8d44f15e9bacf4607  media/05-food-longpress.png
241070926b59ebf16478650944f54036d7f17bdcbe0df31c65f414b6e60f6c1b  media/06-food-deleted-edit.png
e197e8c8a40dbb10ecf9cc6c4e166d330acbade30ba5836ebe8f5de4578a44f3  media/07-calendar-month.png
350497fbd97928340fb6e7ecfa7467331b7b7501e2ce87662d73f661bd10322e  media/08-calendar-year.png
af5a21d2afb8d3445fb336b7487912005248ac4e7a554b6d7e9c796a9dbfc848  media/09-narrow-hint.png
```

### Draft and provenance inputs

```text
e2731d5b4cb291840e8eda1dde99200158862901ab08bdf20018be6a09518ab6  proposed-prerelease-notes.md
2e48c734eeecebcf59139174879f1bf63a28782545be5d910248610e5d77a131  notes-copy-only.md
9d95f8b5f8b01836c8f334e7ed40f141243846fc70cab1d28804fe8eeb6854d3  review-gallery.md
f6e80f6689d443b7c88f887a1ea067f079d75e54ec87745c4c30e31c5577bf8c  task-food-media-provenance.json
bf0bc82c7334e6b07229d2da839eec979dc319c058a8807866b46eb4733ec39c  task-food-build-identity.json
6eeacb54e1386bfc44145c20b4345449f4e1a559ab68d0e312a2e9e0bff29354  calendar/README.md
2210beee2861acf12ee97e1eb9b4d4f14a15917582de1c0cb787228e7e3442f5  calendar/media-provenance.json
2a536e07821b97fdc7425aed70a92526390cf0eb3bb730c51611b5dd0e06a43e  calendar/crop-receipt.json
f71a872429a9f1e2fd5da648032f52fe1ba70a8d3203ed22890c8d7d18edc41c  covered-production-ui-domain.patch
9bfa31652dd55d19b7b79412a27fa8185d6a41abbb31710a28521915ee83bc6f  tasks-food/release_media_test.dart
b6d6af54529ece392d6f325a63da447fbc1fd1caf894a3ec7d43e0823d439ff8  calendar/scripts/calendar_media_test.dart
```

### Source policy and complete range binding

```text
6ba1aecb1df90231706415bab3f3c2d09f1ee2e8bc9c023db8620a193aa4475b  source/AGENTS.md
b682cd4a239537cc516a4649a391ecc49910b735b426800b9577b51be1f7399b  source/design/README.md
64d130208453dde9b40144bf761461ae1f7d6b9311c8dfcd005e5e6161c1fb0a  source/design/releases.md
8246573193cd2dc371a85f84d8004df4036036556f30537f71bf224ca648d7e3  full git diff 137313d..41b8f21
```
