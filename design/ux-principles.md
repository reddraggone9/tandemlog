# UX principles

Lee's accumulated UI preferences as short rules. Every UX brief and independent
screenshot review checks against this list (see the UX pass in `AGENTS.md`).
Add a rule, with its date, whenever Lee corrects a UI; replace a rule instead of
contradicting it.

## Content
1. Less is more: every label, line and control earns its place; drop what says the same thing on every row (11-02).
2. Show the actual values and what changed (`Field: old → new`), not metadata about the change (11-02).
3. No internal IDs, UUIDs, action codes or storage jargon. Show an ID only when it's the only way to tell things apart, e.g. an unnamed device (11-02).
4. Don't show a line that is always the same or always unknown ("User not recorded") (11-02).
5. A heading states what's shared; rows don't repeat it. Group by relative day (Today, Yesterday, weekday + date) instead of a full date on every row. An expanded group's summary is its heading: parts don't repeat its action (`Oat milk`, not `Food added: Oat milk`), and it drops its own item-names line while the parts show (10-26, 11-02, 11-05).
6. Precision matches use: times to the second at most; show a UTC offset only when it differs from the device's current one (11-02).
7. Name things the way the person knows them: food name and brand, task title, device name (11-02).
8. Lines that don't apply disappear entirely instead of showing blanks or placeholders (10-28).

## Layout
9. Consistent spacing: tight within a group, one even gap between groups; never a mix of padded single lines and packed lists (11-02).
10. A dialog's title is the thing itself, not a generic "Details"; don't repeat the title as the first line (11-02).
11. Rows of the same kind look alike: a special list reuses the regular row's line order and style (10-28).
12. Size to content; no large empty bands between content and buttons (10-27).
13. One control per job; no two adjacent pickers that do the same thing (10-27).
14. A single-line field stays one line at narrow widths and large text: ellipsize, never wrap a hint taller than a filled value (10-27).
15. Bound long content on rows (e.g. 3 change lines, then "+N more"); details show everything (11-02).

16. Dialogs use the space they have: a list dialog fills the window height (insets only) instead of a fixed box (11-03).
17. Grouped changes can be expanded: one action that changed several things shows a readable summary that opens inline into ordinary rows, not a special dialog (11-03).

## Actions and discovery
18. Offer the next action the person will want from where they are: open the item, the store link, Undo (10-28, 11-02).
19. Hide an action or entry when it can't apply (deleted item, empty filter) instead of showing it disabled (10-28, 11-02).
20. Secondary states live where they belong (a filter entry with its count), not as banners above the list (10-28).
21. An indicator must be explained where it leads: a warning dot on a button needs a matching mark on the entry inside (10-28).
22. Selection, search and editing stay usable together; one mode shouldn't silently hide or clear another (10-28).

23. Links show readable labels: the store's name (`Walmart`), never the raw URL (11-03).
24. Plain status wording over internal terms: `Next due 2026-11-10`, not `Next occurrence kept` (11-03).

## Evidence for Lee
25. Review captures: dark theme, real native build, cropped Before | After; label widget or synthetic captures as such (10-26).
26. Release notes: user-visible changes only, one change per bullet (10-27).
