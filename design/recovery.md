# Recovery and known boundaries

1. Stop writes and preserve a copy of the entire selected data folder before repair. Sync is not a backup.
2. Read the visible error. Restore a missing or altered committed log from a known intact copy; do not merge log text by hand or remove a conflict copy merely to hide the warning.
3. Unknown format/type: install a compatible app. Keep the original records intact. No partial-success view is claimed at initial open.
4. Incomplete owned tail: save a backup, verify the prefix against another intact copy and the last complete newline, then repair only a proven interrupted append. There is deliberately no automatic tail truncation button yet.
5. Corrupt/incompatible cache with intact canonical history: close all app instances, preserve the private `writer-id`, remove only `cache.sqlite`, `cache.sqlite-wal` and `cache.sqlite-shm` in the matching private space directory, and reopen. Never delete logs as a cache reset.
6. Android grant failure: re-select the original folder. A different folder or replaced manifest is not assumed to be the same space. Real-device replacement/reboot verification is required before recommending a provider setup.

Only one local instance may write a profile at a time (OS file lock). Do not clone a private profile to a second device; it would clone the writer. Sync only the selected canonical folder. Android backup is disabled to reduce this risk. A fresh installation generates a fresh writer and retains old history.

Current limitations: no automated backup/repair UI, no record-level encryption/access control, no log compaction, no provider pairing/control, no private-space UI or cross-space references. Input size bounds are per record; very large streams still need a streaming reader before claiming large-history mobile performance. A durable append followed by an I/O/cache error may have succeeded: refresh/reopen and inspect before manually repeating a capture.

Reopening a previously initialized location whose manifest disappeared fails without creating a replacement manifest, including when all canonical files disappeared together. Restore the original space before reopening; the local cache must not cause a fresh namespace to be written over missing history. A fresh, never-initialized location may still initialize normally.
