# Next task parity — review draft

Status: research baseline, 2026-09-30. Implementation was subsequently authorized; [ADR 0003](decisions/0003-task-parity-and-prerelease-boundary.md) records accepted decisions and supersedes earlier proposals below. Actual source/live migration remains unapproved. This document contains no private source task text.

## Goal and current gaps

Match the existing todo workflow before adding a general planner. Current tasks have title, notes, assignee, creation order and operation-targeted completion/reopening. There are no date/time, tag, manual-move or recurrence fields. `LogEvent` accepts exactly protocol v1 and a closed set of payload keys; its encoder always emits v1. Completion events have no real-world timestamp. SQLite v1 caches per-entity projections; order currently comes from creation `(clock, writer)`. These are concrete migration constraints, not just missing editor controls.

The archived product document proposed due-time sorting with one shared manual tie-break order, start/due dates, calendar/completion-based repeats and richer priorities/reminders. Those proposals are not blanket approval for this milestone. Preserve only behavior established by the source and Lee's current decisions; leave notifications, floating priority buffers, calendar views and general natural-language scheduling outside unless the source proves them necessary for parity.

## Source inventory before selecting semantics

The local worker should report sanitized syntax patterns and counts, not task contents: task check states, date fields and time-tag forms, recurrence phrases/intervals, tag case/hierarchy, ordering/group headings, indentation/subtasks, multiline notes, links/comments/block IDs, completed-history representation, encoding/BOM/newline style and unsupported constructs. Include ambiguous or malformed examples with substituted text. Preserve distinctions in syntax; don't silently normalize them while describing the source. Identify the actual Markdown/plugin convention before researching its semantics.

### Received sanitized inventory

The parent reports identical source on both machines: 220 flat task lines (210 open, 10 completed), manually ordered. There are 108 start (`🛫`), 28 scheduled (`⏳`), 112 due (`📅`) and 10 completed (`✅`) date markers. These are separate fields, not alternative spellings of a due date. All 21 `#start-time-HHMM` tags are syntactically valid; two lack a start date. No literal `HH:MM` time was observed. Preserve those two as time-only values; never infer today, scheduled date or due date as their missing start date.

There are 99 recurrence expressions: 76 completion-relative (`when done`) and 23 calendar-relative. Observed families include day/week/month/year intervals, weekdays, weekday lists, month-end, first Friday every three months, and the first of January/April/July/October. The local reader identified Obsidian Tasks 7.20.0 (`obsidian-tasks-plugin`) and supplied 37 exact rule forms; relevant recurrence settings have now been inspected (see below); enabled runtime behavior is not independently verified. Three completed source tasks have recurrence rules. Test America/Chicago DST, leap years and month ends explicitly.

There are 299 tag occurrences across 24 distinct tags, 70 lines containing wikilinks and 24 Markdown links. Preserve tag spelling and link syntax/targets opaquely; do not fetch link targets or assume they are public URLs. Preserve original tag occurrences in migration provenance even if application tag membership is a set. Source order is the initial manual order; automatic due-date sorting must not replace it by default. Completion dates have date precision, not fabricated times or instants.

Inventory is evidence about syntax, not proof of task-plugin semantics. Obtain sanitized examples retaining exact metadata/punctuation (including combinations of start/scheduled/due and recurrence), encoding/newlines and link embedding before finalizing a parser. No private task titles, source hashes or link targets belong in repository fixtures.

Build a mapping table per observed construct: source meaning → app field/behavior → original formatting/provenance → supported/ambiguous/deferred. Any semantic item left only as raw text is preserved but **not functional parity**. Unknown syntax remains a visible blocker to claiming a complete migration.

## Proposed domain decisions — not yet accepted schemas

