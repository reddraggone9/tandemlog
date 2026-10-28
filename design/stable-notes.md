# 2026.10.8

Uses the same unified workspace format as 2026.10.7; no conversion is needed.

- Date pickers have a simpler header: tap the month or the year to jump, and the dialog is only as tall as its content. Type dates in the date field itself.

![The date picker before, with a Month / year row, a pencil button and empty space above Cancel/OK, beside the new compact picker with month and year menus in its header.](https://raw.githubusercontent.com/reddraggone9/tandemlog/0cc0fe957434531493e688b63360851c6aa39419/evidence/prerelease-2026.10.8-rc.1/editorial/media/03-date-picker.png)

- Picking a year in a date picker opens that year's months.

![At 320 pixels wide and 200 percent text, the old picker's month list beside the new month grid with the header still fully visible.](https://raw.githubusercontent.com/reddraggone9/tandemlog/0cc0fe957434531493e688b63360851c6aa39419/evidence/prerelease-2026.10.8-rc.1/editorial/media/04-date-picker-month-grid-narrow.png)

- The blank Expiration hint stays on one line again.

![At a narrow width with large text, the blank Expiration field changes from a two-line hint to a one-line truncated hint.](https://raw.githubusercontent.com/reddraggone9/tandemlog/0cc0fe957434531493e688b63360851c6aa39419/evidence/prerelease-2026.10.8-rc.1/editorial/media/01-date-hint.png)

- Add and edit dialogs open centered in the window again.

![The Add food dialog moves from the bottom of the window to the middle.](https://raw.githubusercontent.com/reddraggone9/tandemlog/0cc0fe957434531493e688b63360851c6aa39419/evidence/prerelease-2026.10.8-rc.1/editorial/media/02-food-dialog-centered.png)

- Ctrl+click or Shift+click selects Food rows.

![Ctrl+clicking two Food rows opens an editor before and selects both rows after.](https://raw.githubusercontent.com/reddraggone9/tandemlog/0cc0fe957434531493e688b63360851c6aa39419/evidence/prerelease-2026.10.8-rc.1/editorial/media/05-food-ctrl-click.png)

- Deleted Food rows can be selected for batch editing too.

![Long-pressing a deleted Food row opens its editor before and selects it after.](https://raw.githubusercontent.com/reddraggone9/tandemlog/0cc0fe957434531493e688b63360851c6aa39419/evidence/prerelease-2026.10.8-rc.1/editorial/media/06-food-deleted-longpress.png)

- Batch Food edit changes the name, brand, container size, location or retention reason of every selected container at once.

![Editing three protein-bar containers offers only Brand and Location before; after, it offers Food name, Brand, Container size, Location and Retention reason, each marked Mixed.](https://raw.githubusercontent.com/reddraggone9/tandemlog/0cc0fe957434531493e688b63360851c6aa39419/evidence/prerelease-2026.10.8-rc.1/editorial/media/07-food-bulk-edit.png)

- Batch Food edit can remove or restore the selected containers.
- Select Food rows from the keyboard with Space.
- Today no longer splits into two groups during the repeated hour when clocks fall back.
- Faster incoming Task changes from other devices on long histories.
- Typing stays fast in titles and notes that have been edited many times.
- Sync no longer stops and asks for Retry while another device's changes are still arriving.
- Updates SQLite to 3.54.1, which fixes a memory-safety bug on 32-bit Android phones.
