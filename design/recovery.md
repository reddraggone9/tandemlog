# Recovery and known boundaries

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

The private profile contains `settings.json` (selected folder, active person, theme, installation writer), identity-free `writer-migration.json`, `profile.lock`, and `spaces/<SHA256(selected location)>/`. Each space directory contains `cache.sqlite`, SQLite WAL/SHM when open, a defensive `session.lock`, retained cache-rebuild backups, and any legacy `writer-id` retained as inactive migration evidence. Temporary preference/marker files can remain after interrupted replacement. None of these private files should be synced or copied to another active installation.

Default Windows private root derives from `%APPDATA%\com.reddraggone9\tandemlog`. Default native Linux root is `${XDG_DATA_HOME:-$HOME/.local/share}/com.reddraggone9.tandemlog`; the path-provider plugin can retain its older executable-name root if that exists. Flatpak uses its sandbox data root, normally `~/.var/app/com.reddraggone9.tandemlog/data/com.reddraggone9.tandemlog`. Confirm installed paths on the target machine rather than inferring that native and Flatpak settings are shared. Existing user-selected folders are independent of these defaults.

SQLite is rebuildable functional state but also holds the last observed-history integrity baseline. Deleting it does not delete tasks; it does discard evidence needed to detect an old restored/mutated prefix. Preserve the entire private profile before cache repair. Deleting only settings after the migration marker exists creates a fresh installation writer; retained canonical history stays intact. Empty lock files are harmless and should not be deleted as an unlock mechanism. [ADR 0006](decisions/0006-installation-identity-and-instance-lock.md) details migration/reset behavior.
