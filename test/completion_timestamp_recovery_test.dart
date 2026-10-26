import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/timed_view.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:uuid/uuid.dart';
import '../integration_test/native_text_fixtures.dart';

class _FaultCompletionFolder extends LocalLogFolder {
  _FaultCompletionFolder(super.location);
  int? keep;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    final count = keep;
    keep = null;
    if (count == null) return super.append(name, bytes);
    if (count > 0) {
      await super.append(
        name,
        Uint8List.fromList(bytes.take(math.min(count, bytes.length)).toList()),
      );
    }
    throw const FileSystemException('Synthetic uncertain completion append');
  }
}

void main() {
  for (final keep in [0, 37, 1000000]) {
    for (final restart in [false, true]) {
      test(
        'timestamp receipt is exact after $keep-byte fault, restart=$restart',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'completion-instant-recovery-',
          );
          final folder = _FaultCompletionFolder(
            (await Directory('${root.path}/shared').create()).path,
          );
          final profile = '${root.path}/profile';
          TaskStore? store;
          try {
            store = await openNativeFixtureStore(
              folder,
              profile,
              nativeLibraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
            );
            final user = const Uuid().v4(), id = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            await store.createNativeFixtureTask(id, {
              'title': 'Repeat',
              'description': '',
              'assignee': user,
              'schedule': {
                'dueDate': '2030-05-10',
                'recurrence': 'every day when done',
              },
            });
            var samples = 0;
            OperationReceipt? receipt;
            folder.keep = keep;
            await expectLater(
              store.complete(
                id,
                observeCompletionTime: () {
                  samples++;
                  return ViewTime(
                    instant: DateTime.utc(2030, 5, 10, 23, 59, 59, 123, 456),
                    localZoneId: 'America/Chicago',
                    localOffset: const Duration(hours: -5),
                  );
                },
                onPrepared: (value) => receipt = value,
              ),
              throwsA(anything),
            );
            expect(samples, 1);
            expect(receipt, isNotNull);
            final raw = receipt!.raw;
            expect(
              LogEvent.decode(raw).data['completedInstant'],
              '2030-05-10T23:59:59.123456Z',
            );
            if (restart) {
              await store.close();
              store = null;
              store = await openNativeFixtureStore(
                folder,
                profile,
                nativeLibraryPath:
                    Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
              );
              expect(store.visibleTaskRow(id)!['completed'], keep == 1000000);
              expect(store.pendingTextOperations, isEmpty);
              if (keep != 1000000) {
                expect(store.visibleTaskRow(id)!['completedInstant'], isNull);
                // New explicit intent after restart samples a NEW actual instant,
                // even when the clock went backwards. It never revives a draft.
                final fresh = await store.complete(
                  id,
                  completionInstant: DateTime.utc(2029, 1, 1, 12),
                  localZoneId: 'UTC',
                );
                expect(
                  fresh.data['completedInstant'],
                  '2029-01-01T12:00:00.000000Z',
                );
                expect(fresh.encode(), isNot(raw));
              }
            } else {
              final saved = await store.retryTextOperation(receipt!);
              expect(saved.encode(), raw);
              expect(samples, 1);
              final actions = LineSplitter.split(
                utf8.decode(await folder.read('${store.writer}.applog')),
              ).map(UnifiedRecord.decode);
              final completions = actions
                  .expand((a) => a.effects)
                  .map((e) => e.task)
                  .whereType<LogEvent>()
                  .where((e) => isTaskCompletion(e.type))
                  .toList();
              expect(completions, hasLength(1));
              expect(completions.single.encode(), raw);
            }
            final before = jsonEncode(store.rows);
            await store.close();
            store = null;
            store = await openNativeFixtureStore(
              folder,
              profile,
              nativeLibraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
            );
            expect(jsonEncode(store.rows), before);
            expect(samples, 1);
          } finally {
            await store?.close();
            await root.delete(recursive: true);
          }
        },
      );
    }
  }
}
