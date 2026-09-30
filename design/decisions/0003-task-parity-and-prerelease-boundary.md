# Task parity, temporal meaning and prerelease compatibility

Status: implementation authorized 2026-09-30; candidate acceptance pending.

## Goal and scope

Replace Lee's current Markdown task workflow with separate start/scheduled/due dates with optional times, tags, shared manual order and the 37 observed recurrence forms. Preserve the compact capture/list experience. Games, nutrition, notifications and a general planner remain outside this milestone. The source and live data remain untouched until an explicit validated migration destination is approved.

Source behavior is Obsidian Tasks 7.20.0, with scheduled-date removal on recurrence enabled and successor-before-completed ordering. Match due > scheduled > start reference selection, calendar-day offsets, completion-relative versus original-date recurrence and monthly/yearly clamping. The pure Dart algorithm is independently implemented; upstream MIT-licensed source is an external test oracle, not embedded app code. Tests include all 37 observed forms, off-pattern references, month end, leap day and DST dates. See [planning evidence](../next-task-parity-draft.md) and [schema](../schema.md).

## Time semantics

Lee explicitly approved both floating local time and named-zone time from the start. Date-only values remain dates. Each optional time requires its corresponding date. Lee corrected the two earlier source anomalies; they do not justify an independent time-only feature. The task schedule has one shared zone for start, scheduled and due fields; this avoids contradictory per-field calendars while supporting the approved local/pinned distinction. A null zone means floating local wall time, following the device's local calendar; a named IANA zone, including UTC, pins the wall time to that zone. Existing Markdown time tags import as floating. Reject a missing required date rather than invent one, and never silently convert existing task metadata when traveling. Start must not follow due; date-only due means the end of that day in the same schedule zone/local calendar. Validate the coupled schedule atomically on commands, replay and recurrence; source anomalies are reported for correction.

Precision records intent, not a restriction of the UI: the interface could hide default times, and floating datetimes also handle travel. Keeping an omitted time distinct from explicit midnight preserves source/export fidelity and leaves future reminder behavior unambiguous. Otherwise defaults would need a separate precision flag. Derive comparison bounds rather than store a fabricated 23:59:59.999. A date-only due bound is the exclusive beginning of the following day; a precise start at that boundary is invalid. An exact due-time bound is inclusive for start ≤ due.

