import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'local_durability.dart';
import 'profile_lock.dart' show ProfileInUse;

class LocalDatabaseFailure implements Exception {
  const LocalDatabaseFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Opt-in proof of one app-owned local connection and database-file lease.
/// Not wired into application startup or disposable TaskStore cache migration.
/// Callers must not open/close a separate raw file handle to this database.
class LocalProfileDatabase {
  LocalProfileDatabase._(this.root, this._database);
  static const fileName = 'local.sqlite';
  static const _applicationId =
      0x544c4442; // TLDB; local, not canonical format.
  static const _version = 1;
  static const _schema = {
    'profile_metadata':
        'CREATE TABLE profile_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'protected_writer_guards':
        'CREATE TABLE protected_writer_guards (space TEXT NOT NULL, writer TEXT NOT NULL, raw BLOB NOT NULL, PRIMARY KEY(space,writer))',
    'protected_text_intents':
        'CREATE TABLE protected_text_intents (space TEXT NOT NULL, writer TEXT NOT NULL, sequence INTEGER NOT NULL, id TEXT NOT NULL, entity TEXT NOT NULL, raw BLOB NOT NULL, PRIMARY KEY(space,writer,sequence), UNIQUE(space,id))',
    'protected_settings':
        'CREATE TABLE protected_settings (singleton INTEGER PRIMARY KEY CHECK(singleton=1), writer TEXT NOT NULL, raw BLOB NOT NULL)',
    'migration_file_imports':
        'CREATE TABLE migration_file_imports (path TEXT PRIMARY KEY, kind TEXT NOT NULL, hash TEXT NOT NULL)',
  };
  static final _held = <String>{};
  final String root;
  final Database _database;
  bool _closed = false;
  bool _poisoned = false;
  Future<void> _queue = Future<void>.value();
  final _workspaces = <String>{};
  Future<void>? _closing;

