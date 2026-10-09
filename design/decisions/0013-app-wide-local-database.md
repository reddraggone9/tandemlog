# One app-wide local database

Status: user-approved direction and temporary-file exception; database proof, shared TaskStore and integrated bootstrap/cleanup preparation independently reviewed. Application startup is wired in the combined storage/dependency candidate. Lee explicitly authorized this combined release. Exact Windows/Android acceptance, independent combined-source/artifact review and parent publication gates remain pending; no live-data operation is authorized.

## Context and approved direction

Lee wants one permanent local-state DB across workspaces, with migrated legacy files removed after verified import. Downgrade support and permanent rollback copies are unnecessary. SQLite-managed recovery sidecars are explicitly accepted, including after a crash until recovery completes. Hourly workspace snapshots do not capture all installation identity, writer safety or pending intent state; Lee acknowledged that local-only recovery risk.

Use the existing private installation/profile root. Explicit `TANDEMLOG_PROFILE` remains an isolated installation override, not a per-workspace DB. Native Linux and Flatpak must continue discovering the same selected root. The launcher must recognize the new DB before legacy settings disappear, and must not silently merge two populated roots with different installation identities.

## Isolated implementation boundary

`LocalProfileDatabase` owns one SQLite connection and obtains an actual exclusive lock through a short startup write transaction. EXCLUSIVE is configured before the first WAL access; WAL/FULL remains durable and avoids the SHM file in exclusive mode. The connection stays open across workspace changes and closes only with its profile owner. No additional lock file is created for a fresh proof profile. Normal clean close leaves `local.sqlite`; process death may leave its recovery WAL. Never manually remove a live/hot journal or WAL.

The same-process canonical-root guard avoids opening a competing handle for ordinary path/symlink aliases. Never raw-read/hash/copy/rename/unlink the live DB from its owning process: closing an independent POSIX descriptor can interfere with SQLite's advisory locks. Use SQL or SQLite's backup API for live verification. The DB stays on local private storage, outside the synced workspace/SAF provider.

Protected table definitions are checked on reopen. Missing or weakened authority tables fail closed; they are not regenerated as empty caches. SQL-only transactions reject nested transactions and ordinary async callbacks. A failed rollback poisons the owner until close/recovery.

`SqliteWriterGuard` shares the unchanged sequence/hash/reservation policy with `FileWriterGuard`. Reservations commit before canonical append. Shared ingestion acknowledges the head in the same transaction as admitted receipts and trusted checkpoints, then publishes its in-memory acknowledgement after commit. `ProfileTextIntents` preserves and validates exact native receipt bytes, scoped by workspace and writer. Shared TaskStore retires them only against exact admitted canonical bytes in that ingestion transaction. The released v3 wire format and meaning remain unchanged.

Opt-in TaskStore handles borrow the owner's connection and share its operation queue. Immutable `TaskTables` identifiers scope task, native-text, order and checklist queries/indexes by the established location hash; canonical space identity remains separately bound and checked. The owner reserves accepted opens before queue admission, so close cannot race a handle still opening. Closing a handle drains its accepted work, releases its namespace lease and native documents, and leaves other workspaces' connection open. Shared checklist display state uses the same transaction owner and explicit namespace.

Namespace projection versions are metadata, not the profile's global SQLite version. Unsupported bound versions fail closed before standalone legacy replay can run. Explicit namespace rebuild clears only derived events, views, order, native state/actor cache and the derived outbox. It retains bindings, stream/range observations, metadata, guards and protected intents and forces full replay even when log sizes are unchanged. Pending receipts are read from protected authority; the disposable outbox is reconstructed and reconciled with exact canonical receipts, including confirmation through another location alias.

`LegacyProtectedFilesImport` imports settings-owned writer identity, guard records and exact intent files under the coordinated legacy profile/session leases. `LegacyCacheImport` separately captures every recognized primary and historical cache through a committed SQLite snapshot, including committed WAL state: bindings, trusted prefixes/heads/ranges, accepted raw records, local metadata and outbox-only bytes. Unsupported/conflicting/changed/linked sources fail closed. Source observations are immutable recovery evidence inside the one DB; no standalone cache backups remain after complete cleanup. The primary supplies projection seeding while every relevant backup/alias observation is verified against canonical bytes before workspace admission.

`LocalProfileMigration` runs before adapters exist. It imports, reads back, validates source-to-target completeness and plans cleanup while holding the legacy leases. Only then does its durable active marker commit. Imported pending intents have immutable digest obligations; confirmation writes a matching workspace/writer/sequence digest proof in the same ingestion transaction as guard acknowledgement and intent retirement. Original guard baselines remain monotonic fences. Missing authorities cannot be mistaken for confirmation or repaired as an empty installation.

Cleanup releases legacy leases before unlinking their lock files. A validated exact-path/source-digest allowlist excludes unknown files, links, changed replacements, the app DB and canonical data. Each deletion commits `deleting`, rechecks source/target obligations, unlinks, confirms the parent directory barrier, then commits `deleted`. Restart resumes either side of unlink. Duplicate atomic replacements are accounted only when byte-exact; orphan/unconfirmed authorities stop activation. The old files are never reimported after activation. DB-backed preferences preserve the installation writer and unknown settings keys. Failed workspace switches restore store/importer, rows, checklist expansion and Undo; the app-wide owner closes after all handles drain. Linux launcher discovery recognizes both settings and the new DB, preserves an explicit override and stops when both supported roots contain state.

## Exclusion boundary and independent review

The old profile and session locks are keyed by private roots, not canonical workspace paths. Different installation writers legitimately collaborate in the same workspace. A DB lease preserves same-profile exclusion, but cannot prevent two different profiles carrying a copied writer UUID from racing one canonical stream. That pre-existing identity-contract limitation is exposed by synthetic tests; this proof does not claim shared writer exclusion or weaken hash/reservation checks. A separate shared writer lease would require provider-compatible design and additional evidence; locking all writers out of a shared workspace would break collaboration.

Old binaries do not honor the new DB lease after legacy lock/settings cleanup. Concurrent use of those old binaries and downgrade in place are unsupported, consistent with Lee's decision. Legacy leases must span migration before cleanup.

## Remaining rollout gates

- Retain frozen tests for all imported authorities, interrupted replay, exact outbox confirmation, target/source replacement, activation and cleanup cuts. Run the integrated source checks before parent integration; standalone fixture/maintenance clients still use their established cache path.
- Prove Windows and Android native contention, process death and clean-close behavior on the exact pinned SQLite/VFS. Linux subprocess tests do not substitute for those gates. Exercise migration crashes, disk/flush failures, source replacement and cleanup interruption.
- Independent architecture/correctness review and source-bound native handoff before broad rollout. No live user-data operation, push or publication in this slice. Coordinate refresh onto the parent's accepted dependency-only base after its separate candidate/native outcome.

## Alternatives and revisit trigger

Exclusive rollback journaling can also leave one DB after clean close but retains a recovery journal during exclusive operation and usually adds write/sync work. Disk-journal OFF/MEMORY does not meet crash safety. A literal one-file-at-every-instant requirement would require substantial different storage work; it is no longer requested.

Revisit if native lease tests fail, another independent DB connection becomes necessary, same-writer cross-profile exclusion is required, or protected/rebuildable ownership cannot be kept explicit.

Sources: [SQLite locking](https://www.sqlite.org/pragma.html#pragma_locking_mode), [WAL without SHM and crash recovery](https://www.sqlite.org/wal.html), [temporary files](https://www.sqlite.org/tempfiles.html), [locking hazards](https://www.sqlite.org/howtocorrupt.html).
