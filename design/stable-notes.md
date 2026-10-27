# 2026.10.7

**Migration required before updating:** this version cannot open older workspaces and does not convert them. Keep using the previous version until a separate, coordinated conversion is complete. Stop Tandemlog on every device, let sync finish, and convert the workspace with every writing installation included before updating or opening this version. Keep older versions stopped after cutover.

- Task editors have simpler headers and field help for scheduling.
- Forms explain errors beside their fields and offer Review errors; correcting an error restores Add/Save immediately. Empty task capture and user-name inputs stay quiet.
- This occurrence now pairs date and time and requires Due and Repeat; removing either clears its draft value. Existing valid occurrence values without Due move to Due, which can change future repeats.
- Removed the global checklist expand/collapse control.
- Name this device in Settings. Task scheduling also supports CST6CDT, EST5EDT, MST7MDT and PST8PDT.
- Fix stale Tasks after incoming changes while Food is open. Deleted Food dates use softer text.
- Faster repeated startup, incoming sync updates, editing, Save and Undo in Tasks and Food, including recurring-task completion.
- Today includes tomorrow’s timed tasks when they fall within the next 24 hours.

![The next-morning appointment moves into Today, with its actual due date still visible.](https://raw.githubusercontent.com/reddraggone9/tandemlog/ad068998405ffaefe8c9da700aa263028b391e1c/evidence/prerelease-2026.10.7-rc.5/editorial/media/01-today.png)

- Completed tasks—including completed search matches—show newest completion first, with local-date headings instead of repeated dates on each row.

![Completed tasks change from scheduled due-date grouping and manual order to local completion dates and newest-first order.](https://raw.githubusercontent.com/reddraggone9/tandemlog/ad068998405ffaefe8c9da700aa263028b391e1c/evidence/prerelease-2026.10.7-rc.5/editorial/media/02-completed.png)

- Switching between Search and Add carries your text and text selection.

![Switching from Search to Add clears the entry before; after, Buy envelopes and its selected word remain.](https://raw.githubusercontent.com/reddraggone9/tandemlog/ad068998405ffaefe8c9da700aa263028b391e1c/evidence/prerelease-2026.10.7-rc.5/editorial/media/04-search-add.png)

- Long-press an active Food row to start selecting containers.

![The same long-press opens the Beans editor before and selects its container after.](https://raw.githubusercontent.com/reddraggone9/tandemlog/ad068998405ffaefe8c9da700aa263028b391e1c/evidence/prerelease-2026.10.7-rc.5/editorial/media/05-food-longpress.png)

- Edit deleted Food without restoring it.

![Tapping the same deleted Beans search result does nothing before and opens its editor after.](https://raw.githubusercontent.com/reddraggone9/tandemlog/ad068998405ffaefe8c9da700aa263028b391e1c/evidence/prerelease-2026.10.7-rc.5/editorial/media/06-food-deleted-edit.png)

- Jump directly to a month or year in date pickers; date-format guidance no longer truncates at narrow widths with larger text.

![The old February calendar navigation beside the new inline twelve-month jump grid, using the same date and viewport.](https://raw.githubusercontent.com/reddraggone9/tandemlog/ad068998405ffaefe8c9da700aa263028b391e1c/evidence/prerelease-2026.10.7-rc.5/editorial/media/07-calendar-month.png)

![At the same narrow width and 200 percent text, the date-format hint changes from truncated text to complete YYYY-MM-DD on two lines.](https://raw.githubusercontent.com/reddraggone9/tandemlog/ad068998405ffaefe8c9da700aa263028b391e1c/evidence/prerelease-2026.10.7-rc.5/editorial/media/09-narrow-hint.png)
