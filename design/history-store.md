# Local history store and fast start

Status: accepted direction (Lee, 2026-11-05); released in 2026.11.1-rc.1 (build 115), stable 2026.11.1 (build 116).

## Lee's decisions

These are Lee's. Changing them needs his approval.

- **Startup (Lee 11-05):** a warm start trusts the sealed state. Per writer: the file size is at least the sealed offset, and the hash of the last record at that offset matches. Then only the records after the offset are read, validated and applied. No periodic or background full audits ("not worth the cost"). A strict full open happens only when there is no valid seal or the fast check fails, and then the store is rebuilt from the logs.
- **Lists during catch-up (Lee 11-05):** lists are usable immediately from the stored state while new records are applied, edits included. That is no different from editing before another device's offline or in-flight changes arrive. Other writers' new records merge under the existing rules; this device's own writes append after its own sealed head. A first open with no store loads strictly first.
- **History store (Lee 11-05 11:04):** the local SQLite database holds the whole decoded history as persistent rows, so the app never has to parse the full logs again (for example to replay after an older event syncs in). It is not an optional, size-capped cache. It is appended incrementally, with a per-writer sealed offset and last-record hash, and rebuilt from the logs only when the fast check fails or the store's schema generation changes.
- **Release scope (Lee 11-05 10:38):** this ships in the next release; startup time is its main goal. Moving the open off the UI isolate (only keeps the spinner animating) waits for the release after.
- **Local state (Lee, earlier):** one local SQLite database, no downgrade path, no permanent legacy backups. A rebuild from the logs is acceptable.

These supersede the earlier [storage](storage-and-sync.md) rule that every startup re-reads and re-verifies all canonical bytes. The store replaces the decoded-history blob (`UnifiedDecodedCache` in `profile_metadata`), which was rewritten whole at each seal and fully re-verified (SHA-256 plus JSON of every record) on every start.

## Store layout

Per workspace location, in the profile database (the same precedent as the per-location `tasks_<key>_*` projection tables), with `<key>` = SHA-256 of the folder location:

- `history_<key>_records(writer, seq, start_offset, length, hash, raw, typed)`: one row per complete, chain-validated record. `start_offset`/`length` are its byte range in the writer file (without the LF), `hash` its chain hash, `raw` the canonical record text, `typed` the pre-decoded Task/Food fields.
- `history_<key>_seals(writer, sequence, end_offset, hash, last_start)`: per writer, the number of stored records, the offset just after the last one's LF, its hash and its start. Writers with no records have a sequence-0 seal, like their `protected_app_heads` row.
- `profile_metadata['app5.store.<key>']`: the binding: store generation, typed layout, space, epoch, manifest digest, installation writer and native-text flag.

Both tables must have exactly their frozen `CREATE` statements, or the store counts as absent. The profile schema version stays 6: `_verifyOwnedSchema` checks only the four core tables, and the old-profile reset drops every table, these included.

Rows are written inside the same SQL transaction that advances `protected_app_heads`. There are exactly two: the admission commit (`_refreshObserved`, for peer, catch-up and strict-open records) and the own-action confirmation (`_confirmPreparedAction`). So the store always equals the protected heads. There is no separate seal step, no whole-blob rewrite, and no size cap beyond the existing per-file (32 MiB) and per-workspace (256 MiB) log limits. If a store write fails, the store is dropped inside that transaction; admission itself is unaffected and the next open is strict.

## Open

1. Manifest, protected inventory, location binding and directory listing are checked exactly as before. Sync-conflict, legacy and unknown files still refuse the open, and a changed manifest or epoch at a bound location still refuses it.
2. **Store usable** only if the binding matches and the set of seals equals the set of `protected_app_heads` rows for the space and epoch, each with the same sequence, hash and end offset.
3. **Fast check**, per writer with stored records: the file is listed, is a regular file (local folders), is at least `end` bytes long when the provider reports a size, and the bytes read from `last_start` begin with exactly the stored last record followed by LF. One bounded seek read from `last_start` to the end of the file. A provider that cannot seek takes the strict path.
4. **Pass:** each writer's records come from its rows, decoded in parallel short-lived isolates without SHA-256 or JSON re-validation of the record envelope, and without a chain walk. The physical prefix is rebuilt from the stored canonical text (exactly `end` bytes). The existing admission then runs over the whole set: semantic validation, publication, pending effects (records beyond `published` stay invisible), Food admission and the Task projection proof, so visibility is computed by the same code as a strict open.
5. **This device's own file**, and any writer with no stored records (a newly joined peer, or this device before its header was confirmed), is read and verified in full during the open. So the open never auto-joins on a stale view of the own log.
6. **Catch-up:** the app opens with peer catch-up deferred. A peer's bytes after its seal are not read during the open; the lists show the stored state, and the first refresh after the first list frame applies them through the normal incremental path (read from the seal, chain-checked from the sealed head, semantically validated as a delta against the open's key). Any edit refreshes first on the same profile queue, so it waits for catch-up and then appends after the own head. If catch-up finds invalid bytes or exceeds a limit, the result is the same as a failed in-session refresh today: the safety error is shown, writes are refused, and the stored lists stay visible. Other callers (agent CLI, tests) catch up inside the open.
7. **Fail or no store:** strict full open (every byte read, decoded and verified), then the store is rebuilt from that result in the commit transaction.

