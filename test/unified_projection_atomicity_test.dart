import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'unified_conversion_test.dart' as fixture;
import 'unified_history_test.dart' as commands;

void main() {
  test(
    'all attached projections publish after one SQL admission commit',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'unified-projection-atomicity-',
      );
      final folder = commands.FaultFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final profile = await LocalProfileDatabase.open('${root.path}/profile');
      UnifiedHistory? app;
      TaskStore? tasks;
      FoodStore? food;
      try {
        final p = fixture.plan(), cv = p.convert(fixture.ack(p));
        await folder.create(
          'tandemlog-space.json',
          Uint8List.fromList(utf8.encode(cv.manifest.encode())),
        );
        for (final e in cv.files.entries) {
          await folder.create(e.key, Uint8List.fromList(e.value));
        }
        profile.transaction(
          () => profile.database.execute(
            'INSERT INTO protected_settings VALUES (1,?,?)',
            [
              fixture.owner,
              utf8.encode(
                jsonEncode({'writer': fixture.owner, 'appearance': 'system'}),
              ),
            ],
          ),
        );
        app = await UnifiedHistory.open(
          folder,
          profile: profile,
          writer: fixture.owner,
        );
        tasks = await TaskStore.openUnified(app);
        food = await FoodStore.openUnified(app);
        final beforeTasks = tasks.rows.map(canonicalDataJson).toList(),
            beforeFood = food.state.containers
                .map((c) => canonicalDataJson(c.toJson()))
                .toList(),
            beforeRevision = app.snapshot.revision;
        final attachment = Object();
        var fail = false;
        await profile.serialize(() async {
          app!.attachProjectionInProfileQueue(attachment, (snapshot) {
            if (fail && snapshot.records.any((r) => r.sequence > 5)) {
              throw FormatFailure('Synthetic projection failure after staging');
            }
            return () {};
          });
        });
        fail = true;
        await expectLater(
          app.appendAtomic([
            commands.taskBuilder(commands.newTask),
            commands.foodBuilder(),
          ]),
          throwsA(isA<FormatFailure>()),
        );
        expect(tasks.rows.map(canonicalDataJson).toList(), beforeTasks);
        expect(
          food.state.containers
              .map((c) => canonicalDataJson(c.toJson()))
              .toList(),
          beforeFood,
        );
        expect(app.snapshot.revision, beforeRevision);
        expect(app.hasPending, isTrue);
        final exact = app.pendingRecords.map((r) => r.encode()).toList();
        await profile.serialize(() async {
          app!.detachProjectionInProfileQueue(attachment);
        });
        await app.recoverPrepared();
        expect(app.hasPending, isFalse);
        expect(tasks.rows.any((r) => r['id'] == commands.newTask), isTrue);
        expect(
          food.state.containers.any((c) => c.id == commands.newFood),
          isTrue,
        );
        expect(
          app.snapshot.records
              .where((r) => r.sequence > 5)
              .map((r) => r.encode())
              .toList(),
          exact,
        );
      } finally {
        await food?.close();
        await tasks?.close();
        await app?.close();
        await profile.close();
        await root.delete(recursive: true);
      }
    },
  );
}
