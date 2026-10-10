# Recovery and known boundaries

The unreleased [Food module](decisions/0014-food-inventory.md) retains exact
prepared bytes and offers explicit suffix retry after safe admission. An
isolated Food history error leaves compatible Tasks usable; shared manifest,
installation authority or DB faults stop writes. Shared Retry revalidates the
same owner and both modules without appending, resetting authority or discarding
mounted drafts. Restoring intact shared identity can resume those drafts; lost
protected guards/receipts and poisoned owners remain blocked.

1. Stop writes and preserve a copy of the entire selected data folder before repair. Sync is not a backup.
2. Read the visible error. Restore a missing or altered committed log from a known intact copy; do not merge log text by hand or remove a conflict copy merely to hide the warning.
3. Unknown format/type: install a compatible app. Keep the original records intact. No partial-success view is claimed at initial open.
4. Incomplete owned tail: save a backup, verify the prefix against another intact copy and the last complete newline, then repair only a proven interrupted append. There is deliberately no automatic tail truncation button yet.
5. A known obsolete cache layout is rebuilt automatically from supported canonical logs, retaining a private SQLite backup and preserving local writer identity, workspace identity and committed-stream integrity checks. Unknown future cache layouts remain untouched with an explicit compatible-app error. Incompatible canonical records still fail explicitly. For unrelated cache corruption, close all app instances and preserve the entire private profile before a targeted cache-only repair; never delete logs as a cache reset.
6. Android grant failure: re-select the original folder. A different folder or replaced manifest is not assumed to be the same space. Real-device replacement/reboot verification is required before recommending a provider setup.

Only one local instance may read/write a profile at a time (settings-root OS file lock held before preferences load). Do not clone a private profile to a second device; it would clone the writer. Sync only the selected canonical folder. Android backup is disabled to reduce this risk. A fresh installation generates a fresh writer and retains old history.

Current limitations: no automated backup/repair UI, no record-level encryption/access control, no log compaction, no provider pairing/control, no private-space UI or cross-space references. Input size bounds are per record; very large streams still need a streaming reader before claiming large-history mobile performance. A durable append followed by an I/O/cache error may have succeeded: refresh/reopen and inspect before manually repeating a capture.

Reopening a previously initialized location whose manifest disappeared fails without creating a replacement manifest, including when all canonical files disappeared together. Restore the original space before reopening; the local cache must not cause a fresh namespace to be written over missing history. A fresh, never-initialized location may still initialize normally.


## Local versus shared files in the next candidate

The selected canonical folder contains only `tandemlog-space.json` and per-writer `.jsonl` streams (plus transport-generated conflict/temp files if the sync provider creates them). Sync that folder, not its parent. New desktop setup uses `<private-profile>/shared-data`; a saved/custom selection stays unchanged, and a populated legacy `data` default remains recoverable after settings reset. Android uses the explicitly selected SAF tree.

The private profile contains `settings.json` (selected folder, active person, theme, installation writer), identity-free `writer-migration.json`, `profile.lock`, `writer-guards/<space UUID>.<writer UUID>.json`, and `spaces/<SHA256(selected location)>/`. Each space directory contains `cache.sqlite`, SQLite WAL/SHM when open, a defensive `session.lock`, retained cache-rebuild backups, and any legacy `writer-id` retained as inactive migration evidence. Temporary preference/marker files can remain after interrupted replacement. None of these private files should be synced or copied to another active installation.

Default Windows private root derives from `%APPDATA%\com.reddraggone9\tandemlog`. Default native Linux root is `${XDG_DATA_HOME:-$HOME/.local/share}/com.reddraggone9.tandemlog`; the path-provider plugin can retain its older executable-name root if that exists. Flatpak uses its sandbox data root, normally `~/.var/app/com.reddraggone9.tandemlog/data/com.reddraggone9.tandemlog`. Confirm installed paths on the target machine rather than inferring that native and Flatpak settings are shared. Existing user-selected folders are independent of these defaults.

SQLite is rebuildable functional state but also holds the last observed-history integrity baseline. Deleting it does not delete tasks; it does discard evidence needed to detect an old restored/mutated prefix. Preserve the entire private profile before cache repair. Deleting only settings after the migration marker exists creates a fresh installation writer; retained canonical history stays intact. Empty lock files are harmless and should not be deleted as an unlock mechanism. [ADR 0006](decisions/0006-installation-identity-and-instance-lock.md) details migration/reset behavior.

Use Settings **Check data integrity** for an explicit full scan while a workspace is open. It verifies every complete current record's self-hash and predecessor from genesis, checks semantics, and compares retained private observations. The report is selectable/copyable and identifies the failed writer log, record and byte offset when available. No automatic repair is performed. A partial remote tail waits; an owned partial tail remains a write-blocking interrupted-append error. Normal Retry/reopen/foreground reconciliation remains incremental and is not a substitute for this check.

V3 does not convert existing v1/v2 canonical folders. An incompatible-folder error is distinct from an obsolete disposable cache. Preserve old canonical files and private identity; coordinate any fresh test contents with Lee and all devices/apps before touching the permanent shared folder. A fresh v3 reconstruction checks current chain continuity but cannot detect a fully recomputed valid chain, removal of a whole writer stream or its final records without an independently trusted head. Keep backups; do not describe hashes as authenticated history.

The private writer guard survives cache deletion and a change of canonical-folder path. Restoring an older backup under the same workspace/writer identity stops writing if it lacks the acknowledged head or pending exact append prefix. A failed append can leave prepared sequences reserved even when no complete new record is currently visible; absence does not prove that attempted bytes cannot later arrive. Exact visible prefixes advance the guard, but unseen prepared records remain reserved and block new appends. Restore the exact prepared history from an intact verified copy when available; never skip sequences, clear the guard because a scan found nothing, or retry with a different payload under a reserved event ID. If that history is unavailable, deliberate fresh installation identity is a separate coordinated recovery action after backup; it is not automatic repair. Removing the whole private profile also removes this protection; a genuinely fresh installation cannot infer an old trusted head.

Linux locally created directories/files and atomic preference/guard replacements use parent-directory fsync barriers in addition to file flush. Other platforms retain their documented file/provider guarantees. Android rejects duplicate canonical manifest/log display names before accessing an ambiguous URI. Resolve duplicates through the provider after backing up; the app never selects one arbitrarily.
