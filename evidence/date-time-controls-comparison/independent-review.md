# Independent date/time notes and media review

Reviewer: separate `/root/checklist_model` agent, 2026-10-04. Explicit review request Sentinel_384dba8d4b2c819191ecb4e09003a3ec. Scope limited to date/time notes/media; no broad native-text or release acceptance review.

Reviewed actual `design/date-layout-preview-notes.md`, both final comparison images, raw build43/build44/candidate captures, crop/label recipe, source closure and receipt. Guidance: latest `design/releases.md` editorial requirements committed3ad1485, paragraphs48–54. Historical application diff147a876d799e5832527177fa76c5fdf77c1827a6..e2df9f1de036077d4db7b91fb359f42d204e3d83; new isolated diff e2df9f1de036077d4db7b91fb359f42d204e3d83..2a251aa2c67430584c66cb7c27ee53b5eb0c158a; final capture-only commit3611ba68acc83d103d8892479cd79acd4358e7d8.

## Result

Content/media and exact publication image link PASS after hosting recheck.

- New preview's single bullet accurately limits denser side-by-side rows to enlarged text; no blanket smaller-screen claim. Content-measured threshold, narrower padding and fixed48px icon targets form one user-visible layout improvement, adequately covered without implementation/testing clutter. No exceptional actionable compatibility requirement found in this presentation diff.
- Primary image accurately shows build43 Add time versus build44 directly visible Time, with matching390px/100% data/theme. It explicitly labels already-shipped build44 history and is excluded from the new preview draft. Historical scheduling-before-Tags/Assignee remains separately described in prior notes/context; image need not illustrate every older bullet. Suggested earlier wording matches guidance: “Start and Due now show Time fields directly.” No retroactive published-note edit requested.
- Secondary image accurately shows build44 stacked controls versus unpublished candidate side-by-side at520px/200%. Both Start and Due visible. Before/Candidate labels distinguish release status; figures are contextual viewport/textscale, not universal breakpoint promises.
- Crops retain field labels, dates, icons and Time controls. Text and captions readable at native image size. Blank synthetic dates/times match; raw screenshots show synthetic task text only. No private content visible. Alt text describes the illustrated change. Receipt file hashes all match; task_editor hashes match exact source revisions. Recipe crops recorded actual application pixels and adds labels only. This is native Linux capture provenance, not Android/Windows acceptance.

## Resolved hosting finding

Normal authorized HTTP read of the actual Markdown image URL returned404:
https://raw.githubusercontent.com/reddraggone9/tandemlog/3611ba68acc83d103d8892479cd79acd4358e7d8/evidence/date-time-controls-comparison/secondary-build44-to-candidate.png

After author pushed the exact capture commit on experiment/date-time-layout, reviewer repeated the same normal network read: HTTP200, final URL unchanged (no redirect),39572bytes, SHA2568d33ffa3344c631a3bec326acce723d7d305a56558aeebd5d28f2ef769883029. Public bytes exactly match reviewed local image. The earlier404 is resolved; no blocking editorial/media finding remains. No notes/images were materially modified since visual review. This editorial PASS is not authorization to publish or a substitute for platform/release acceptance.

## Optional

Remove provisional “version assigned only after candidate acceptance” draft header when assembling published notes; assigning the final actual version then suffices. This is draft bookkeeping, not a defect in the actual change description.

No author notes/media/app source edited by reviewer. No publication or commits performed. Material revisions require recheck.
