import 'dart:ffi';

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/common.dart' show CommonPreparedStatement;

/// Diagnostic API wall intervals, including binding, SQLite and result decoding.
/// No SQL text or arguments are passed to the observer. This is not an engine
/// statement counter: execute may run several statements and triggers are hidden.
typedef MeasureDatabaseCall =
    T Function<T>(String operation, T Function() work);

/// Only installed by an opt-in profile observer. All connection ownership,
/// hooks, results, parameters and exceptions remain with the original database.
class DiagnosticDatabase extends Database {
  DiagnosticDatabase(this.delegate, this.measure);
  final Database delegate;
  final MeasureDatabaseCall measure;

  @override
  void execute(String sql, [List<Object?> parameters = const []]) =>
      measure('sqlite.api.execute', () => delegate.execute(sql, parameters));
  @override
  ResultSet select(String sql, [List<Object?> parameters = const []]) =>
      measure('sqlite.api.select', () => delegate.select(sql, parameters));
  @override
  PreparedStatement prepare(
    String sql, {
    bool persistent = false,
    bool vtab = true,
    bool checkNoTail = false,
  }) => _DiagnosticStatement(
    measure(
      'sqlite.api.prepare',
      () => delegate.prepare(
        sql,
        persistent: persistent,
        vtab: vtab,
        checkNoTail: checkNoTail,
      ),
    ),
    measure,
  );
  @override
  List<PreparedStatement> prepareMultiple(
    String sql, {
    bool persistent = false,
    bool vtab = true,
  }) => [
    for (final statement in measure(
      'sqlite.api.prepareMultiple',
      () => delegate.prepareMultiple(sql, persistent: persistent, vtab: vtab),
    ))
      _DiagnosticStatement(statement, measure),
  ];
  @override
  PreparedStatement statementFromPointer({
    required Pointer<void> statement,
    required String sql,
    bool borrowed = false,
  }) => _DiagnosticStatement(
    delegate.statementFromPointer(
      statement: statement,
      sql: sql,
      borrowed: borrowed,
    ),
    measure,
  );

  @override
  DatabaseConfig get config => delegate.config;
  @override
  int get userVersion => delegate.userVersion;
  @override
  set userVersion(int value) => delegate.userVersion = value;
  @override
  int get lastInsertRowId => delegate.lastInsertRowId;
  @override
  int get updatedRows => delegate.updatedRows;
  @override
  int getUpdatedRows() => delegate.updatedRows;
  @override
  bool get autocommit => delegate.autocommit;
  @override
  Pointer<void> get handle => delegate.handle;
  @override
  Pointer<void> leak() => delegate.leak();
  @override
  Stream<SqliteUpdate> get updates => delegate.updates;
  @override
  Stream<SqliteUpdate> get updatesSync => delegate.updatesSync;
  @override
  Stream<void> get commits => delegate.commits;
  @override
  Stream<void> get rollbacks => delegate.rollbacks;
  @override
  VoidPredicate? get commitFilter => delegate.commitFilter;
  @override
  set commitFilter(VoidPredicate? value) => delegate.commitFilter = value;
  @override
  set busyHandler(bool Function(int count)? handler) =>
      delegate.busyHandler = handler;
  @override
  ({int current, int highwater}) status(
    StatusParameter option, {
    bool reset = false,
  }) => delegate.status(option, reset: reset);
  @override
  void createCollation({
    required String name,
    required CollatingFunction function,
  }) => delegate.createCollation(name: name, function: function);
  @override
  void createFunction({
    required String functionName,
    required ScalarFunction function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
    bool subtype = false,
  }) => delegate.createFunction(
    functionName: functionName,
    function: function,
    argumentCount: argumentCount,
    deterministic: deterministic,
    directOnly: directOnly,
    subtype: subtype,
  );
  @override
  void createAggregateFunction<V>({
    required String functionName,
    required AggregateFunction<V> function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
    bool subtype = false,
  }) => delegate.createAggregateFunction(
    functionName: functionName,
    function: function,
    argumentCount: argumentCount,
    deterministic: deterministic,
    directOnly: directOnly,
    subtype: subtype,
  );
  @override
  Stream<double> backup(Database toDatabase, {int nPage = 5}) =>
      delegate.backup(
        toDatabase is DiagnosticDatabase ? toDatabase.delegate : toDatabase,
        nPage: nPage,
      );
  @override
  void releaseMemory() => delegate.releaseMemory();
  @override
  void close() => delegate.close();
  @override
  void dispose() => delegate.close();
}

class _DiagnosticStatement extends CommonPreparedStatement
    implements PreparedStatement {
  _DiagnosticStatement(this.delegate, this.measure);
  final PreparedStatement delegate;
  final MeasureDatabaseCall measure;
  @override
  void executeWith(StatementParameters parameters) => measure(
    'sqlite.api.statement.execute',
    () => delegate.executeWith(parameters),
  );
  @override
  ResultSet selectWith(StatementParameters parameters) => measure(
    'sqlite.api.statement.select',
    () => delegate.selectWith(parameters),
  );
  // Cursor creation does not consume the cursor. Stepping and raw access remain
  // deliberately unmeasured rather than changing lazy execution semantics.
  @override
  IteratingCursor iterateWith(StatementParameters parameters) =>
      delegate.iterateWith(parameters);
  @override
  // ignore: experimental_member_use
  RawPreparedStatement get raw => delegate.raw;
  @override
  String get sql => delegate.sql;
  @override
  int get parameterCount => delegate.parameterCount;
  @override
  bool get isReadOnly => delegate.isReadOnly;
  @override
  bool get isExplain => delegate.isExplain;
  @override
  Pointer<void> get handle => delegate.handle;
  @override
  Pointer<void> leak() => delegate.leak();
  @override
  void reset() => delegate.reset();
  @override
  void close() => delegate.close();
  @override
  void dispose() => delegate.close();
}
