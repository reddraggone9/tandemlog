# Food density UX review — draft pending stable source notice

Independent reviewer inspected actual Linux GTK pixels. No implementation edits, builds or tests were performed by this reviewer. The original first-slice and v5 closure receipts remain unchanged.

The identical twelve-group dark normal-text fixture moved from 112 px rows to 64 px rows including margin. Fully visible groups increased from 5 to 10 at390×850 and6 to10 at1200×850. The list viewport also differs slightly (650→642 px narrow,688→680 px wide), so this is a matched practical screen comparison rather than a claim of identical viewport allocation. Fonts remain readable and unchanged in the row source; the Inspect target grows from40 to48 px.

All eight dark/light,1×/2×,390/1200 captures were visually reviewed. At2×, rows grow naturally to136 px narrow/104 px wide, with3/5 fully visible groups. No clipped row text or overlapping row actions was observed. The large narrow title and view chips wrap; search hint truncation is a preference/discovery detail rather than an observed row blocker. The shared retention filter remains separately discoverable in Retained. Full large-text editor and keyboard/screen-reader journeys are not covered by collapsed-row screenshots.

Name and contents summary share the first line; prominent expiry and brand form the second. Size/location/physical count and secondary commands live under Inspect. This makes common scanning compact and adds one inspection step for secondary actions; that is a reversible progressive-disclosure tradeoff. Rice remains7 full+1 container⅓ full with8 physical identities in inspection. Its partial container can be selected explicitly, removed, found in Deleted and restored with the same displayed ID. Retained sections start collapsed; Inbox explains the needs-date rule; Deleted explicitly labels its own search and Restore.

One concrete editor defect was found: wrapped expiry helper crowded the certainty floating label. The author inserted12 px separation. The actual preview-accepted/narrow-editor.png closes it; both texts and Add/Cancel are readable. The previous screenshot remains under images/preview-before-spacing-fix. Changed closure frames were separately viewed; unchanged closure frames match prior viewed hashes.

Production-verified narrow/wide captures show Tasks/Food navigation and compact stock. The author-run production log reports4/4 passing tests, including admission safety, isolated Food failure and add/remove/restart/Restore. A prior accepted-named run actually failed an authority-loss assertion; its raw log is retained and is not accepted. Reviewing logs and pixels does not independently establish every durable-data invariant or replace code/security review.

The sampled preview demo has a visible native X pointer and uses Flutter scripted taps plus pointer positioning. It is Linux desktop, not physical touch or Android. Final demo/source binding remains pending the stable notice.

Remaining gates: exact stable source/run binding; broader keyboard and assistive technology workflow checks; actual Windows/Android affected flows and visible-input demos; final artifact/storage/recovery review; release/editorial gates. No private import, live synced data, Android/Windows acceptance or publication is claimed here.
