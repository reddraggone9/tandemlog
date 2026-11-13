# 2026.11.2-rc.1

- Set a food’s **Keeps for** duration to estimate expiration dates for receipt imports and new entries.

  ![Before: no shelf-life field; After: Keeps for and the source of an estimated expiration date.](media/rc117/food-keeps-for.png)

  ![Before: adding Carrots, cut leaves Expiration blank; After: its two-week Keeps for duration prefills 2026-11-23.](media/rc117/food-autofill.png)

- Remember a newly entered expiration duration for that food’s future entries.

  ![Before: entering Mango’s expiration offers no duration to save; After: Keeps for offers the 12-day interval to remember.](media/rc117/food-remember.png)

- Estimated expiration dates show **est.** in the Food list.

  ![Before: Strawberries shows 2026-11-14 without a marker; After: the same date is marked est.](media/rc117/food-estimated-list.png)

- New food entries and receipt imports prefill the food’s usual location.

  ![Before: Location is blank when adding Carrots, cut; After: Fridge is prefilled.](media/rc117/food-usual-location.png)

- Undated food can suggest an expiration date based on last time.

  ![Before: an undated yogurt has an empty Expiration field; After: a dimmed date suggestion can be applied.](media/rc117/food-date-suggestion.png)

- Food editors put **Location** directly below **Expiration**.
- **Store link** now follows **Keep at least**.
- Last-price dates now include the year (`YYYY-MM-DD`).
- Long task titles can use up to six lines in the editor.

  ![Before: the long task title is cut off after two lines at 200% text; After: all three lines are visible.](media/rc117/editor-title.png)

- When editor buttons need more room, **Save changes** gets its own full-width row.

  ![Before: large-text task actions wrap unevenly; After: Delete and Cancel sit above a full-width Save changes button.](media/rc117/editor-actions.png)

- Repeat rules accept lists with “and” and serial commas, such as “every week on Monday and Friday”.
- Normal workspace reopening has shorter pauses in its progress animation.
