# 0037 — Android Food bulk-editor Cancel exits selection

Status: Accepted by Lee, 2026-10-30.

## Context

Native RC107 testing observed that Cancel in the Android Food bulk editor closes the editor and exits selection entirely. Lee confirmed this is correct behavior while accepting RC107 for stable.

## Decision

Keep the implemented behavior: Cancel closes the bulk editor and clears selection. It authors no canonical records. This is not a defect or next-release follow-up.

## Alternatives and consequences

Retaining selection after Cancel was considered as an observation, not an accepted requirement. Exiting selection makes Cancel finish the bulk-edit interaction; starting another bulk edit requires selecting again. No product code changes accompany this clarification.

## Revisit trigger

Revisit only if Lee requests a different cancellation workflow or a future shared selection redesign changes this interaction.
