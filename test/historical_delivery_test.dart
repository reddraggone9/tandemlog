import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/domain/event.dart';

Future<Directory> copyFolder(
  Directory from,
  String to, {
  Set<String> omit = const {},
}) async {
  final result = await Directory(to).create();
  await for (final file in from.list()) {
    if (file is File && !omit.contains(file.uri.pathSegments.last)) {
      await file.copy('${result.path}/${file.uri.pathSegments.last}');
    }
  }
  return result;
}

void main() {
  test(
    'review: historical source and marker arrive after cross-writer Undo',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'review-historical-order-',
      );
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final stores = <TaskStore>[];
      Future<TaskStore> open(Directory folder, String profile) async {
        final s = await TaskStore.open(
          LocalLogFolder(folder.path),
          '${root.path}/$profile',
          textEngine: engine,
        );
        stores.add(s);
        return s;
      }

      try {
        final fa = await Directory('${root.path}/a').create(),
            a = await open(await Directory('${root.path}/a').create(), 'pa');
        final user = const Uuid().v4(),
            parent = const Uuid().v4(),
            child = const Uuid().v5(parent, 'successor');
        await a.command(user, 'user.created', {'name': 'Synthetic'});
        await a.command(parent, 'task.created', {
          'title': 'Parent',
          'description': '',
          'assignee': user,
          'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
        });
        final fb = await copyFolder(fa, '${root.path}/b'),
            b = await open(await Directory('${root.path}/b').create(), 'pb');
        final original = await b.complete(
          parent,
          completionDay: DateTime(2030, 5, 10),
        );
        await File(
          '${fb.path}/${b.writer}.jsonl',
        ).copy('${fa.path}/${b.writer}.jsonl');
        await a.refresh();
        await a.command(child, 'task.edited', {'title': 'Independent child'});
        await a.initializeSharedText();
        await a.reopen(parent, [original.id]);
        final fc = await copyFolder(fa, '${root.path}/c'),
            c = await open(await Directory('${root.path}/c').create(), 'pc');
        final marker = await c.complete(
          parent,
          completionDay: DateTime(2030, 6, 10),
        );
        final fd = await copyFolder(fc, '${root.path}/d'),
            d = await open(await Directory('${root.path}/d').create(), 'pd');
        await d.undoOperations([marker.id]);
        final expected = jsonEncode(d.taskSnapshot);
        final receiverFolder = await copyFolder(
          fd,
          '${root.path}/receiver',
          omit: {'${b.writer}.jsonl', '${c.writer}.jsonl'},
        );
        final receiver = await open(receiverFolder, 'pr');
        expect(
          receiver.rows.singleWhere((r) => r['id'] == parent)['completed'],
          false,
        );
        await File(
          '${fc.path}/${c.writer}.jsonl',
        ).copy('${receiverFolder.path}/${c.writer}.jsonl');
        await receiver.refresh();
        expect(
          receiver.rows.singleWhere((r) => r['id'] == parent)['completed'],
          false,
        );
        await File(
          '${fb.path}/${b.writer}.jsonl',
        ).copy('${receiverFolder.path}/${b.writer}.jsonl');
        await receiver.refresh();
        expect(jsonEncode(receiver.taskSnapshot), expected);
        final eventCount = receiver.db
            .select('SELECT count(*) AS n FROM events')
            .single['n'];
        await receiver.refresh();
        expect(
          receiver.db.select('SELECT count(*) AS n FROM events').single['n'],
          eventCount,
        );
        // Marker before original source, with no Undo: exact final convergence.
        final lateSourceFolder = await copyFolder(
          fc,
          '${root.path}/late-source',
          omit: {'${b.writer}.jsonl'},
        );
        final lateSource = await open(lateSourceFolder, 'pls');
        await File(
          '${fb.path}/${b.writer}.jsonl',
        ).copy('${lateSourceFolder.path}/${b.writer}.jsonl');
        await lateSource.refresh();
        expect(jsonEncode(lateSource.taskSnapshot), jsonEncode(c.taskSnapshot));
        // Original source before marker: marker's parent-only change leaves child exact.
        final lateMarkerFolder = await copyFolder(
          fc,
          '${root.path}/late-marker',
          omit: {'${c.writer}.jsonl'},
        );
        final lateMarker = await open(lateMarkerFolder, 'plm');
        final childBefore = jsonEncode(
          lateMarker.rows.singleWhere((r) => r['id'] == child),
        );
        await File(
          '${fc.path}/${c.writer}.jsonl',
        ).copy('${lateMarkerFolder.path}/${c.writer}.jsonl');
        await lateMarker.refresh();
        expect(jsonEncode(lateMarker.taskSnapshot), jsonEncode(c.taskSnapshot));
        expect(
          jsonEncode(lateMarker.rows.singleWhere((r) => r['id'] == child)),
          childBefore,
        );
        // A correctly chained marker with a wrong source hash is initially missing,
        // then rejected by actual ingestion when that source becomes known.
        final invalidFolder = await copyFolder(
          fc,
          '${root.path}/invalid-late-source',
          omit: {'${b.writer}.jsonl'},
        );
        final invalidData =
            jsonDecode(jsonEncode(marker.data)) as Map<String, dynamic>;
        invalidData['retainedSuccessor']['hash'] = 'f' * 64;
        final invalid = LogEvent(
          marker.space,
          marker.writer,
          marker.sequence,
          marker.clock,
          marker.entity,
          marker.type,
          invalidData,
        ).encode(previousHash: marker.previousHash!);
        await File(
          '${invalidFolder.path}/${c.writer}.jsonl',
        ).writeAsString('$invalid\n');
        final invalidReceiver = await open(invalidFolder, 'pi');
        final before = jsonEncode(invalidReceiver.taskSnapshot),
            beforeEvents = invalidReceiver.db
                .select('SELECT count(*) AS n FROM events')
                .single['n'];
        await File(
          '${fb.path}/${b.writer}.jsonl',
        ).copy('${invalidFolder.path}/${b.writer}.jsonl');
        await expectLater(
          invalidReceiver.refresh(),
          throwsA(
            isA<FormatFailure>().having(
              (e) => e.message,
              'specific historical validation',
              contains('Invalid retained historical initialization'),
            ),
          ),
        );
        expect(jsonEncode(invalidReceiver.taskSnapshot), before);
        expect(
          invalidReceiver.db
              .select('SELECT count(*) AS n FROM events')
              .single['n'],
          beforeEvents,
        );
      } finally {
        for (final s in stores.reversed) {
          await s.close();
        }
        engine.dispose();
      }
    },
  );
}
