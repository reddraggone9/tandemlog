# Frozen synthetic receipt claim fixture

`concurrent-receipt.operations` was frozen on 2026-10-28 while repairing the
independent Food RC review. SHA-256:
`9e66d5611bfd905e7b6f8f9cbdfe8ea6718098ca127efa509ef7f9d0aa438cff`.

Six canonical Food effect records: each of two synthetic installation writers
records the same one-unit source purchase, claims the same deterministic receipt
container with a different creation instant, then edits using its own original
birth basis. These are Food effects, not standalone unified physical log files.

The test pins exact bytes, verifies both original mutation bases, replay/delivery
order equality and incremental fallback, rejects ordinary/arbitrary-ID/different
receipt-value duplicate births, and checks selective claim Undo. Existing released
Food/current-operation/Undo fixtures are unchanged. Do not regenerate these bytes
to accommodate a future reader; add a separately attributed fixture instead.
