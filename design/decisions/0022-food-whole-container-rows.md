# Food whole-container rows

Status: accepted by Lee on 2026-10-14; implementation under acceptance. This supersedes the expanded/contents interface in ADR 0019, without changing canonical history.

## Context and decision

Food is managed as physical containers. Remaining contents has no interface: no fractions, unspecified-content labels, conflict resolution, inspection, expansion or edit-count controls. Flat rows show name, physical count when plural, expiration, Brand, retention reason, size and Location. Existing secondary/semantic colors remain. Tap/click or keyboard activation edits the entire observed active/retained group, following Tasks. There is no separate Edit group details menu item.

The existing dedicated minus removes one observed container. In Deleted the same position restores one observed container. The ellipsis occupies the old expansion position: Add another plus Remove N for active groups, Add another plus Restore N for Deleted, using the same observed group quantity. Right-click has identical items. Whole-group removal retains its confirmation and Cancel. Group restoration retains its existing direct behavior. Existing Undo applies to one or many containers through additive records.

Keep group-level Brand/Location selection and filtering. No individual selection, split-group editor or edit-count interface is added. Lee accepts Add another… then Remove one container for the uncommon expiration/splitting case. Add another copies descriptive defaults, leaves expiration blank and retention empty, starts at one, creates fresh IDs on successful Add, and never mutates its template on cancellation.

Rows, gestures and popup state are bound to workspace identity, observed physical IDs and deletion tokens. An open editor retains its captured targets; later arrivals cannot silently join the edit. Child minus/restore/menu controls act independently from row editing. Size/Location remain directly visible rather than disappearing with expansion.

Food's Android shortcut uses the existing Material kitchen_outlined fridge glyph in white on the existing green background with consistent padding. Tasks and the normal app icon remain unchanged. Stable shortcut IDs and existing explicit destination/intent flags remain; Android updateShortcuts refreshes existing pinned copies at startup before dynamic publication. No automatic pinning or permissions are added. Actual launcher upgrade refresh must be qualified by native evidence.

## Alternatives

Retaining inspection or contents controls would keep the unwanted fractional model visible. A split/count editor would add a workflow Lee explicitly declined. Moving Restore one into the menu while keeping Restore all on the row was superseded by Lee's symmetric deletion/restoration instruction. A new image asset style was unnecessary because Food already has a fridge glyph.

## Compatibility and consequences

This is presentation and command targeting only. Do not rewrite, normalize, import or discard existing canonical files. Historical fractions, amounts, conflicts, certainty fields, parsers, stable IDs, hashes, replay, pending protected receipts and generic Retry remain unchanged. New containers continue the existing internal Full default; the interface makes no remaining-content assertion. Retention, searchable suggestions, all-status search, filters and the 50-action Undo stack remain. No new data files, schema, events or preferences are introduced.

## Revisit trigger

Revisit quantity workflows only after a concrete everyday need and new product approval. Revisit launcher refresh for a launcher that demonstrably fails to update an existing pinned copy. Native Android narrow and Linux desktop checks, both themes/enlarged text, gesture independence, one/many Remove/Restore/Undo and byte preservation are acceptance work, not assumed results.
