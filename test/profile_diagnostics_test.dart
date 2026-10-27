import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/text/native_text_engine.dart';

import '../tool/windows_widget_qa/probe_cost_trace.dart';

class _Observer implements ProfileDiagnosticObserver {
  _Observer({this.failStart = false, this.failFinish = false});
  final bool failStart, failFinish;
  final events = <(String, bool?)>[];
  @override
  Object start(String operation) {
    events.add((operation, null));
    if (failStart) throw StateError('observer start');
    return operation;
  }

  @override
  void finish(Object token, bool succeeded) {
    events.add((token as String, succeeded));
    if (failFinish) throw StateError('observer finish');
  }
}

void main() {
  for (final failStart in [false, true]) {
    for (final failFinish in [false, true]) {
      test('native API observer preserves native success and failure '
          'start=$failStart finish=$failFinish', () {
        final engine = NativeTextEngine(
          libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
        );
        final observer = _Observer(
          failStart: failStart,
          failFinish: failFinish,
        );
        engine.diagnosticObserver = observer;
        try {
          expect(engine.seedText('Synthetic probe').bytes, isNotEmpty);
          expect(
            () => engine.inspect(NativeTextUpdate.parse('AQID')),
            throwsA(
              isA<NativeTextException>().having(
                (e) => e.operation,
                'operation',
                'inspect',
              ),
            ),
          );
          expect(
            engine.diagnosticCallbackFailures,
            failStart || failFinish ? 2 : 0,
          );
          if (!failStart) {
            expect(observer.events, contains(('native.api.inspect', false)));
          }
        } finally {
          engine.dispose();
        }
      });
    }
  }
  late Directory root;
  late LocalProfileDatabase profile;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('profile-diagnostics-');
    profile = await LocalProfileDatabase.open(root.path);
    profile.database.execute('CREATE TABLE evidence(value TEXT UNIQUE)');
  });
  tearDown(() async {
    await profile.close();
    await root.delete(recursive: true);
  });

  for (final failStart in [false, true]) {
    for (final failFinish in [false, true]) {
      test('observer faults preserve success/error identity '
          'start=$failStart finish=$failFinish', () async {
        final observer = _Observer(
          failStart: failStart,
          failFinish: failFinish,
        );
        profile.diagnosticObserver = observer;
        final value = Object();
        expect(
          profile.transaction(() {
            profile.database.execute('INSERT INTO evidence VALUES (?)', ['ok']);
            return value;
          }),
          same(value),
        );
        final failure = StateError('original action');
        expect(
          () => profile.transaction<Never>(() {
            profile.database.execute('INSERT INTO evidence VALUES (?)', [
              'revert',
            ]);
            throw failure;
          }),
          throwsA(same(failure)),
        );
        expect(await profile.serialize(() async => value), same(value));
        await expectLater(
          profile.serialize<Never>(() async => throw failure),
          throwsA(same(failure)),
        );
        expect(
          await profile.observeAsynchronous(
            'fixture.asyncSuccess',
            () async => value,
          ),
          same(value),
        );
        await expectLater(
          profile.observeAsynchronous<Never>(
            'fixture.asyncFailure',
            () async => throw failure,
          ),
          throwsA(same(failure)),
        );
        expect(
          profile.database.select('SELECT value FROM evidence').single['value'],
          'ok',
        );
        expect(profile.database.autocommit, isTrue);
        expect(
          profile.diagnosticCallbackFailures,
          failStart || failFinish
              ? observer.events.where((e) => e.$2 == null).length
              : 0,
        );
      });
    }
  }

  test(
    'nested BEGIN failure leaves the outer transaction owned and intact',
    () {
      final observer = _Observer();
      profile.diagnosticObserver = observer;
      profile.transaction(() {
        profile.database.execute("INSERT INTO evidence VALUES ('outer')");
        expect(
          () => profile.transaction(() => fail('nested body ran')),
          throwsA(isA<SqliteException>()),
        );
        expect(profile.database.autocommit, isFalse);
        expect(
          profile.database.select('SELECT value FROM evidence').single['value'],
          'outer',
        );
      });
      expect(profile.database.autocommit, isTrue);
      expect(observer.events, contains(('sqlite.begin', false)));
      expect(observer.events.where((e) => e.$1 == 'sqlite.rollback'), isEmpty);
    },
  );

  test('failed COMMIT rolls back; automatic rollback needs no second SQL', () {
    final observer = _Observer();
    profile.diagnosticObserver = observer;
    final db = profile.database;
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('CREATE TABLE parent(id INTEGER PRIMARY KEY)');
    db.execute(
      'CREATE TABLE child(parent INTEGER REFERENCES parent(id) '
      'DEFERRABLE INITIALLY DEFERRED)',
    );
    expect(
      () =>
          profile.transaction(() => db.execute('INSERT INTO child VALUES (1)')),
      throwsA(isA<SqliteException>()),
    );
    expect(db.select('SELECT * FROM child'), isEmpty);
    expect(db.autocommit, isTrue);
    expect(observer.events, contains(('sqlite.commit', false)));
    expect(observer.events, contains(('sqlite.rollback', true)));
    observer.events.clear();
    db.execute(
      'CREATE TABLE unique_values(value TEXT UNIQUE ON CONFLICT ROLLBACK)',
    );
    expect(
      () => profile.transaction(() {
        db.execute("INSERT INTO unique_values VALUES ('duplicate')");
        db.execute("INSERT INTO unique_values VALUES ('duplicate')");
      }),
      throwsA(isA<SqliteException>()),
    );
    expect(db.autocommit, isTrue);
    expect(db.select('SELECT * FROM unique_values'), isEmpty);
    expect(observer.events.where((e) => e.$1 == 'sqlite.rollback'), isEmpty);
    expect(profile.transaction(() => 7), 7);
  });

  test(
    'queue waits preserve order, failure recovery and admitted close drain',
    () async {
      final observer = _Observer(failFinish: true);
      profile.diagnosticObserver = observer;
      final gate = Completer<void>();
      final admitted = Completer<void>();
      final order = <String>[];
      final first = profile.serialize<void>(() async {
        order.add('first');
        admitted.complete();
        await gate.future;
        throw StateError('first fails');
      });
      final expectedFailure = expectLater(first, throwsStateError);
      final second = profile.serialize(() async {
        order.add('second');
        return 7;
      });
      await admitted.future;
      final closing = profile.close();
      await expectLater(
        profile.serialize(() async => fail('late work admitted')),
        throwsStateError,
      );
      expect(order, ['first']);
      gate.complete();
      await expectedFailure;
      expect(await second, 7);
      await closing;
      expect(order, ['first', 'second']);
      expect(
        observer.events.where((e) => e == ('profile.queueWait', true)),
        hasLength(2),
      );
      expect(profile.diagnosticCallbackFailures, 2);
    },
  );

  test(
    'API spans count direct and prepared calls without observing SQL text',
    () {
      final trace = ProbeCostTrace(() => 0);
      profile.diagnosticObserver = ProbeProfileDiagnostics(trace);
      final db = profile.database;
      profile.transaction(
        () => db.execute('INSERT INTO evidence VALUES (?)', ['private-value']),
      );
      expect(
        trace.spans.where((s) => s['operation'] == 'sqlite.api.execute'),
        hasLength(3),
      );
      expect(
        trace.spans.where((s) => s['operation'] == 'sqlite.transaction'),
        hasLength(1),
      );
      expect(trace.report().toString(), isNot(contains('private-value')));
      trace.spans.clear();
      final insert = db.prepare('INSERT INTO evidence VALUES (?)');
      try {
        insert.execute(['prepared']);
        expect(
          () => insert.execute(['prepared']),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        insert.close();
      }
      final select = db.prepare('SELECT value FROM evidence ORDER BY value');
      try {
        expect(select.select().map((r) => r['value']), [
          'prepared',
          'private-value',
        ]);
        // Lazy stepping remains lazy and is explicitly outside the observed API.
        final cursor = select.iterateWith(StatementParameters(const []));
        expect(cursor.moveNext(), isTrue);
        select.reset();
      } finally {
        select.close();
      }
      expect(
        trace.spans.where((s) => s['operation'] == 'sqlite.api.prepare'),
        hasLength(2),
      );
      final executions = trace.spans
          .where((s) => s['operation'] == 'sqlite.api.statement.execute')
          .toList();
      expect(executions, hasLength(2));
      expect(executions.last['succeeded'], isFalse);
      expect(profile.diagnosticCallbackFailures, 0);
    },
  );

  test(
    'observation can be disabled without changing the connection or retained statement',
    () {
      final original = profile.database;
      final trace = ProbeCostTrace(() => 0);
      profile.diagnosticObserver = ProbeProfileDiagnostics(trace);
      final observed = profile.database;
      expect(observed.handle, original.handle);
      final statement = observed.prepare('SELECT 1 AS value');
      profile.diagnosticObserver = null;
      expect(profile.database, same(original));
      final count = trace.spans.length;
      expect(statement.select().single['value'], 1);
      statement.close();
      expect(trace.spans, hasLength(count));
    },
  );

  test(
    'database hook, configuration, multi-statement and backup delegation',
    () async {
      final raw = profile.database;
      final trace = ProbeCostTrace(() => 0);
      profile.diagnosticObserver = ProbeProfileDiagnostics(trace);
      final db = profile.database;
      expect(db.config, isA<DatabaseConfig>());
      db.userVersion = LocalProfileDatabase.schemaVersion;
      db.execute(
        "INSERT INTO evidence VALUES ('first'); INSERT INTO evidence VALUES ('second');",
      );
      expect(db.updatedRows, raw.updatedRows);
      expect(db.lastInsertRowId, raw.lastInsertRowId);
      expect(db.userVersion, raw.userVersion);
      final updates = <SqliteUpdate>[];
      final subscription = db.updatesSync.listen(updates.add);
      try {
        db.execute("INSERT INTO evidence VALUES ('hook')");
        expect(updates.single.tableName, 'evidence');
      } finally {
        await subscription.cancel();
      }
      final destination = sqlite3.openInMemory();
      try {
        await db.backup(destination).drain<void>();
        expect(
          destination
              .select('SELECT value FROM evidence ORDER BY value')
              .map((r) => r['value']),
          ['first', 'hook', 'second'],
        );
      } finally {
        destination.close();
      }
      final statements = db.prepareMultiple('SELECT 1; SELECT 2;');
      try {
        expect(statements.map((s) => s.select().single.values.single), [1, 2]);
      } finally {
        for (final statement in statements) {
          statement.close();
        }
      }
    },
  );

  test('waiting does not count another queued action as owned SQL', () async {
    var now = 0;
    final trace = ProbeCostTrace(() => now++);
    profile.diagnosticObserver = ProbeProfileDiagnostics(trace);
    final gate = Completer<void>();
    final first = profile.serialize(() async {
      profile.database.execute('SELECT 1');
      await gate.future;
    });
    final second = profile.serialize(() async => 7);
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await first;
    expect(await second, 7);
    final waits = trace.spans
        .where((s) => s['operation'] == 'profile.queueWait')
        .toList();
    expect(waits, hasLength(2));
    expect(waits.last.containsKey('sqlStatementStarts'), isFalse);
    expect(
      trace.spans.where((s) => s['operation'] == 'sqlite.api.execute'),
      hasLength(1),
    );
  });
}
