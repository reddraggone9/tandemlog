# 0006 — Installation identity and one active app instance

Status: accepted by Lee, 2026-10-03. Implementation is pending final native/CI acceptance; canonical protocol remains v2.

## Reason and behavior

Preferences already belong to the installation. Separate processes editing the same `settings.json.tmp` can race even when they open different workspaces. Acquire the settings-root `profile.lock` **before reading or writing settings**, retain it while startup, commands, preference writes, import and store shutdown can finish, and release its OS handle on shutdown. A second instance shows the reason and contextual Retry; it does not read preferences or open canonical data. Process death releases the OS lease, so an old empty lock file is not a stale lock to delete. A same-process canonical-path guard prevents the second POSIX acquisition that OS process-owned locks would otherwise permit. Different explicitly selected private profiles are separate installations.

Keep one installation writer UUID in `settings.json`, alongside folder/person/theme preferences. Active person is not writer identity. Sequence and observed clock remain **workspace-scoped**, reconstructed from canonical logs. Thus one installation can use sequence 1 in two distinct spaces without a collision: event IDs and references are interpreted within their space. Only one production store is active after a workspace switch finishes; the existing per-space `session.lock` remains defensive. During a switch the old store is retained until the replacement opens and preferences commit, allowing failure rollback under the installation lease.

## Local migration and reset

On the first upgraded settings load, prefer the legacy writer-id for the selected folder's SHA256 cache directory. If it is absent, choose the lexical first legacy cache-directory path, independently of listing order or timestamps. Validate all discovered legacy identities and fail visibly if invalid. Persist the chosen UUID through flushed atomic settings replacement **before** creating `writer-migration.json`, whose complete payload is `{"v":1}` and contains no identity. A crash between the two steps finishes the marker using the already saved UUID. Leave all legacy identity files and canonical streams untouched; other-space streams remain readable, with future commands written to the installation UUID's stream using that space's next sequence.

Deleting only settings after the marker exists creates a new writer on next load. It never resurrects a legacy per-space UUID, and old tasks/history remain readable in a reselected canonical folder. Do not copy settings/writer identities between active installations. Deleting the whole private profile also deletes the marker and integrity checkpoints; this is a fresh installation and a weaker historical rollback-detection baseline. Preserve complete canonical backups before resetting data.

## Alternatives and revisit

Per-space writer files add identity plumbing without solving preference races. An unlocked UUID in preferences would still allow simultaneous writers. A global OS lock without a same-process guard would be insufficient on POSIX. Auto-forwarding a second launch into the first window is deferred; Retry is the bounded initial behavior. Revisit for deliberate multiple windows/processes or a background writer, not hypothetical parallel modules.

SQLite cache 11 replays supported caches 1–9 for the approved Inbox projection using retained canonical files and existing integrity checkpoints. Cache 10 gains range checkpoints in place, without historical reads. Neither operation migrates canonical protocol. Tests cover process contention/crash, aliases, interrupted startup/migration, reset, two spaces, preserved streams and cache replay. Exact native/CI receipts belong in runtime QA and status.
