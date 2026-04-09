# Data Model

This document is for application data and event definitions.

## Scope

Describe:

- entities and their invariants
- event types and payload shapes
- relationships between entities
- deletion, restore, and undo semantics at the data-model level
- rules for extending the schema over time

Payload shapes should not change in place. If the meaning or structure of an event changes, define a new event type instead. If an install encounters an unknown event type in a canonical log, it should prompt for an app update and refuse to fully initialize.

## Event Schema (Draft)

### Tasks

```
task_created         { id, title, description?, due_date?, recurrence?, assigned_to[]?, created_by, tags[]? }
task_field_changed   { task_id, field, old_value, new_value }
task_assigned        { task_id, assigned_to[] }
task_completed       { task_id, completed_by }
task_uncompleted     { task_id }
task_deleted         { task_id }
task_snoozed         { task_id, until }
```

### Time Logs

```
time_log_started     { id, category, task_id?, note? }
time_log_stopped     { log_id }
time_log_edited      { log_id, field, old_value, new_value }
time_log_deleted     { log_id }
```

Categories for time logs are currently an open list, probably user-defined.
