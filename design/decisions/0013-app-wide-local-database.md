# One app-wide local database

Status: user-approved direction and temporary-file exception; isolated proof in progress. Production migration, activation and cleanup are not implemented or architecture-approved by this proof.

## Context and approved direction

Lee wants one permanent local-state DB across workspaces, with migrated legacy files removed after verified import. Downgrade support and permanent rollback copies are unnecessary. SQLite-managed recovery sidecars are explicitly accepted, including after a crash until recovery completes. Hourly workspace snapshots do not capture all installation identity, writer safety or pending intent state; Lee acknowledged that local-only recovery risk.

Use the existing private installation/profile root. Explicit `TANDEMLOG_PROFILE` remains an isolated installation override, not a per-workspace DB. Native Linux and Flatpak must continue discovering the same selected root. The launcher must recognize the new DB before legacy settings disappear, and must not silently merge two populated roots with different installation identities.

## Isolated implementation boundary

`LocalProfileDatabase` owns one SQLite connection and obtains an actual exclusive lock through a short startup write transaction. EXCLUSIVE is configured before the first WAL access; WAL/FULL remains durable and avoids the SHM file in exclusive mode. The connection stays open across workspace changes and closes only with its profile owner. No additional lock file is created for a fresh proof profile. Normal clean close leaves `local.sqlite`; process death may leave its recovery WAL. Never manually remove a live/hot journal or WAL.

The same-process canonical-root guard avoids opening a competing handle for ordinary path/symlink aliases. Never raw-read/hash/copy/rename/unlink the live DB from its owning process: closing an independent POSIX descriptor can interfere with SQLite's advisory locks. Use SQL or SQLite's backup API for live verification. The DB stays on local private storage, outside the synced workspace/SAF provider.

Protected table definitions are checked on reopen. Missing or weakened authority tables fail closed; they are not regenerated as empty caches. SQL-only transactions reject nested transactions and ordinary async callbacks. A failed rollback poisons the owner until close/recovery.

`SqliteWriterGuard` shares the unchanged sequence/hash/reservation policy with `FileWriterGuard`. Safety mutations commit before returning. `ProfileTextIntents` preserves and validates exact native receipt bytes, scoped by workspace and writer; it does not append canonical history or retire receipts automatically. The released v3 wire format and meaning remain unchanged.

`LegacyProtectedFilesImport` is deliberately **files-only**. It imports existing settings-owned writer identity, private guard records and text-intent JSON files under legacy profile/session leases, records source hashes, commits, then verifies through SQL plus source readback. Repeating an unchanged import does not overwrite newer guard state with stale source records. Conflicting/changed/linked sources fail closed. No originals are deleted, and there is no activation or cleanup API. Marker/legacy-writer manifest entries are evidence only, not a substitute for future workspace identity association.

## Exclusion boundary and independent review

The old profile and session locks are keyed by private roots, not canonical workspace paths. Different installation writers legitimately collaborate in the same workspace. A DB lease preserves same-profile exclusion, but cannot prevent two different profiles carrying a copied writer UUID from racing one canonical stream. That pre-existing identity-contract limitation is exposed by synthetic tests; this proof does not claim shared writer exclusion or weaken hash/reservation checks. A separate shared writer lease would require provider-compatible design and additional evidence; locking all writers out of a shared workspace would break collaboration.

Old binaries do not honor the new DB lease after legacy lock/settings cleanup. Concurrent use of those old binaries and downgrade in place are unsupported, consistent with Lee's decision. Legacy leases must span migration before cleanup.

## Remaining rollout gates

- Import protected location-to-space bindings, all trusted stream/head/range observations and cache-only outbox receipts from every legacy cache. Preserve conflicting observations; do not blindly deduplicate aliases. Account separately for historical backup caches and unsupported versions.
- Scope every global task table/key/index/query by workspace. Current TaskStore schema and replay/reset paths assume a disposable per-workspace DB. Do not reuse destructive cache migrations on protected tables. Review one shared transaction owner, explicit acknowledgement/projection atomicity and workspace-handle close semantics before wiring startup.
- Add exact-source allowlist cleanup only after complete verified import and activation. Track deletion progress durably, resume after interruption, and exclude unknown/changed/linked files and canonical workspace data. Filesystem deletion is not atomic with the SQLite transaction. No permanent downgrade fence or stale backup copies.
- Prove Windows and Android native contention, process death and clean-close behavior on the exact pinned SQLite/VFS. Linux subprocess tests do not substitute for those gates. Exercise migration crashes, disk/flush failures, source replacement and cleanup interruption.
- Independent architecture/correctness review before broad rollout. No live user data migration/cleanup or publication in this slice.

## Alternatives and revisit trigger

Exclusive rollback journaling can also leave one DB after clean close but retains a recovery journal during exclusive operation and usually adds write/sync work. Disk-journal OFF/MEMORY does not meet crash safety. A literal one-file-at-every-instant requirement would require substantial different storage work; it is no longer requested.

Revisit if native lease tests fail, another independent DB connection becomes necessary, same-writer cross-profile exclusion is required, or protected/rebuildable ownership cannot be kept explicit.

Sources: [SQLite locking](https://www.sqlite.org/pragma.html#pragma_locking_mode), [WAL without SHM and crash recovery](https://www.sqlite.org/wal.html), [temporary files](https://www.sqlite.org/tempfiles.html), [locking hazards](https://www.sqlite.org/howtocorrupt.html).