  /// Workspace operations may perform provider I/O, but only this queue admits
  /// them to the shared connection. Internal calls must not enqueue themselves.
  Future<T> serialize<T>(Future<T> Function() work) {
    if (_closed || _closing != null) {
      return Future.error(StateError('Local profile is closing.'));
    }
    final result = _queue.then((_) {
      database; // Fail closed after an earlier shared rollback failure.
      return work();
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void acquireWorkspace(String key) {
    if (!_workspaces.add(key)) {
      throw const ProfileInUse(
        'This workspace is already open in this profile.',
      );
    }
  }

  void releaseWorkspace(String key) => _workspaces.remove(key);

  /// One owner serializes short transactions. Do not dispose this connection
  /// from a workspace handle or hold transactions across provider I/O.
  Database get database {
    if (_closed || _poisoned) {
      throw StateError(
        'Local profile database is closed or requires recovery.',
      );
    }
    return _database;
  }

  static Future<LocalProfileDatabase> open(
    String root, {
    LocalDurability? durability,
  }) async {
    final barriers = durability ?? LocalDurability.shared;
    final directory = await barriers.ensureDirectoryDurable(Directory(root));
    final canonicalRoot = await directory.resolveSymbolicLinks();
    // A separate same-process handle can interfere with POSIX file locks.
    if (!_held.add(canonicalRoot)) throw const ProfileInUse(_inUse);
    Database? db;
    var transaction = false;
    try {
      final file = File('$canonicalRoot/$fileName');
      // No raw File open/read/close while SQLite owns its native handle.
      db = sqlite3.open(file.path);
      db.execute('PRAGMA busy_timeout=0');
      // Must precede any schema/header access to an existing WAL database.
      final locking = db.select('PRAGMA locking_mode=EXCLUSIVE');
      if (locking.single.values.single != 'exclusive') {
        throw const LocalDatabaseFailure(
          'Exclusive database locking is unavailable.',
        );
      }
      db.execute('PRAGMA synchronous=FULL');
      // The pragma alone does not acquire a lease. Retain the actual exclusive
      // lock after this short write transaction, rather than keeping an
      // uncommitted transaction open for the lifetime of the application.
      db.execute('BEGIN EXCLUSIVE');
      transaction = true;
      final version = db.select('PRAGMA user_version').single.values.single;
      final application = db
          .select('PRAGMA application_id')
          .single
          .values
          .single;
      if (version == 0 && application == 0) {
        if (db
            .select(
              "SELECT 1 FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%' LIMIT 1",
            )
            .isNotEmpty) {
          throw const LocalDatabaseFailure(
            'Unrecognized local database; retained without migration.',
          );
        }
        for (final sql in _schema.values) {
          db.execute(sql);
        }
        db.execute("INSERT INTO profile_metadata VALUES ('schema','1')");
        db.execute('PRAGMA application_id=$_applicationId');
        db.execute('PRAGMA user_version=$_version');
      } else if (version != _version || application != _applicationId) {
        throw const LocalDatabaseFailure(
          'Unsupported local database; retained without migration.',
        );
      }
      _verifyOwnedSchema(db);
      // Force a real write on reopen as well; obtaining EXCLUSIVE mode must be
      // proven before any settings, writer identity or workspace is used.
      db.execute("UPDATE profile_metadata SET value='1' WHERE key='schema'");
      if (db.updatedRows != 1) {
        throw const LocalDatabaseFailure(
          'Invalid local database metadata; preserve it before recovery.',
        );
      }
      db.execute('COMMIT');
      transaction = false;
      final journal = db.select('PRAGMA journal_mode=WAL');
      if (journal.single.values.single != 'wal') {
        throw const LocalDatabaseFailure('Durable WAL mode is unavailable.');
      }
      db.execute('PRAGMA synchronous=FULL');
      await barriers.syncParentAfterCreate(file);
      return LocalProfileDatabase._(canonicalRoot, db);
    } catch (error, stack) {
      Object? cleanupFailure;
      try {
        if (transaction && db != null && !db.autocommit) db.execute('ROLLBACK');
      } catch (failure) {
        cleanupFailure = failure;
      }
      var disposed = db == null;
      try {
        db?.close();
        disposed = true;
      } catch (failure) {
        cleanupFailure ??= failure;
      }
      // Failed native close must not enable another handle through our guard.
      // A process restart is required when connection disposal is unconfirmed.
      if (disposed) _held.remove(canonicalRoot);
      if (cleanupFailure != null) {
        throw LocalDatabaseFailure(
          'Local database open failed ($error); cleanup also failed ($cleanupFailure). Preserve the profile and restart before recovery.',
        );
      }
      if (error is SqliteException &&
          (error.resultCode == 5 || error.resultCode == 6)) {
        throw const ProfileInUse(_inUse);
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  static const _inUse =
      'This profile is already open in another TandemLog instance. Close that instance, then try again.';

  static void _verifyOwnedSchema(Database db) {
    for (final entry in _schema.entries) {
      final actual = db.select(
        "SELECT sql FROM sqlite_schema WHERE type='table' AND name=?",
        [entry.key],
      );
      // Local proof schema is frozen in this unpublished version. Checking the
      // complete definition also catches dropped PK/UNIQUE/NOT NULL checks.
      if (actual.length != 1 || actual.single['sql'] != entry.value) {
        throw const LocalDatabaseFailure(
          'Protected local database schema is missing or invalid; preserve it before recovery.',
        );
      }
    }
  }

  /// SQL work only: provider I/O and async callbacks are forbidden. Nested
  /// transactions are rejected rather than accidentally committing an outer
  /// store's projection transaction or safety reservation.
  T transaction<T>(T Function() work) {
    // Never-returning synchronous fault paths are subtypes of every return
    // type, including Future; do not mistake them for asynchronous callbacks.
    if (work is Future Function() && work is! Never Function()) {
      throw ArgumentError('Local database transactions must be synchronous.');
    }
    final db = database;
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = work();
      if (result is Future) {
        throw ArgumentError('Local database transactions must be synchronous.');
      }
      db.execute('COMMIT');
      return result;
    } catch (error, stack) {
      // SQLITE_FULL and some I/O failures can already roll back a transaction.
      // Preserve the initiating error instead of masking it with a second one.
      rollbackAfterFailure(error);
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Common failure boundary for the few transaction sites that must await a
  /// legacy file adapter. Shared ingestion itself does not await within SQL.
  void rollbackAfterFailure(Object error) {
    try {
      if (!_database.autocommit) _database.execute('ROLLBACK');
    } catch (failure) {
      _poisoned = true;
      throw LocalDatabaseFailure(
        'Local transaction failed ($error); rollback also failed ($failure). Close the profile before recovery.',
      );
    }
  }

  Future<void> close() {
    if (_closed) return Future<void>.value();
    if (_workspaces.isNotEmpty) {
      return Future.error(
        StateError('Close workspace handles before their profile.'),
      );
    }
    return _closing ??= _queue.then((_) {
      _database.close();
      _closed = true;
      _held.remove(root);
    });
  }
}