The date/time editor defaults to Local, with one optional zone choice for these task dates, not a global preference. For pinned wall times, a DST gap moves forward by the gap and an ambiguous fold uses the earlier instant. Preserve original civil values and zone. Use calendar recurrence, not 24-hour durations; record the completion day used by a command so replay never consults the current clock. Timezone data is bundled through pinned BSD-2-Clause `timezone` 0.11.1; no online lookup or notification service is needed. [Package documentation](https://pub.dev/packages/timezone).

## Recurring history and concurrency

A completion and its successor proposal are one durable event. Replays never append events. Concurrent completions converge on one stable successor identity. Reopening history preserves the already-created successor and its work; recompleting the predecessor must not duplicate it. This also applies to immediate Undo in this candidate and must be stated in the UI/notes. Cancelling a future occurrence is a separate future command, not an accidental effect of historical reopening.

Tags retain spelling and use observed-add removal so offline additions survive. Manual moves are relative to a task anchor in a shared order, not a whole-list replacement or floating-point rank. Filtering must not silently reorder hidden tasks.

## Event ordering correction

The first slice replaced the [original wall-clock/causal hybrid](https://github.com/reddraggone9/tandemlog/blob/1be49b4/design/storage-and-sync.md#L35-L39) with a pure Lamport counter. That preserved convergence but lost the intended approximate recency of independent offline edits: an old edit at counter 10,000 could defeat yesterday’s edit at counter 50. Lee requested correction before expanding the protocol.

Lee explicitly chose the original algorithm: `max(now_ns, highest_seen_clock + 1)`. Protocol v2 serializes this scalar as a canonical decimal string, decoded exactly with BigInt, within the original signed 64-bit range. Dart supplies wall time at microsecond precision, converted to nanosecond units before applying logical increments; nanosecond units do not claim nanosecond physical accuracy. Writer/sequence remain event identity, and clock/writer/sequence provide deterministic order. Imported timestamps remain immutable; task schedule dates are unrelated metadata.

When observed time is materially ahead of the device clock (five minutes for the diagnostic), warn but continue local writes using the observed maximum. This follows the original availability tradeoff: a bad future clock can propagate into subsequent events, and correcting the system clock alone does not fix canonical history. A slow receiver can cause the same warning. No clamping, restamping, admission rejection or automatic repair is performed.

The proposed HLC pair would separate physical time from burst counters; Lee preferred the original scalar approach. Exact string serialization addresses JSON/JavaScript integer precision without changing that algorithm. Old numeric counters and the unpublished tuple draft fail explicitly rather than being reinterpreted as epoch timestamps. Tests preserve stale-offline, causality, backward-clock, equal-time, future propagation/warning and immutable-replay coverage.

Coordinated history repair is deferred maintenance design, not implemented. A possible future operation would close all clients, preserve backups, rewrite deliberately and force cache rebuilds; stale offline logs and generation identity require an explicit reviewed design. This task never rewrites actual history.

## Source completion actions

The private rehearsal exposed `🏁 delete` metadata omitted from the initial source inventory. Obsidian Tasks removes the completed occurrence while retaining its successor; this is independent of the recurrence expression. Lee explicitly chose **retained completed history for every Tandemlog task**: the source flag only managed Markdown clutter. Parse the flag only to report the intentional behavior adaptation; do not persist it or its formatting in app events, and never implement app deletion from that flag.

For canonical Markdown export, Lee authorized `🏁 delete` on every open recurring row. Generate it from current completion/recurrence state, without a stored source flag. Completed recurring rows remain historical and do not spawn successors during import. Unknown input completion actions remain explicit errors. [Source semantics](https://github.com/obsidian-tasks-group/obsidian-tasks/blob/7.20.0/docs/Getting%20Started/On%20Completion.md).

## Application identity and compatibility

Use `com.reddraggone9.tandemlog` for the next candidate. Android's package changes, Linux's application identity changes, and Windows's company metadata becomes `com.reddraggone9`; these affect fresh settings locations and installation identity. Retain the existing owner signing key. Public prerelease notes must disclose the separate installation and protocol break.

Lee considers prereleases disposable; the durable versioned compatibility promise starts at stable 0.1.0. Protocol v2 uses an explicitly new workspace. Do not silently accept old protocol data, migrate folders in place, delete history, or reset an existing chosen workspace. Existing sources/canonical folders remain backups, regardless of installation disposability. Avoid elaborate rc-to-rc compatibility machinery that would delay real workflow parity.

## Migration and acceptance

The one-time migration tool lives in a private standalone rehearsal package outside this repository. Its migration-only tests and formatting policy are not maintained by app CI or shipped in release assets. It uses a dedicated writer and fresh private staging folder, pinned to actual application APIs. Generic domain/persistence regressions remain in the app. Lee rejected the initial source-map approach: canonical events must contain only functional task data and ordinary event metadata, never original formatting, duplicate source snapshots or import-only references. The canonical Markdown serializer operates on current projected domain values and manual order. Reparse its output and independently compare semantic fields; byte equality is useful only once the owner has deliberately reformatted the source to the deterministic serializer. The old private source-map rehearsal is superseded and is not a live migration. Publish only synthetic fixtures; actual private source stays with the authorized local worker. Destination approval follows a fresh data-only dry run and review of the private formatting diff and any unsupported semantic fields. Cosmetic source fidelity is not a reason to retain unusable source material forever in synced history.

Candidate gates remain full integrity/convergence tests, native Linux task-based UX, signed multi-platform builds and exact-artifact Android validation via Leela/Farnsworth. Cloud raw SSH is unavailable in the tested environment; no network bypass is part of this work. Stable release requires Lee's acceptance and broader platform gates.


## Renderer semantics correction

The initial migration audit covered Markdown task fields and recurrence but missed behavior in the adjacent renderer. Owner feedback identified functional `due-min`/`due-max` tags and start-time visibility. They become typed optional sorting-bound fields with editor controls, not opaque labels or migration metadata. Scheduled-first ordering, local date groups, start availability and manual tie order preserve the actual workflow. Bounds never overwrite stored schedule dates. The earlier successful source round trip is not proof of full renderer parity.

Precise times extend the source's date-only effective dates by retaining time within a clamped civil day; pinned instants render in the viewer's local zone. This keeps bounds about sorting days without silently changing exact deadlines. Invalid bound combinations fail atomically. Clock-driven derived views must refresh without storage mutations. Release stays blocked until the revised private renderer comparison/formatting diff and native desktop/Android checks and demos pass.