| Area | Recommended narrow direction | Main edge cases |
| --- | --- | --- |
| Dates/times | Distinguish date-only from a local date/time anchored to an IANA zone. Preserve the observed separate start/scheduled/due fields, plus time-only start values. Treat date, time, zone and DST resolution as one atomic value. | Time tags without dates, traveling users, ambiguous/missing local times, clearing time without losing date, overdue meaning. |
| Tags | Preserve spelling and hierarchy initially. Per-tag add/remove operations should preserve independent offline additions; observed-add removal is a suitable small domain rule. Avoid whole-tag-list LWW. | Case identity, escaping/literal hashes, simultaneous add/remove, reserved time tags, duplicates. |
| Manual order | Prefer explicit relative move commands over array indices or floating-point ranks. Project a shared sequence in deterministic logical-event order; keep a stable fallback for concurrent moves/missing anchors. Benchmark this small-list approach before adopting a sequence CRDT. | Two offline moves of one task or different tasks, filtered/Completed/Everyone views, due-time grouping, moved/completed anchors. |
| Recurrence | Implement only observed rule forms, with explicit anchor mode and versioned rule meaning. Keep series and occurrence identity separate; preserve completed occurrences. | Calendar versus elapsed intervals, completion-based repeats, missed cycles, month end, undo after successor work, concurrent completion and rule edits. |

The verified source is flat and manually ordered, so import line order as the default shared order. The archive's due-sort/manual-tie-break proposal is not the parity default. Moving within a filter must not silently reset hidden tasks. A deterministic replay of relative moves resolves convergence but does not promise every concurrent human ordering intention survives. Do not disguise that policy as real-time recency. Global order needs its own cache projection rather than overloading the existing per-entity creation-order string.

### Date/time policy

