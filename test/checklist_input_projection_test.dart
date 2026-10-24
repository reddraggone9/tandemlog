import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/checklist.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/text/recurring_text.dart';

void main() {
  test(
    'indexed checklist matches full oracle across copies, moves, tombstones, '
    'Undo, prefixes and append generations',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'checklist-input-oracle-',
      );
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      TaskStore? store;
      try {
        final shared = await Directory('${root.path}/shared').create();
        final s = store = await TaskStore.open(
          LocalLogFolder(shared.path),
          '${root.path}/profile',
          textEngine: engine,
        );
        final user = const Uuid().v4(), parent = const Uuid().v4();
        await s.command(user, 'user.created', {'name': 'Synthetic'});
        expect(
          (await s.createTasks({
            parent: 'Native parent',
            for (var i = 0; i < 12; i++) const Uuid().v4(): 'Unrelated task $i',
          }, user)).succeeded,
          isTrue,
        );
        await s.edit(
          parent,
          {
            'schedule': {'dueDate': '2030-05-01', 'recurrence': 'every day'},
          },
          tags: [],
          observedTagRefs: {},
        );
        final first = const Uuid().v4(), second = const Uuid().v4();
        await s.addChecklistItem(parent, 'First', id: first);
        await s.addChecklistItem(parent, 'Second', id: second);
        var input = RecurringTextInput.fromCanonical(
          s.unified!.snapshot.tasks.map((e) => e.canonicalRaw!),
        );
        var previousLength = input.history.length;
        final parents = <String>{parent};
        void oracle() {
          final all = s.unified!.snapshot.tasks;
          final oldIds = input.history.map((e) => e.id).toSet();
          final added = all.where((e) => !oldIds.contains(e.id));
          input =
              input.appendedCanonical(added.map((e) => e.canonicalRaw!)) ??
              RecurringTextInput.fromCanonical(all.map((e) => e.canonicalRaw!));
          for (final id in parents) {
            expect(input.checklist(id), projectChecklist(all.toList(), id));
          }
          for (var end = previousLength; end <= all.length; end++) {
            final prefix = all.take(end).toList();
            final partial = RecurringTextInput.fromCanonical(
              prefix.map((e) => e.canonicalRaw!),
            );
            for (final id in parents) {
              expect(
                partial.checklist(id),
                projectChecklist(prefix.toList(), id),
              );
            }
          }
          previousLength = all.length;
        }

        oracle();
        final moved = await s.moveChecklistItem(second, first);
        oracle();
        final beforeToggle = s.currentView;
        final decoded = s.displaySnapshotRowsDecoded;
        final unrelated = beforeToggle.rows.firstWhere(
          (row) => row['kind'] == 'task' && row['id'] != parent,
        );
        final toggled = await s.setChecklistCompleted(first, true);
        expect(s.displaySnapshotRowsDecoded - decoded, 1);
        expect(
          identical(
            s.currentView.rows.singleWhere(
              (row) => row['id'] == unrelated['id'],
            ),
            unrelated,
          ),
          isTrue,
        );
        expect(identical(s.currentView.users, beforeToggle.users), isTrue);
        expect(s.currentView.rows, s.rows);
        expect(
          identical(
            s.currentView.rows.singleWhere((row) => row['id'] == parent),
            beforeToggle.rows.singleWhere((row) => row['id'] == parent),
          ),
          isFalse,
        );
        oracle();
        final removed = await s.deleteChecklistItem(second);
        oracle();
        await s.undoOperations([removed.id, toggled.id]);
        oracle();
        final completed = await s.complete(
          parent,
          completionDay: DateTime(2030, 5, 1),
        );
        final completion = s.unified!.snapshot.tasks.lastWhere(
          (e) => e.type == 'task.completedWithChecklist',
        );
        final child = (completion.data['successor'] as Map)['id'] as String;
        parents.add(child);
        oracle();
        final copied = s.checklistItems(child).first['id'] as String;
        await s.setChecklistCompleted(copied, true);
        oracle();
        await s.undoOperations([completed.id]);
        oracle();
        final deleted = await s.deleteChecklistItem(first);
        oracle();
        await s.undoOperations([deleted.id]);
        oracle();
        // Retain malformed cross-entity retractions: admission rejects them
        // elsewhere, but selection must preserve the pure projector's meaning.
        final otherWriter = const Uuid().v4();
        final foreign = LogEvent.decode(
          LogEvent(
            s.space,
            otherWriter,
            1,
            EventClock(input.history.last.clock.value + BigInt.one),
            user,
            'task.operationUndone',
            {'operation': moved.id},
          ).encode(previousHash: eventGenesisHash(s.space, otherWriter)),
        );
        final extended = input.appendedCanonical([foreign.canonicalRaw!])!;
        expect(
          extended.checklist(parent),
          projectChecklist([...input.history, foreign], parent),
        );
        expect(input.checklist(parent).map((e) => e['id']), [second, first]);
        expect(extended.checklist(parent).map((e) => e['id']), [first, second]);
        // Colliding non-checklist creations remain corruption.
        final collisionWriter = const Uuid().v4();
        final collision = LogEvent.decode(
          LogEvent(
            s.space,
            collisionWriter,
            1,
            EventClock(foreign.clock.value + BigInt.one),
            first,
            'user.created',
            {'name': 'Collision'},
          ).encode(previousHash: eventGenesisHash(s.space, collisionWriter)),
        );
        final invalid = RecurringTextInput.fromCanonical([
          ...input.history.map((e) => e.canonicalRaw!),
          collision.canonicalRaw!,
        ]);
        expect(() => invalid.checklist(parent), throwsA(isA<FormatFailure>()));
        expect(
          () => projectChecklist(invalid.history.toList(), parent),
          throwsA(isA<FormatFailure>()),
        );
      } finally {
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