Forced full audits (Settings → Verify Logs, `refresh(forceFullAudit: true)`) ignore the store, re-read every byte, and rewrite the rows of every writer they re-read. So Verify Logs also repairs a damaged store.

## Task projection proof

The Task projection witness (`app5.task.cache.<key>`) is still sealed at pause/close and consumed on open, but it no longer carries a digest of the projection rows. Instead, SQLite triggers on the nine sealed projection tables delete the witness in the same statement as any row change (for the metadata table, only its two sealed keys). A witness present at open therefore proves the rows are unchanged since the seal, and the open checks the event/row bijection and canonical revision but does not re-hash the projection (Lee 11-05: no full re-verification at start). The open requires all 27 triggers to exist; an older witness generation takes the strict path once.

At startup, witness-guarded projection rows are read in pages of 512 between cooperative pauses. The restore is trusted only if the witness remains unchanged after the last page, then consumed. A change falls back to strict replay. Both strict replay and warm restore use a 4 ms cooperative validator budget; the private scratch transaction is discarded if validation is interrupted. Shared profile commits remain atomic and synchronous.

## What each check catches and misses

| Check | Catches | Misses |
|---|---|---|
| Binding (generation, layout, space, epoch, manifest, writer, native flag) | A different installation identity, a decoder or layout change between app versions (generation bump), a store left from a different workspace | Nothing about file contents. A changed manifest or epoch at a bound location already refuses the open before this |
| Seals equal `protected_app_heads` (same writers both ways, same sequence, hash, end) | A store left behind while an older app version kept admitting; a store whose transaction was lost | Rows edited consistently with both tables (not a malicious-rewrite defence) |
| `size >= end` | Truncation below the sealed offset; a shorter replacement | A same-length or longer replacement |
| Exact last-record bytes at `[last_start, end)` | Replacement or rewrite that changes the last sealed record; any length change earlier in the file (the record no longer sits at that offset) | A same-length change strictly inside the prefix that leaves the last record byte-identical (bit rot, a hand edit keeping its length). Lee accepted this; Verify Logs and any strict open read every byte |
| Stored row contents other than the last record | — | Damage to other `raw` or `typed` values inside the store (SQLite page damage, a bug). They are served as stored until Verify Logs rewrites them or a generation bump rebuilds the store |
| Directory listing (every open) | Sync-conflict copies, unknown or legacy files, a missing expected writer file; symlinks and non-regular files on local folders | — |
| Catch-up and own-file validation | Everything for new bytes: UTF-8, canonical JSON, record hash, chain continuity from the sealed head, sequence/clock order, semantic rules | — |
| Task witness triggers | Any change to a sealed projection row after the seal, including unsaved text intent | Changes made with triggers disabled or by another program |

## Consequences

- An older app can still open the profile (schema 6). If it keeps admitting, its heads move past the store seals and the next open of this version is strict and rebuilds the store.
- Bump `HistoryStore.generation` whenever record decoding, the typed layout or admission rules change so that stored rows are no longer equivalent to a strict decode.
- **Background owner for long profile SQL (Lee 11-13, 60 fps).** `LocalProfileDatabase.transactionAsync` keeps one BEGIN IMMEDIATE...COMMIT but lets its body hand the native connection to a background isolate (`ProfileTransaction.run`: the same connection borrowed through `sqlite3.fromPointer(borrowed: true)`, bundled SQLite is THREADSAFE=1). While a job holds it, every UI-isolate route to the connection (`database`, `transaction`, another job) throws instead of touching it; the validator's scratch database is lent the same way and refuses selection meanwhile. Any failure, including COMMIT failing on the owner or the worker dying, rolls the whole transaction back on the UI isolate; a failed rollback poisons the profile as before. Memory is published only after the commit future completes, in the same order as before. Used by: the history commit (heads, workspace row, store rows with their encoding, and COMMIT; small refreshes under 64 records run the same job inline), the first Task attach (projection copy from the validator, index DDL, visible-row decode and freeze; the stage uses that work only for the exact branch, snapshot and revision it was prepared for, otherwise it clears and redoes it), and the warm store read (`readOffIsolate`: rows, rebuilt bytes and decode, no transaction). Projection stages themselves still run synchronously inside the transaction. Tests: `test/profile_owner_transaction_test.dart`.
- A strict open decodes each large writer file on its own background isolate ahead of the chain walk; the walk still checks every record in order and adopts a decode only for the identical raw line. The profile grows by roughly 1-2x the log bytes, and agent read and dry-run commands, which copy the profile, copy that too.
- Each distinct folder location spelling keeps its own store, like the Task projection tables. Stores for locations that are no longer used are not cleaned up yet.
- A crash in the foreground (no pause seal) still reopens the history from the store, but the Task projection is rebuilt strictly (about 1.1 s on the desktop harness).
