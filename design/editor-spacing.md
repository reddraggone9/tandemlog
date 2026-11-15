# Editor spacing maintenance UX brief (2026-11-15)

Question: what am I editing, and how do I save or cancel it?
Retain existing title/help, fields, validation and actions in their existing order.
Reuse AlertDialog's centered bounded scroll layout and keyboard handling; add no
new labels, navigation, actions or status icons. The next action remains editing,
then Save or Cancel. Tasks navigation check remains unchanged.

Task/Food modal title and content have physical 16dp horizontal gutters matching
actions even at 200% text. Keep text scaling and vertical adaptive padding.
Use one shared padding widget inside AlertDialog's zero horizontal padding, so
Flutter's title/content padding scaling cannot shrink the gutter. Filled buttons
share a 64x48 minimum with standard density, not a fixed height, and grow for text.
No action semantics, storage, performance budgets or persistence change.
