import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/food_import.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'food_import_test.dart' as imports;
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'unified_conversion_test.dart' as fixture;
import 'unified_history_test.dart' show FaultFolder;

void main() {
  test(
    'Food commands and legacy Undo use one app receipt and recover exact bytes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'unified-food-adapter-',
      );
      final folder = FaultFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final profile = await LocalProfileDatabase.open('${root.path}/profile');
      UnifiedHistory? app;
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
        food = await FoodStore.openUnified(app);
        expect(food.state.containers.single.details.name, 'Rice');
        final old = fixture.foodHistory().first;
        await food.undoOperations([old]);
        expect(food.state.containers, isEmpty);
        expect(food.lastPreparedRecords.single.unified, isTrue);
        expect(food.lastPreparedRecords.single.writer, fixture.owner);
        expect(
          food.lastPreparedRecords.single.operation.undoOwner,
          fixture.owner,
        );
        await app.renameDevice('Phone');
        await food.add(const FoodDetails(name: 'New beans'), 1);
        final added = food.state.containers.single;
        expect(added.details.name, 'New beans');
        await food.changeDetails(
          [added.id],
          const FoodDetails(name: 'Edited beans'),
          ['name'],
        );
        expect(food.state.containers.single.details.name, 'Edited beans');
        final saved = food.lastPreparedRecords.single;
        await food.undoOperations([saved]);
        expect(food.state.containers.single.details.name, 'New beans');
        final before = await folder.read(unifiedLogName(fixture.owner));
        folder.cut = 60;
        await expectLater(
          food.remove([added.id]),
          throwsA(isA<FileSystemException>()),
        );
        final prepared = app.pendingRecords.map((r) => r.encode()).toList();
        expect(prepared, hasLength(1));
        expect(food.hasPreparedAppend, isTrue);
        await food.close();
        food = null;
        await app.close();
        app = null;
        app = await UnifiedHistory.open(
          folder,
          profile: profile,
          writer: fixture.owner,
        );
        food = await FoodStore.openUnified(app);
        await food.recoverPrepared();
        expect(food.hasPreparedAppend, isFalse);
        expect(food.state.containers.single.deleted, isTrue);
        expect(
          (await folder.read(
            unifiedLogName(fixture.owner),
          )).sublist(before.length),
          utf8.encode('${prepared.single}\n'),
        );
        expect(
          profile.database.select('SELECT * FROM protected_food_intents'),
          isEmpty,
        );
        expect(
          profile.database.select('SELECT * FROM protected_writer_guards'),
          isEmpty,
        );
        expect(
          (await folder.list())
              .map((e) => e.name)
              .where((n) => n.endsWith('.jsonl') || n.endsWith('.foodlog')),
          isEmpty,
        );
      } finally {
        await food?.close();
        await app?.close();
        await profile.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'completed legacy Food import remains recognized after full conversion',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'unified-legacy-import-',
      );
      final folder = FaultFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final profile = await LocalProfileDatabase.open('${root.path}/profile');
      FoodStore? food;
      UnifiedHistory? app;
      try {
        await folder.create(
          'tandemlog-space.json',
          Uint8List.fromList(
            utf8.encode(jsonEncode({'v': 3, 'id': imports.space})),
          ),
        );
        profile.transaction(
          () => profile.database.execute(
            'INSERT INTO protected_settings VALUES (1,?,?)',
            [
              imports.installation,
              utf8.encode(
                jsonEncode({
                  'writer': imports.installation,
                  'appearance': 'system',
                }),
              ),
            ],
          ),
        );
        food = await FoodStore.open(
          folder,
          profile: profile,
          installationWriter: imports.installation,
          space: imports.space,
        );
        final plan = imports.plan();
        final committed = await food.commitImport(plan);
        expect(committed.status, FoodImportStatus.committed);
        final records = food.lastPreparedRecords
            .map((r) => r.encode())
            .toList();
        await food.close();
        food = null;
        final sources = {
          for (final i in await folder.list())
            if (i.name.endsWith('.foodlog')) i.name: await folder.read(i.name),
        };
        final cutover = UnifiedCutoverPlan.inspect(
          space: imports.space,
          owners: {imports.installation},
          participants: {imports.installation},
          sources: sources,
          hasUnresolvedPreparedWrites: false,
        );
        final cv = cutover.convert([
          CutoverAcknowledgement(
            imports.installation,
            cutover.sourceDigest,
            quiesced: true,
            pendingResolved: true,
          ),
        ]);
        for (final e in cv.files.entries) {
          await folder.create(e.key, Uint8List.fromList(e.value));
        }
        await folder
            .file('tandemlog-space.json')
            .writeAsString(cv.manifest.encode(), flush: true);
        app = await UnifiedHistory.open(
          folder,
          profile: profile,
          writer: imports.installation,
        );
        food = await FoodStore.openUnified(app);
        final before = await folder.read(unifiedLogName(imports.installation));
        final inspected = await food.dryRunImport(plan);
        expect(inspected.status, FoodImportStatus.committed);
        expect(inspected.writer, committed.writer);
        expect(
          (await food.commitImport(plan)).status,
          FoodImportStatus.committed,
        );
        expect(await folder.read(unifiedLogName(imports.installation)), before);
        expect(
          app.snapshot.effects
              .where((e) => e.food != null)
              .map((e) => e.raw)
              .toList(),
          records,
        );
        // A new import uses the current installation's common global allocator.
        final next = imports.plan(
          importId: imports.otherNamespace,
          source: List.filled(64, 'b').join(),
          count: 1,
        );
        expect(
          (await food.commitImport(next)).status,
          FoodImportStatus.committed,
        );
        expect(food.lastPreparedRecords.single.writer, imports.installation);
        expect(app.hasPending, isFalse);
        final exact = await folder.read(unifiedLogName(imports.installation));
        final saved = profile.database
            .select(
              "SELECT key,value FROM profile_metadata WHERE key LIKE 'food.import.v1.%attempt.%'",
            )
            .first;
        final key = saved['key'] as String, raw = saved['value'] as String;
        final damaged = jsonDecode(raw) as Map<String, dynamic>;
        ((damaged['records'] as List).first as Map)['hash'] = '0' * 64;
        profile.transaction(
          () => profile.database.execute(
            'UPDATE profile_metadata SET value=? WHERE key=?',
            [jsonEncode(damaged), key],
          ),
        );
        await expectLater(app.refresh(), throwsException);
        await expectLater(app.renameDevice('blocked'), throwsException);
        expect(await folder.read(unifiedLogName(imports.installation)), exact);
        profile.transaction(
          () => profile.database.execute(
            'UPDATE profile_metadata SET value=? WHERE key=?',
            [raw, key],
          ),
        );
        await app.refresh();
        profile.transaction(
          () => profile.database.execute(
            'DELETE FROM protected_food_import_witnesses WHERE space=?',
            [imports.space],
          ),
        );
        await expectLater(app.refresh(), throwsException);
        profile.transaction(
          () => profile.database.execute(
            'INSERT INTO protected_food_import_witnesses VALUES (?,1)',
            [imports.space],
          ),
        );
        await app.refresh();
      } finally {
        await food?.close();
        await app?.close();
        await profile.close();
        await root.delete(recursive: true);
      }
    },
  );
}
