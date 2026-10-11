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
