import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/activity_log.dart';
import 'package:tandemlog/application/activity_values.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import '../integration_test/native_text_fixtures.dart';

const _milk = FoodDetails(
  name: 'Synthetic milk',
  brand: 'Synthetic dairy',
  location: 'Fridge',
  expiry: '2027-01-10',
  estimated: null,
);

String _lines(ActivityDescription d) =>
    [?d.subject, ...d.changes.map((c) => c.line)].join('\n');

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('activity-values-');
    addTearDown(() => root.delete(recursive: true));
  });

  Future<(TaskStore, FoodStore)> open(String data, String name) async {
    await Directory(data).create(recursive: true);
    final tasks = await openNativeFixtureStore(
      LocalLogFolder(data),
      '${root.path}/$name',
      nativeLibraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    final food = await FoodStore.openUnified(tasks.unified!);
    addTearDown(() async {
      await food.close();
      await tasks.close();
    });
    return (tasks, food);
  }

  List<String> describeAll(TaskStore store, {bool text = false}) {
    final snapshot = store.unified!.snapshot;
    final values = ActivityValues(snapshot, textAt: store.textFieldsAt);
    return [
      for (final e in activityEntries(snapshot).reversed)
        if (!e.types.every((t) => t.startsWith('writer.')))
          '${e.summary}\n${_lines(values.describe(e, text: text))}'.trim(),
    ];
  }

  test('values: names, assignee, old → new food and native title', () async {
    final (tasks, food) = await open('${root.path}/data', 'a');
    final person = const Uuid().v4(), task = const Uuid().v4();
    await tasks.command(person, 'user.created', {'name': 'Synthetic Lee'});
    await tasks.createNativeFixtureTask(task, {
      'title': 'Buy milk',
      'description': '',
      'assignee': person,
    });
    await tasks.editNativeFixtureTask(task, {'title': 'Buy oat milk'});
    await food.add(_milk, 1);
    final id = food.state.containers.single.id;
    await food.changeDetails(
      [id],
      const FoodDetails(
        name: 'Synthetic oat milk',
        brand: 'Synthetic dairy',
        location: 'Freezer',
        expiry: '2027-01-10',
        estimated: null,
      ),
      ['name', 'location'],
    );
    final rows = describeAll(tasks);
    expect(rows, [
      'User added\nSynthetic Lee',
      'Task added\nBuy milk\nAssignee: Synthetic Lee',
      // Rows do not replay shared text; details do.
      'Task edited\nTitle: changed',
      'Food added\nSynthetic milk (Synthetic dairy)',
      'Food edited\nSynthetic oat milk (Synthetic dairy)\n'
          'Name: Synthetic milk → Synthetic oat milk\n'
          'Location: Fridge → Freezer',
    ]);
    expect(
      describeAll(tasks, text: true)[2],
      'Task edited\nTitle: Buy milk → Buy oat milk',
    );
    // Long notes show the changed part with context, not two equal prefixes.
    final notes = List.generate(6, (i) => '- [ ] synthetic item $i').join('\n');
    await tasks.editNativeFixtureTask(task, {'description': notes});
    await tasks.editNativeFixtureTask(task, {
      'description': notes.replaceFirst('item 4', 'item four'),
    });
    await tasks.complete(
      task,
      localZoneId: 'UTC',
      completionInstant: DateTime.utc(2030, 5, 10),
    );
    final last = describeAll(tasks, text: true).reversed.take(3).toList();
    expect(last[0], 'Task completed');
    expect(
      last[1],
      'Task edited\nNotes: … [ ] synthetic item 4 ↵ - [ ] syn… → '
      '… [ ] synthetic item four ↵ - [ ] syn…',
    );
    expect(last[2], startsWith('Task edited\nNotes: none → - [ ] synthetic'));
  });

  test(
    'a captured task is named once; a deleted task keeps its name',
    () async {
      final (tasks, _) = await open('${root.path}/data', 'a');
      final person = const Uuid().v4();
      await tasks.command(person, 'user.created', {'name': 'Synthetic Lee'});
      // Capture positions a task among existing ones with a second effect.
      await tasks.createTasks({const Uuid().v4(): 'Synthetic first'}, person);
      final id = const Uuid().v4();
      final result = await tasks.createTasks({
        id: 'Synthetic captured',
      }, person);
      expect(result.succeeded, isTrue);
      await tasks.command(id, 'task.deleted', {});
      final rows = describeAll(tasks, text: true);
      // That positioning effect is not a second item.
      expect(rows, contains(startsWith('Task added\nSynthetic captured')));
      expect(rows.where((r) => r.contains('×')), isEmpty);
      expect(rows.last, 'Task deleted\nSynthetic captured');
    },
  );

  test('device renames show old name → new name', () async {
    final (tasks, _) = await open('${root.path}/data', 'a');
    final history = tasks.unified!;
    await history.renameDevice('Synthetic tablet');
    await history.renameDevice('Synthetic kitchen tablet');
    final snapshot = history.snapshot;
    final values = ActivityValues(snapshot);
    final renames = [
      for (final e in activityEntries(snapshot).reversed)
        if (e.types.contains('writer.named')) _lines(values.describe(e)),
    ];
    expect(renames, [
      'Name: Unnamed device → Synthetic tablet',
      'Name: Synthetic tablet → Synthetic kitchen tablet',
    ]);
  });

  test(
    'a concurrent edit of the same field shows only the new value',
    () async {
      final a = '${root.path}/a-data', b = '${root.path}/b-data';
      final (tasksA, foodA) = await open(a, 'a');
      await foodA.add(_milk, 1);
      final id = foodA.state.containers.single.id;
      Future<void> sync(String from, String to) async {
        await Directory(to).create(recursive: true);
        for (final file in Directory(from).listSync().whereType<File>()) {
          final target = File('$to/${file.uri.pathSegments.last}');
          if (!target.existsSync() || target.lengthSync() < file.lengthSync()) {
            await file.copy(target.path);
          }
        }
      }

      await sync(a, b);
      final (_, foodB) = await open(b, 'b');
      expect(foodB.state.containers.single.id, id);
      // Offline from each other: each device moves the same container.
      await foodA.changeDetails(
        [id],
        const FoodDetails(name: 'x', location: 'Pantry', estimated: null),
        ['location'],
      );
      await foodB.changeDetails(
        [id],
        const FoodDetails(name: 'x', location: 'Counter', estimated: null),
        ['location'],
      );
      // A later edit of another field after both still knows the old name.
      await foodB.changeDetails(
        [id],
        const FoodDetails(name: 'x', brand: 'Store brand', estimated: null),
        ['brand'],
      );
      await sync(b, a);
      await tasksA.refresh();
      await foodA.refresh();
      final rows = describeAll(tasksA);
      expect(rows.where((r) => r.contains('Location')).toSet(), {
        'Food location changed\nSynthetic milk (Synthetic dairy)\n'
            'Location: Pantry',
        'Food location changed\nSynthetic milk (Synthetic dairy)\n'
            'Location: Counter',
      });
      expect(
        rows.last,
        'Food edited\nSynthetic milk (Store brand)\n'
        'Brand: Synthetic dairy → Store brand',
      );
      // An edit after both concurrent moves observed them: old is ambiguous.
      await foodA.changeDetails(
        [id],
        const FoodDetails(name: 'x', location: 'Shelf', estimated: null),
        ['location'],
      );
      expect(
        describeAll(tasksA).last,
        'Food location changed\nSynthetic milk (Store brand)\nLocation: Shelf',
      );
    },
  );
}
