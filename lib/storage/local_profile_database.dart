import 'dart:io';
import 'dart:convert';

import '../domain/event.dart' show isCanonicalId;
import '../diagnostics/operation_observer.dart';

import 'package:sqlite3/sqlite3.dart';

import 'local_durability.dart';
import 'diagnostic_database.dart';
import 'profile_lock.dart' show ProfileInUse;

class LocalDatabaseFailure implements Exception {
  const LocalDatabaseFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Optional synchronous observation only. Implementations must not perform SQL
/// or alter profile state. Failures are counted and never change operation
/// results, error identity, transaction ordering or queue admission.
typedef ProfileDiagnosticObserver = OperationDiagnosticObserver;

/// App-owned local connection and database-file lease. At coordinated cutover,
/// old local state is reset transactionally while retaining device preferences.
/// Callers must not open/close a separate raw file handle to this database.
class LocalProfileDatabase {
  LocalProfileDatabase._(this.root, this._database);
  static const fileName = 'local.sqlite';
  static const _applicationId =
      0x544c4442; // TLDB; local, not canonical format.
  static const schemaVersion = 6;
  static const _version = schemaVersion;
  static const _schema = {
    'protected_app_workspaces':
        'CREATE TABLE protected_app_workspaces (space TEXT PRIMARY KEY, epoch TEXT NOT NULL, manifest TEXT NOT NULL, observed TEXT NOT NULL)',
    'protected_app_heads':
        'CREATE TABLE protected_app_heads (space TEXT NOT NULL, epoch TEXT NOT NULL, writer TEXT NOT NULL, sequence INTEGER NOT NULL, hash TEXT NOT NULL, bytes INTEGER NOT NULL, digest TEXT NOT NULL, published INTEGER NOT NULL, PRIMARY KEY(space,epoch,writer))',
    'profile_metadata':
        'CREATE TABLE profile_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'protected_settings':
        'CREATE TABLE protected_settings (singleton INTEGER PRIMARY KEY CHECK(singleton=1), writer TEXT NOT NULL, raw BLOB NOT NULL)',
  };
  static final _held = <String>{};
  final String root;
  final Database _database;
  bool _closed = false;
  bool _poisoned = false;
  Future<void> _queue = Future<void>.value();
  final _workspaces = <String>{};
  Future<void>? _closing;
  ProfileDiagnosticObserver? diagnosticObserver;
  DiagnosticDatabase? _diagnosticDatabase;
  int diagnosticCallbackFailures = 0;

  Object? _diagnosticStart(ProfileDiagnosticObserver? observer, String name) {
    if (observer == null) return null;
    try {
      return observer.start(name);
    } catch (_) {
      diagnosticCallbackFailures++;
      return null;
    }
  }

  void _diagnosticFinish(
    ProfileDiagnosticObserver? observer,
    Object? token,
    bool succeeded,
  ) {
    if (observer == null || token == null) return;
    try {
      observer.finish(token, succeeded);
    } catch (_) {
      diagnosticCallbackFailures++;
    }
  }

  T _diagnose<T>(String name, T Function() work) {
    final observer = diagnosticObserver;
    if (observer == null) return work();
    final token = _diagnosticStart(observer, name);
    var succeeded = false;
    try {
      final value = work();
      succeeded = true;
      return value;
    } finally {
      _diagnosticFinish(observer, token, succeeded);
    }
  }

  /// Optional phase observation; application payloads are never passed through.
  T observeSynchronous<T>(String name, T Function() work) =>
      _diagnose(name, work);

  Future<T> observeAsynchronous<T>(String name, Future<T> Function() work) {
    final observer = diagnosticObserver;
    if (observer == null) return work();
    final token = _diagnosticStart(observer, name);
    Future<T> measured() async {
      var succeeded = false;
      try {
        final result = await work();
        succeeded = true;
        return result;
      } finally {
        _diagnosticFinish(observer, token, succeeded);
      }
    }

    return measured();
  }

  void _executeControl(Database db, String sql, String name) {
    if (diagnosticObserver == null) {
      db.execute(sql);
    } else {
      _diagnose<void>(name, () => db.execute(sql));
    }
  }