Do not encode date-only as midnight UTC or implement calendar days by adding 24-hour durations. Dart explicitly documents that `DateTime.add(Duration(days: ...))` can cross DST with a changed wall time/date: [Dart API](https://api.dart.dev/dart-core/DateTime/add.html). IANA zone rules change over time: [IANA database](https://www.iana.org/time-zones). Use explicit calendar arithmetic and a pinned timezone-data dependency when a library is selected; no package decision is made here.

For entered timed tasks, retain local civil components, zone, selected gap/fold policy and resolved instant together. For generated recurrence occurrences, persist resolved schedule choices in explicit commands so replicas do not silently reinterpret the same occurrence under different timezone data. Preserve unknown source timezone/time precision as unknown until resolved. A floating local schedule is a separate meaning, not an accidental device-local default.

Proposed policies for Lee to confirm only if relevant to the source: preserve household wall time; choose an explicit gap/fold policy; choose clamp versus skip for invalid month dates; decide whether missed occurrences accumulate or advance to the next useful date. RFC 5545 supplies a recurrence vocabulary, but its invalid-date/nonexistent-time rules must not be assumed to match a task plugin: [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545#section-3.3.10). No reminders/notification permissions are implied by adding due times.

### Obsidian Tasks 7.20.0 recurrence compatibility proposal

Research baseline: official tag `7.20.0`, commit `69d6bf8f29fc34877bcfeef45db7163bf72a7303`. Read the versioned [recurrence guide](https://github.com/obsidian-tasks-group/obsidian-tasks/blob/7.20.0/docs/Getting%20Started/Recurring%20Tasks.md), [Recurrence implementation](https://github.com/obsidian-tasks-group/obsidian-tasks/blob/7.20.0/src/Task/Recurrence.ts), [Occurrence implementation](https://github.com/obsidian-tasks-group/obsidian-tasks/blob/7.20.0/src/Task/Occurrence.ts), [recurrence tests](https://github.com/obsidian-tasks-group/obsidian-tasks/blob/7.20.0/tests/Task/Recurrence.test.ts) and [task transition tests](https://github.com/obsidian-tasks-group/obsidian-tasks/blob/7.20.0/tests/Task/Task.test.ts). These were inspected, not executed. The authorized local reader subsequently verified `removeScheduledDateOnRecurrence=true` and `recurrenceOnNextLine=false`; actual plugin runtime behavior remains untested here.

Recommended parity rules:

- Pick the reference date by **due > scheduled > start**, not by whichever date is earliest. Missing fields stay absent. Derive one successor reference date, then preserve each other field's signed calendar-day offset from the original reference. Do not advance each field independently by a month, and do not shift the historical completion date into the successor. `Occurrence` uses rounded day offsets to account for DST; implement date arithmetic explicitly rather than elapsed 24-hour durations.
- Without `when done`, find the next occurrence after the old reference day. Late completion advances once; do not automatically skip to today or generate every missed occurrence. With `when done`, reset recurrence calculation to the completion day and find the next matching date strictly after that day. A weekday/month-day rule can match later in that same week/month; “when done” does not invariably mean wait one full period. Completion means the day supplied when completing, not an old imported completion marker.
- Plain monthly/yearly intervals clamp missing target dates backward to a valid date, and later occurrences inherit that resulting day: a monthly January 31 can become February 28 then March 28. Explicit `on the last` retains true month-end. Preserve ordinal-weekday, weekday-list and named-month constraints; quarterly intervals are anchored to the reference/completion month and are not synonymous with fixed January/April/July/October. Upstream tests cover monthly clamping, leap-day yearly clamping, named weekdays and all-three-date shifting.
- The default retains scheduled dates; `removeScheduledDateOnRecurrence=true` removes them only when start or due also exists. A scheduled-only task retains its scheduled date. `recurrenceOnNextLine` controls successor placement; the default puts it before the completed row. The verified local settings are removal **enabled** and placement **before** the completed row. Match those choices: the 26 recurring start+scheduled+due tasks lose scheduled on the successor, while preserving shifted start/due. Preserve scheduled on imported original occurrences. No new settings UI is required for parity. Custom status definitions exist, but the source uses only open/completed; additional status types are outside the observed scope.
- Preserve the three already-completed repeating rows as history on import, without generating successors or guessing series links from matching text. Upstream stores separate task lines rather than durable series identity. A new Tandemlog completion may create one successor; importing/replaying a completed row must not.
- The source's time tags are outside these date-only recurrence rules. Preserve their spelling. Subject to Lee confirming meaning, carry the start wall-time independently through date recurrence in America/Chicago; do not infer start dates for the two due+done rows with undated time tags. DST gap/fold resolution for an actual timed instant is a Tandemlog decision, not behavior demonstrated by this plugin's date-only scheduler.

Synthetic acceptance examples with the verified scheduled-removal setting (proposed expected results from the documented rules, not executed parity tests):

| Input | Expected successor |
| --- | --- |
| Start Oct 1, scheduled Oct 2, due Oct 3, 2026; `every week`; complete Oct 20 | Start Oct 8, no scheduled date, due Oct 10, still overdue. |
| Same dates; `every week when done`; complete Oct 20 | Due Oct 27; start Oct 25, no scheduled date. |
| Due Jul 31, 2026; `every 3 months on the last` | Due Oct 31, 2026. |
| Jan 31, 2026; `every month` | Feb 28, then Mar 28. |
| Jan 31, 2026; `every month on the last` | Feb 28, then Mar 31. |
| Feb 29, 2024; `every year` | Feb 28, 2025. |

For off-pattern references (such as due October 3 with `every 3 months on the last`), do not assume that the first successor waits three full months. During implementation, evaluate all 37 observed expressions against the pinned upstream implementation with explicit completion dates, including reference dates not themselves on the rule, then create independently asserted Dart fixtures. This is a small compatibility oracle, not permission to embed the upstream plugin or run private data through it.

Observed rule inventory for sanitized fixtures:

- With `when done`: `every day`, `every 2 days`, `every 5 days`, `every 9 days`, `every 20 days`, `every 25 days`; `every week`, `every 2 weeks`, `every 3 weeks`, `every 4 weeks`, `every 6 weeks`, `every 7 weeks`, `every 8 weeks`, `every 13 weeks`, `every 26 weeks`; `every month`, `every 3 months`, `every 4 months`, `every 6 months`; `every year`, `every 5 years`; `every weekday`; `every week on Monday`, `every week on Friday`, `every week on Saturday`, `every week on Wednesday, Sunday`, `every week on Monday, Tuesday, Wednesday, Thursday, Friday, Saturday`; `every month on the last`.
- Without suffix: `every day`, `every 36 days`, `every week`, `every week on Monday`, `every month on the last`, `every 3 months on the 1st Friday`, `every 3 months on the last`, `every January, April, July and October on the 1st`, `every year`.

The date-field combinations reported by the local reader are: start+due 75; start+due+done 5; start+scheduled+due 26; scheduled+due 1; start-only 2; scheduled-only 1; due-only 1; due+done 4; done-only 1; no dates 104. The verified recurrence subset is 72 start+due, 26 start+scheduled+due and 1 start-only: all 99 have a reference date. Undated recurrence need not be implemented for source parity.

### Recurrence is the main correctness risk

Do not implement repeat by overwriting one task's due date and clearing its completed flag. That loses history and can double-advance when two offline devices complete the same occurrence. Use stable occurrence IDs, rule revision IDs and explicit completion instants/zone context for new events; old v1 completions remain undated unless the source provides actual evidence.

One completion command must atomically express its completion and proposed successor schedule, or an equivalent single durable logical event. Replay may derive projections but must never append successor events. Competing completions of one occurrence must converge on one successor identity and a documented deterministic anchor; two clients must not independently create conflicting `task.created` records for that successor. The exact event shape follows the observed recurrence subset, not this sketch.

Define undo/reopen before coding: retracting a completion must not delete or orphan notes/completions already attached to its successor. Candidate behavior is to undo unacted-on advancement, while preserving an already-used successor; whether that meets Lee's workflow needs confirmation. Also settle schedule editing scope and “finish permanently” only if used. Keep these acceptance examples small and explicit.

## Approved prerelease identity and compatibility boundary

Lee approved `com.reddraggone9.tandemlog` as the application identifier for the next coherent candidate. Do not publish a standalone rename while setup/planning remains in progress. Inventory platform identifiers before implementation: Android application ID/namespace, desktop identity/resource metadata and the resulting support-directory paths are related but not interchangeable. Document the actual changed package and paths in candidate release notes; Android package identity changes mean a separate installation, not an in-place update of rc2.

Lee considers pre-0.1.0 installations disposable. The durable versioned compatibility promise starts at stable 0.1.0. Avoid building elaborate automatic migrations or compatibility bridges solely between these prereleases. Retain the existing permanent owner signing key; changing application identity does not justify replacing or exposing it.

Disposable installations do **not** authorize deletion of source Markdown, canonical task folders, backups or other user data. Old/unknown protocols must fail explicitly rather than be partially read or silently discarded. Never silently relocate a chosen folder. Release notes must identify intentional breaks and the supported fresh-setup/import path before a user installs the candidate.

## Compatibility and rollout proposal

1. Choose a deliberate new protocol/schema for the parity candidate, with explicit version checks. We may require a fresh workspace instead of supporting rc2 history; that is acceptable under the prerelease policy, but must be stated before cutover. Never rewrite or delete existing canonical history to make it fit.
2. Reject unsupported manifests/events visibly on both read and write. Do not mix old and new writers in one workspace. A stale offline rc2 can still write its old folder; using a separate new destination avoids pretending that an offline compatibility barrier exists.
3. Preserve the useful semantics of operation-targeted completion/undo in the new design. Existing v1 completions have no timestamp; if an explicit import is offered, do not fabricate completion instants. Markdown completion dates retain their actual date-only precision.
4. Version private SQLite projections and test rebuild/restart/interruption behavior for the new candidate. Keep incremental warm startup. Preserve private writer identities for any workspace that remains in use; fresh installations/spaces may allocate new identities.
5. Test old-format refusal, invalid/unknown records, deterministic replay, cache recovery and fresh-space import. If rc2 import is explicitly added, test its mapping rather than assuming backward compatibility. Keep untouched source and canonical backups; reverting to rc2 means reopening its compatible original folder, not feeding it the new protocol.
6. Before stable 0.1.0, establish historical fixtures and a documented upgrade/recovery contract. After that boundary, persisted format/meaning changes require supported versioned migration behavior. Keep the repository's existing integrity and no-silent-loss rules throughout prereleases.

## External one-time migration and round trip

The importer is a separate CLI/tool, not an app feature. It must use the same versioned validation/domain meaning as the app, not a second ad hoc event specification. Start with a dry run into a **new private staging destination**; never modify the source or live store during exploration.

- Read a stable source snapshot, record its byte hash, encoding/newlines and parser/mapping version, and detect source changes before final acceptance.
- Assign a dedicated import writer, contiguous sequence and logical clocks. Persist a run manifest with stable entity IDs/record mapping so retries of the same run are idempotent, including duplicate task text. Never reuse the live app writer or allocate identity from task text alone. A deliberate second import must be distinguished from retry.
- Fresh-space rehearsal is simplest. A later merge into an existing space needs explicit destination/user mapping, observed maximum logical clock, an offline import-session identity and duplicate-import checks. Write no partial visible batch while building it. Folder/provider publication and recovery must be tested; do not assume Android atomic rename from desktop behavior.
- Verify domain replay into an empty cache: counts/check states, title/notes, dates/times/zones, ordinary versus reserved tags, recurrence, relative order and links. Unmapped fields are reported, not dropped or truncated to current field limits.
- Export the imported canonical model back to Markdown and compare both semantic fields and original bytes. Byte-perfect source restoration alone can hide a broken importer if the exporter merely returns a stored original file; semantic verification must independently read the emitted domain events/projection.

Lossless Markdown generally needs formatting/non-task provenance beyond task fields. Preferred initial plan: a **private migration bundle** with domain JSONL and a lossless source-map/provenance JSONL sidecar, outside the live sync folder. It can retain headings/comments/whitespace/line endings and source spans without adding an archival-data module to the app. Do not put an unrecognized sidecar `.jsonl` inside the live folder: today's scanner expects canonical writer logs. Keep a byte-identical untouched source backup separately.

This has an explicit limitation: exact reconstruction is from **JSONL plus provenance**, not necessarily domain logs alone. If Lee requires reconstruction from the app's canonical logs alone, preservation metadata must become a recognized versioned canonical format (with size/privacy limits) before import; do not call a hidden sidecar a JSONL-only guarantee. Original source content/provenance may contain material beyond tasks and must not be copied to a shared household space by default. An unchanged import must round-trip exactly; formatting/export behavior after later app edits is a separate scope to define.

After dry-run app parity and both comparisons pass, present the concrete destination and mapping for approval. Keep source/live data untouched until that final migration step. Private real fixtures, reports and source hashes stay off the public repository; commit only sanitized equivalents.

## Ordered delivery proposal after authorization

1. Sanitized source inventory and a small parity/ambiguity matrix; answer only the decisions actually needed.
2. Explicit protocol/version and cache foundations (without unnecessary rc-to-rc migration machinery), approved application identifier, plus date/time and tag domain tests, then a compact editor/list presentation. Native desktop/Android QA preserves current capture/notes density and keyboard flows.
3. Shared manual ordering with deterministic concurrent-move fixtures and touch/keyboard interaction checks.
4. Observed repeat forms with occurrence/completion/undo conflict tests and DST/month/missed-cycle fixtures. This is the highest-risk segment; do not promise safe same-day parity before seeing the actual rules.
5. External dry-run importer/exporter, isolated replay and semantic/byte round trips; then a candidate the user can compare against the old workflow before destination approval and cutover.

If a source convention changes this ordering, revise the plan rather than forcing it into these assumptions. Broader planner features stay deferred.

## Remaining narrow questions after inventory

1. Confirm with Lee: does `#start-time-HHMM` mean the task's start/availability time in America/Chicago (not due time), and do the two undated times intentionally remain time-only? Preserve the reserved tag verbatim for round-trip regardless of UI representation.
2. Resolved by local inspection: scheduled removal is enabled, successors precede completed rows, and all 99 repeats have reference dates. Match these behaviors without asking Lee to reconfirm existing configuration. Imported source statuses are only open/completed.
3. Confirm with Lee when defining repeat interactions: if a completed occurrence is reopened after its successor has been edited/completed, should both remain? Recommend preserving both rather than deleting successor work; distinguish transient Undo from deliberate historical reopening.
4. Confirm migration acceptance: is a private JSONL migration bundle with provenance acceptable for byte-exact round-trip, or must canonical app logs alone reproduce the original bytes? Domain parity is checked independently either way.

No manual-sort question is needed now: preserve verified source order. Implementation is now authorized; actual source migration remains pending. Sanitized templates may resolve most recurrence choices; avoid asking Lee to design a general recurrence engine.
