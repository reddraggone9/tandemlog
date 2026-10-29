# Food field editing and Full defaults

Status: accepted by Lee for the next experimental preview on 2026-10-11;
implementation and exact native acceptance are tracked in
[status](../status.md). No live-data replacement is authorized in the cloud.

## Context and decision

Brand and Location are optional free text whose existing values can help entry
and selection. Use one lightweight autocomplete for Add and Edit, including
values from Deleted, without a catalog or forced values. Reuse the shared tag
selection control for multiple-value filters: OR within each field, AND between
fields. Empty means any. Inclusive Food search pauses these saved filters too.

Lee approved filtering, selecting matching active physical containers and bulk
editing only Brand/Location. Capture exact IDs; exclude hidden/deleted rows and
later arrivals. Allow partial selection and show an explicit selected count.
(Superseded 2026-10-29 by Lee: Food selection is row-level and includes later
arrivals in a selected row; there is no partial selection. See
[batch selection](../batch-selection.md#row-level-food-selection-lee-2026-10-29).)
Each field has Apply and Clear controls, so mixed values remain unchanged unless
chosen. Reuse the existing host command, batched append and one Undo receipt.
Cancel/no-op writes nothing; changed selection/workspace guards reject stale
draft targets. No dates, names, sizes, retention or contents are edited in bulk.

Keep inline Inspect and the existing lower overflow location. Remove duplicate
container counts and opaque visible ID prefixes, retain remaining contents and
distinct accessible per-container actions, and reduce separator spacing without
shrinking targets. Moving overflow into a third header slot and replacing inline
expansion with a details view are deferred at Lee's direction.

Lee explicitly removed the RC-only Unspecified contents state. New/imported
containers default Full (1/1), independently of optional nominal size. Existing
numeric partial fractions and measured amounts retain their exact meaning.
All-null contents fail decoding; never normalize signed record or import-plan
bytes. Keep obsolete fixtures frozen as rejection evidence and add a separate
independently generated Full-default vector.

## Additional accepted workflows

Lee approved trying one shared centered 1450px content limit for standalone
Tasks and Food, with the existing padding. Keep the existing one-level Task
editor layout: a 420px side panel at its current breakpoint and modal editing
below it. Opening that panel does not widen the outer frame.

Desktop secondary click anywhere on a Food group opens the same menu as its
lower expanded ellipsis. Both use one item builder and action handler. Keep
primary clicks, selection, inline Inspect and 48px targets. No mobile long-press
workflow is introduced. Active and retained groups offer Add another…, Edit and
Remove; deleted groups offer only Add another… alongside their existing Restore
control. Stale workspace/member observations cannot act on a different group.

Lee approved the label Add another… and a prefilled Add draft: copy name, Brand,
nominal container size and Location; clear expiration and retention; focus the
empty expiration; start with count 1. Reuse the normal editor, suggestions,
calendar, validation and Add command. Opening, Cancel/Back and invalid submission
write nothing. Valid Add creates independent fresh physical identity and Full
contents, without copying deletion, partial contents, certainty, import identity,
observed edits or history. A deleted source remains deleted; this is a new
purchase, not Restore. The existing session Undo reverses the new Add alone.

Folder selection is user choice rather than running work. Keep a separate
picker guard to prevent duplicate dialogs while allowing normal app actions;
show work progress only after a different folder is selected for validation and
loading. Recheck the active owner/workspace and intervening drafts before the
switch. Cancel/same-folder and draft veto preserve the active workspace; failed
validation/settings persistence rolls it back. Android launch failure clears its
native picker guard so retry remains possible.

Retained is one flat expiration-sorted list, with the retention reason on each
row. Its reason input and autocomplete filter items directly. Keep physical
container grouping and Inspect expansion when all displayed details, including
the reason, match; different reasons remain separate groups. Search still
bypasses saved filters and includes its existing Deleted section.

## Alternatives and consequences

A catalog would add entities and lifecycle rules to a free-text feature.
Implicitly applying a blank mixed value would clear fields unexpectedly. A
wildcard update could include arrivals the user never selected. Those approaches
are rejected in favor of exact observed IDs and explicit field choices.

Preserving the development-only unspecified state through a migration would add
compatibility Lee does not need. A throwaway trial with any old all-null history
or protected receipt needs a fresh separate path, workspace/profile identity and
immutable import plan coordinated locally. The old files, receipt bindings and
established Tasks persistence remain intact. This is not an in-place cache reset.

## Revisit

Revisit selection discovery and expanded-row density after native use. A details
view remains a product decision. Exact replacement-APK acceptance and independent
source/media review are required before publication.