  /// Workspace operations may perform provider I/O, but only this queue admits
  /// them to the shared connection. Internal calls must not enqueue themselves.
  Future<T> serialize<T>(Future<T> Function() work) {
    if (_closed || _closing != null) {
      return Future.error(StateError('Local profile is closing.'));
    }
    final observer = diagnosticObserver;
    final waiting = _diagnosticStart(observer, 'profile.queueWait');
    final result = _queue.then((_) {
      _diagnosticFinish(observer, waiting, true);
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

  /// Drain accepted work and release a handle even after SQL rollback poisoning.
  /// Cleanup must not access the database or enqueue another profile operation.
  Future<void> closeWorkspace(String key, void Function() cleanup) {
    final result = _queue.then((_) {
      try {
        cleanup();
      } finally {
        releaseWorkspace(key);
      }
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// One owner serializes short transactions. Do not dispose this connection
  /// from a workspace handle or hold transactions across provider I/O.
  Database get database {
    if (_closed || _poisoned) {
      throw StateError(
        'Local profile database is closed or requires recovery.',
      );
    }
    return diagnosticObserver == null
        ? _database
        : _diagnosticDatabase ??= DiagnosticDatabase(_database, _diagnose);
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
        db.execute(
          "INSERT INTO profile_metadata VALUES ('schema','$_version')",
        );
        db.execute('PRAGMA application_id=$_applicationId');
        db.execute('PRAGMA user_version=$_version');
      } else if (version is int &&
          version >= 1 &&
          version <= 5 &&
          application == _applicationId) {
        // The coordinated cutover deliberately abandons old caches, local
        // drafts and unfinished intent. Preserve the small preferences row;
        // never run the retired legacy file/event importers.
        final settingsSchema = db.select(
          "SELECT sql FROM sqlite_schema WHERE type='table' AND name='protected_settings'",
        );
        if (settingsSchema.length != 1 ||
            settingsSchema.single['sql'] != _schema['protected_settings']) {
          throw const LocalDatabaseFailure(
            'Cannot preserve installation settings from this old profile.',
          );
        }
        final rows = db.select(
          'SELECT writer,typeof(raw) AS kind,length(raw) AS size,raw FROM protected_settings',
        );
        if (rows.length != 1 ||
            rows.single['kind'] != 'blob' ||
            rows.single['size'] is! int ||
            (rows.single['size'] as int) > 65536) {
          throw const LocalDatabaseFailure(
            'Old installation settings are missing or invalid.',
          );
        }
        final Object? value;
        try {
          value = jsonDecode(utf8.decode(rows.single['raw'] as List<int>));
        } on FormatException {
          throw const LocalDatabaseFailure(
            'Old installation settings are not valid UTF-8 JSON.',
          );
        }
        if (value is! Map<String, dynamic> ||
            !isCanonicalId(value['writer']) ||
            value['writer'] != rows.single['writer'] ||
            value['folder'] != null && value['folder'] is! String ||
            value['user'] != null && value['user'] is! String ||
            value['appearance'] != null &&
                !{'system', 'light', 'dark'}.contains(value['appearance'])) {
          throw const LocalDatabaseFailure(
            'Old installation settings binding is invalid.',
          );
        }
        final kept = {
          for (final key in [
            'writer',
            'folder',
            'user',
            'appearance',
            'lastSection',
          ])
            if (value.containsKey(key)) key: value[key],
        };
        final tables = db
            .select(
              "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((r) => r['name'] as String)
            .toList();
        for (final table in tables) {
          db.execute('DROP TABLE "${table.replaceAll('"', '""')}"');
        }
        for (final sql in _schema.values) {
          db.execute(sql);
        }
        db.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
          kept['writer'],
          utf8.encode(jsonEncode(kept)),
        ]);
        db.execute(
          "INSERT INTO profile_metadata VALUES ('schema','$_version')",
        );
        db.execute('PRAGMA user_version=$_version');
      } else if (version != _version || application != _applicationId) {
        throw const LocalDatabaseFailure(
          'Unsupported local database; retained without migration.',
        );
      }
      _verifyOwnedSchema(db);
      // Force a real write on reopen as well; obtaining EXCLUSIVE mode must be
      // proven before any settings, writer identity or workspace is used.
      db.execute(
        "UPDATE profile_metadata SET value='$_version' WHERE key='schema'",
      );
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
      // Each admitted local schema is frozen. Checking the
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
    if (diagnosticObserver == null) return _transaction(work);
    return _diagnose('sqlite.transaction', () => _transaction(work));
  }

  T _transaction<T>(T Function() work) {
    final db = database;
    // BEGIN remains outside the rollback catch: a failed BEGIN must not roll
    // back another owner's transaction.
    _executeControl(db, 'BEGIN IMMEDIATE', 'sqlite.begin');
    try {
      final result = diagnosticObserver == null
          ? work()
          : _diagnose('sqlite.body', work);
      if (result is Future) {
        throw ArgumentError('Local database transactions must be synchronous.');
      }
      _executeControl(db, 'COMMIT', 'sqlite.commit');
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
      // The SQLite wrapper's autocommit getter does not check whether its
      // native handle was closed. Empty SQL checks wrapper liveness before
      // reading transaction state, without executing a database command.
      _database.execute('');
      if (!_database.autocommit) {
        _executeControl(_database, 'ROLLBACK', 'sqlite.rollback');
      }
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
