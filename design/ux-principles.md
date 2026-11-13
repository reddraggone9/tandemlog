# UX principles

Lee's accumulated UI preferences as short rules. Every UX brief and independent
screenshot review checks against this list (see the UX pass in `AGENTS.md`).
Add a rule, with its date, whenever Lee corrects a UI; replace a rule instead of
contradicting it. Rules dated 9-30–10-24 come from Lee's earlier decisions with Nibbler.

## Content
1. Less is more: every label, line and control earns its place; drop what says the same thing on every row (11-02).
2. Show the actual values and what changed (`Field: old → new`), not metadata about the change (11-02).
3. No internal IDs, UUIDs, action codes or storage jargon. Show an ID only when it's the only way to tell things apart, e.g. an unnamed device (11-02).
4. Don't show a line that is always the same or always unknown ("User not recorded") (11-02).
5. A heading states what's shared; rows don't repeat it. Group by relative day (Today, Yesterday, weekday + date) instead of a full date on every row. An expanded group's summary is its heading: parts don't repeat its action (`Oat milk`, not `Food added: Oat milk`), and it drops its own item-names line while the parts show (10-26, 11-02, 11-05).
6. Precision matches use: times to the second at most; show a UTC offset only when it differs from the device's current one (11-02).
7. Name things the way the person knows them: food name and brand, task title, device name (11-02).
8. Lines that don't apply disappear entirely instead of showing blanks or placeholders (10-28).
9. Defaults instead of setup questions; no permanent explanatory text or manual refresh buttons. Help is on demand, behind a ? next to the editor title (9-30–10-24).
10. Labels use the app's own field names (Start/Due, not "planned"/"deadline") (9-30–10-24).

## Layout
11. Consistent spacing: tight within a group, one even gap between groups; never a mix of padded single lines and packed lists (11-02).
12. A dialog's title is the thing itself, not a generic "Details"; don't repeat the title as the first line (11-02).
13. Rows of the same kind look alike: a special list reuses the regular row's line order and style (10-28).
14. Size to content; no large empty bands between content and buttons (10-27).
15. One control per job; no two adjacent pickers that do the same thing (10-27).
16. A single-line field stays one line at narrow widths and large text: ellipsize, never wrap a hint taller than a filled value (10-27).
17. Bound long content on rows (e.g. 3 change lines, then "+N more"); details show everything (11-02).
18. Dialogs use the space they have: a list dialog fills the window height (insets only) instead of a fixed box (11-03).
19. Nothing moves under the finger and nothing resizes a dialog: suggestions are overlays; entering selection adds no checkbox column or row shift; changing the selection while a side pane is open swaps its content in place without a closing flash (9-30–10-24, 10-28, 10-29).
20. Editor dialogs stay vertically centered, not pinned to the bottom of the window (10-27).
21. Layout follows window width, not device type; Tasks and Food share components and behave the same instead of drifting apart (9-30–10-24, 10-28).
22. Grouped changes can be expanded: one action that changed several things shows a readable summary that opens inline into ordinary rows, not a special dialog (11-03). The rows inside read as its contents (smaller text) and show they can be tapped; the expand chevron never splits the summary's words (11-05).

## Actions and discovery
23. Offer the next action the person will want from where they are: open the item, the store link, Undo (10-28, 11-02).
24. Hide an action or entry when it can't apply (deleted item, empty filter) instead of showing it disabled (10-28, 11-02).
25. Secondary states live where they belong (a filter entry with its count), not as banners above the list (10-28).
26. An indicator must be explained where it leads: a warning dot on a button needs a matching mark on the entry inside (10-28).
27. Selection, search and editing stay usable together; one mode shouldn't silently hide or clear another (10-28).
28. Links show readable labels: the store's name (`Walmart`), never the raw URL (11-03).
29. Plain status wording over internal terms: `Next due 2026-11-10`, not `Next occurrence kept` (11-03).
30. Validation: errors appear beside the field and Save becomes Review errors; a fresh form never starts red; quick capture and simple forms just disable the action (9-30–10-24).
31. Bulk actions feel like one action: one Undo reverses them (9-30–10-24).

## Startup and errors
32. Never show an error or onboarding screen before something has actually failed or nothing is set up; while the workspace opens, show the app name and a progress bar only (11-03).
33. Error screens lead with what happened and what to do, in plain words; technical details are collapsed, with Copy (11-03).
34. Startup never freezes the UI: the progress bar keeps moving (11-03).

## Evidence for Lee
35. Review captures: dark theme, real native build, cropped Before | After; label widget or synthetic captures as such (10-26).
36. Release notes: user-visible changes only, one change per bullet (10-27).

37. Suggestions live in the field they change: dimmed until accepted, with an in-field apply button; no separate offer line (Lee 11-13).
