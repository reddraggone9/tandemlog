import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'support/stable123_schedule.dart' as stable;

// Frozen verbatim from stable123 a6de3d53, except its wall_time import.
// The old decoder must actually parse the persisted rule, not just its revision.
void main() {
  test(
    'historical recurrence bytes and supported input spellings stay exact',
    () {
      for (final rule in [
        'every week on Monday,Thursday',
        'every week on Monday, Thursday',
        'every week on Monday and Thursday',
        'every January, and May on the 15th',
      ]) {
        final event = LogEvent(
          '00000000-0000-4000-8000-000000000001',
          '00000000-0000-4000-8000-000000000002',
          1,
          EventClock(BigInt.one),
          '00000000-0000-4000-8000-000000000003',
          'task.edited',
          {
            'schedule': {'dueDate': '2026-11-16', 'recurrence': rule},
          },
        );
        final bytes = event.encode();
        expect(LogEvent.decode(bytes).encode(), bytes);
        expect(
          (LogEvent.decode(bytes).data['schedule'] as Map)['recurrence'],
          rule,
        );
        if (!rule.contains('Monday,Thursday')) {
          expect(normalizeNewRecurrenceInput(rule), rule);
        }
      }
    },
  );

  test('new inputs persist stable123-supported separators', () async {
    final root = await Directory.systemTemp.createTemp('separator-write-');
    final store = await TaskStore.open(
      LocalLogFolder('${root.path}/logs'),
      '${root.path}/profile',
    );
    try {
      final user = const Uuid().v4();
      await store.command(user, 'user.created', {'name': 'Example'});
      for (final list in [
        'Monday,Thursday',
        'Monday,  Thursday',
        'Monday  and  Thursday',
        'Monday,  and  Thursday',
      ]) {
        for (final rule in [
          'every week on $list when done',
          'every ${list.replaceAll('Monday', 'January').replaceAll('Thursday', 'May')} on the 15th',
        ]) {
          final id = const Uuid().v4();
          final input = {'dueDate': '2026-11-16', 'recurrence': rule};
          final created = await store.command(id, 'task.created', {
            'title': 'Example',
            'description': '',
            'assignee': user,
            'schedule': input,
          });
          void check(Map data) {
            final saved = Map<String, dynamic>.from(data['schedule'] as Map);
            final old = stable.TaskSchedule.fromJson(saved);
            final current = TaskSchedule.fromJson(saved);
            expect(
              old.next(DateTime.utc(2026, 11, 16)).toJson(),
              current.next(DateTime.utc(2026, 11, 16)).toJson(),
            );
            expect(input['recurrence'], rule);
          }

          check(created.data);
          check(
            (await store.command(id, 'task.edited', {'schedule': input})).data,
          );
          final completed = await store.complete(
            id,
            completionInstant: DateTime.utc(2026, 11, 16, 12),
          );
          check(completed.data['successor'] as Map);

          expect(TaskSchedule.fromJson(input).toJson()['recurrence'], rule);
        }
      }
    } finally {
      await store.close();
      await root.delete(recursive: true);
    }
  });

  test(
    'a text Save that also changes Repeat persists supported separators',
    () async {
      final root = await Directory.systemTemp.createTemp('separator-text-');
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final store = await TaskStore.open(
        LocalLogFolder('${root.path}/logs'),
        '${root.path}/profile',
        textEngine: engine,
      );
      try {
        final user = const Uuid().v4(), task = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Example'});
        String seed(String text) =>
            sha256.convert(engine.seedText(text).bytes).toString();
        await store.command(task, 'task.createdWithText', {
          'title': 'Example',
          'description': '',
          'assignee': user,
          'tags': <String>[],
          'text': {
            'codec': 'yrs-v1',
            'adapter': 1,
            'seeds': {'title': seed('Example'), 'description': seed('')},
          },
        });
        final capture = await store.captureTaskText(task);
        final session = TaskTextSession(capture);
        try {
          // Title and Repeat in one Save is a task.textEdited, not task.edited.
          session.replace('title', 'Example 2');
          final saved = await TextSaveCommand(store, session).save(
            fields: {
              'schedule': {
                'dueDate': '2026-11-16',
                'recurrence': 'every week on Monday,Thursday',
              },
            },
            tags: const [],
            observedTagRefs: const {},
          );
          final event = LogEvent.decode(saved.receipt!.raw);
          expect(event.type, 'task.textEdited');
          final schedule = Map<String, dynamic>.from(
            event.data['schedule'] as Map,
          );
          expect(schedule['recurrence'], 'every week on Monday, Thursday');
          stable.TaskSchedule.fromJson(schedule);
          final row = store.rows.singleWhere((r) => r['id'] == task);
          expect(
            (row['schedule'] as Map)['recurrence'],
            'every week on Monday, Thursday',
          );
        } finally {
          session.cancel();
        }
      } finally {
        await store.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
