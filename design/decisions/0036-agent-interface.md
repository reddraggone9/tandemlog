# ADR0036 — Agent interface shipped with the GUI

Status: **Accepted direction** (Lee, 2026-10-28 22:10 CDT). Implemented on
release line `vex/agent-interface-20261029` (2026-10-29), not yet released;
see [section 11](../agent-interface.md#11-implementation-2026-10-29) for
deviations and pending gates.

## Context and decision

Lee accepted separate binaries/logs for agentic access: “I think you've convinced
me. Do what you think is best.” The goal is low-configuration, provider-independent
agent access to the same Tandemlog actions, not another data writer implementation.

Adopt the requirements in [Agent interface](../agent-interface.md): a headless
Dart CLI and stdio MCP adapter sharing domain commands, shipped in the existing
Flatpak, Windows installer and ZIP. Each agent identity owns a separate private
profile, installation and log; no per-machine identity rule or agent-count cap.
Use whole-action Undo only, revisions for every existing-item mutation, mandatory
plan hashes for bulk/merge/import, and generic source keys.

## Alternatives and consequences

A GUI-hosted HTTP API needs a running app/network authorization. A Python writer
duplicates canonical semantics; a headless Flutter mode retains GUI dependencies.
Shared GUI/agent writer state couples append/hash-chain recovery and text actor
ownership. A separate Linux tarball adds an installation/update path. Reject
these alternatives; package both executables together but isolate their state.

Shared workspace extraction, native packaging, read-only opening and durable
whole-action text Undo need feasibility work. Acceptance does not prove current
stores can undo text across process restarts, authorize a canonical format change
or weaken performance/compatibility gates. The [implementation questions](../agent-interface.md#9-settled-requirements-and-implementation-questions)
remain explicit blockers to claiming completion.

## Validation and revisit trigger

Documentation only during Food RC.2 qualification. Implementation starts on its
own release line **after Food products is stable**, with parity, packaged native,
concurrency, restart/Undo and existing performance checks. Revisit on concrete
feasibility evidence; record any needed format/semantic decision before changing
requirements. No implementation, main integration, CI, benchmark, release or
live-data action is authorized by this documentation change.
