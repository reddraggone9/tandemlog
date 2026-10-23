import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';

const user = '00000000-0000-4000-8000-000000000001';
String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> row(TaskStore s, String id) =>
    s.rows.singleWhere((r) => r['id'] == id);

void main() {
  late Directory root, folder;
  final stores = <TaskStore>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('occurrence-due-synthetic-');
    folder = await Directory('${root.path}/shared').create();
  });
  tearDown(() async {
    for (final s in stores.reversed) {
      await s.close();
    }
    stores.clear();
    await root.delete(recursive: true);
  });
  Future<TaskStore> open(String profile) async {
    final s = await TaskStore.open(
      LocalLogFolder(folder.path),
      '${root.path}/$profile',
    );
    stores.add(s);
    return s;
  }

  Future<void> seed(TaskStore s, int n, Map<String, dynamic> schedule) =>
      s.command(id(n), 'task.created', {
        'title': 'Synthetic $n',
        'description': 'Retain notes',
        'tags': ['synthetic'],
        'assignee': user,
        'schedule': schedule,
      });

  test(
    'ordinary append preserves canonical prefix, other fields, existing Due and conflict; cold replay is idempotent',
    () async {
      final s = await open('a');
      await s.command(user, 'user.created', {'name': 'Synthetic'});
      await seed(s, 2, {
        'scheduledDate': '2030-10-05',
        'scheduledTime': '00:00',
        'timeZone': 'UTC',
        'recurrence': 'every week',
        'dueMinDays': 0,
      });
      await seed(s, 3, {
        'scheduledDate': '2030-10-05',
        'dueDate': '2030-10-06',
        'recurrence': 'every week',
      });
      await seed(s, 4, {
        'startDate': '2030-10-06',
        'scheduledDate': '2030-10-05',
        'recurrence': 'every week',
      });
      await seed(s, 5, {
        'startDate': '2030-10-01',
        'scheduledDate': '2030-10-05',
        'recurrence': 'every week',
      });
      final before = {
        for (final n in [2, 3, 4, 5]) n: jsonDecode(jsonEncode(row(s, id(n)))),
      };
      final log = File('${folder.path}/${s.writer}.applog');
      final prefix = await log.readAsBytes();
      final result = await s.migrateOccurrenceDates();
      expect(result.migrated, 2);
      expect(result.conflicts.keys, [id(4)]);
      expect(result.error, isNull);
      final bytes = await log.readAsBytes();
      expect(bytes.sublist(0, prefix.length), prefix);
      final appended = utf8
          .decode(bytes.sublist(prefix.length))
          .trim()
          .split('\n')
          .expand((raw) => (jsonDecode(raw)['effects'] as List))
          .map((effect) => jsonDecode((effect as Map)['raw'] as String))
          .toList();
      expect(appended.length, 2);
      for (final event in appended) {
        expect(event['operation'], {'family': 'task.update', 'revision': 1});
        expect(((event['value'] as Map)['values'] as Map).keys, ['schedule']);
      }
      for (final n in [2, 5]) {
        final task = row(s, id(n)), old = before[n] as Map;
        for (final field in [
          'title',
          'description',
          'tags',
          'tagRefs',
          'assignee',
          'completed',
          'inbox',
          'position',
        ]) {
          expect(task[field], old[field], reason: field);
        }
        final schedule = task['schedule'] as Map;
        expect(schedule['dueDate'], '2030-10-05');
        expect(schedule['scheduledDate'], isNull);
        expect(schedule['scheduledTime'], isNull);
      }
      expect((row(s, id(2))['schedule'] as Map)['dueTime'], '00:00');
      expect(row(s, id(3)), before[3]);
      expect(row(s, id(4)), before[4]);
      final replay = await open('cold');
      expect(replay.taskSnapshot, s.taskSnapshot);
      final again = await replay.migrateOccurrenceDates();
      expect(again.migrated, 0);
      expect(again.conflicts.keys, [id(4)]);
      expect(await log.readAsBytes(), bytes);
      expect(await s.migrateOccurrenceDates().then((r) => r.migrated), 0);
    },
  );

  test(
    'freshly synced Due is preserved and cancellation appends nothing',
    () async {
      final a = await open('a');
      await a.command(user, 'user.created', {'name': 'Synthetic'});
      await seed(a, 2, {
        'scheduledDate': '2030-10-05',
        'recurrence': 'every week',
      });
      final b = await open('b');
      final initial = File('${folder.path}/${a.writer}.applog');
      final prefix = await initial.readAsBytes();
      expect(
        (await a.migrateOccurrenceDates(canCommit: () => false)).migrated,
        0,
      );
      expect(await initial.readAsBytes(), prefix);
      await b.edit(
        id(2),
        {
          'schedule': {
            'dueDate': '2030-10-12',
            'scheduledDate': '2030-10-05',
            'recurrence': 'every week',
          },
        },
        tags: ['synthetic'],
        observedTagRefs: Map<String, String>.from(
          row(b, id(2))['tagRefs'] as Map,
        ),
      );
      expect((await a.migrateOccurrenceDates()).migrated, 0);
      expect((row(a, id(2))['schedule'] as Map)['dueDate'], '2030-10-12');
      expect(await initial.readAsBytes(), prefix);
      expect(a.taskSnapshot, b.taskSnapshot);
    },
  );
  test('revoked draft admission after planning prevents the append', () async {
    final s = await open('a');
    await s.command(user, 'user.created', {'name': 'Synthetic'});
    await seed(s, 2, {
      'scheduledDate': '2030-10-05',
      'recurrence': 'every week',
    });
    final log = File('${folder.path}/${s.writer}.applog');
    final prefix = await log.readAsBytes();
    final before = jsonDecode(jsonEncode(row(s, id(2))));
    var admissionChecks = 0;
    final result = await s.migrateOccurrenceDates(
      canCommit: () => ++admissionChecks == 1,
    );
    expect(admissionChecks, greaterThanOrEqualTo(2));
    expect(result.migrated, 0);
    expect(result.error, isNull);
    expect(row(s, id(2)), before);
    expect(await log.readAsBytes(), prefix);
  });

  test(
    'internal migration refresh reports newly imported noneligible rows even with zero conversions',
    () async {
      final a = await open('a');
      await a.command(user, 'user.created', {'name': 'Synthetic'});
      final b = await open('b');
      final view = a.currentView;
      final cacheTransactions = a.cacheTransactions;
      expect(await a.refresh(), isFalse);
      expect(identical(a.currentView, view), isTrue);
      expect(a.cacheTransactions, cacheTransactions);
      await b.command(id(9), 'user.created', {'name': 'Newly synced person'});
      final result = await a.migrateOccurrenceDates();
      expect(result.migrated, 0);
      expect(result.changed, isTrue);
      expect(row(a, id(9))['name'], 'Newly synced person');
      expect((await a.migrateOccurrenceDates()).changed, isFalse);
    },
  );
}
