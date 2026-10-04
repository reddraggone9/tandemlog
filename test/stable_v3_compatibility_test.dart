import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';

const _fixture = 'test/fixtures/stable-v3-2026.10.0';
const _space = '11111111-1111-4111-8111-111111111111';
const _writers = [
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
];
const _hashes = {
  '22222222-2222-4222-8222-222222222222.jsonl':
      '288c5695f760dc2abc4b4815c42b80bef3052b4f769086c21b3c2b66eebdbd5e',
  '33333333-3333-4333-8333-333333333333.jsonl':
      'a358e34769fc7d58a909dba4e7ff12d9285e623e95198f2229732c5a4d248dde',
};

void main() {
  final expected = jsonDecode(
    File('$_fixture/expected-rows.json').readAsStringSync(),
  );

  test(
    'first stable v3 bytes, identities, clocks and event meanings stay frozen',
    () {
      final types = <String>{};
      for (final writer in _writers) {
        final bytes = File('$_fixture/$writer.jsonl').readAsBytesSync();
        expect(sha256.convert(bytes).toString(), _hashes['$writer.jsonl']);
        final lines = utf8.decode(bytes).split('\n')..removeLast();
        var previous = eventGenesisHash(_space, writer);
        BigInt? clock;
        for (var i = 0; i < lines.length; i++) {
          final event = LogEvent.decode(lines[i]);
          expect(event.encode(), lines[i]);
          expect(event.space, _space);
          expect(event.writer, writer);
          expect(event.sequence, i + 1);
          expect(event.previousHash, previous);
          expect(event.clock.toJson(), jsonDecode(lines[i])['clock']);
          if (clock != null) expect(event.clock.value, greaterThan(clock));
          previous = event.hash!;
          clock = event.clock.value;
          types.add(event.type);
        }
      }
      expect(types, {
        'user.created',
        'task.created',
        'task.edited',
        'task.moved',
        'task.deleted',
        'task.completed',
        'task.completionUndone',
        'task.recurringCompletionUndone',
        'task.operationUndone',
      });
    },
  );

  for (final arrival in [_writers, _writers.reversed.toList()]) {
    test(
      'frozen history converges after arrival $arrival and cache rebuild',
      () async {
        final root = await Directory.systemTemp.createTemp('stable-v3-');
        TaskStore? store;
        try {
          final shared = await Directory('${root.path}/shared').create();
          await File(
            '$_fixture/tandemlog-space.json',
          ).copy('${shared.path}/tandemlog-space.json');
          final folder = LocalLogFolder(shared.path);
          final profile = '${root.path}/profile';
          store = await TaskStore.open(folder, profile);
          for (final writer in arrival) {
            await File(
              '$_fixture/$writer.jsonl',
            ).copy('${shared.path}/$writer.jsonl');
            await store.refresh();
          }
          expect(store.rows, expected);
          expect(await store.refresh(), isFalse);
          await store.verifyHistory();
          expect(store.lastHistoryVerification!.checkedRecordCount, 22);
          final identity = store.writer;
          await store.close();
          store = await TaskStore.open(folder, profile);
          expect(store.writer, identity);
          expect(store.rows, expected);
          expect(store.readFiles, 0);
          await store.close();
          store = await TaskStore.open(folder, '${root.path}/fresh-profile');
          expect(store.writer, isNot(identity));
          expect(store.rows, expected);
          for (final writer in _writers) {
            expect(
              await folder.read('$writer.jsonl'),
              File('$_fixture/$writer.jsonl').readAsBytesSync(),
            );
          }
        } finally {
          await store?.close();
          await root.delete(recursive: true);
        }
      },
    );
  }

  test(
    'new writer extends frozen v3 without rewriting prior history',
    () async {
      final root = await Directory.systemTemp.createTemp('stable-v3-write-');
      TaskStore? store;
      try {
        final shared = await Directory('${root.path}/shared').create();
        for (final name in ['tandemlog-space.json', ..._hashes.keys]) {
          await File('$_fixture/$name').copy('${shared.path}/$name');
        }
        final folder = LocalLogFolder(shared.path);
        store = await TaskStore.open(
          folder,
          '${root.path}/profile',
          now: () => DateTime.utc(2026, 2, 1, 12),
        );
        const entity = '99999999-9999-4999-8999-999999999999';
        final event = await store.command(entity, 'task.edited', {
          'description': 'New stable-reader work',
        });
        expect(event.sequence, 1);
        expect(
          event.clock.value,
          greaterThan(BigInt.parse('1769947200000000021')),
        );
        expect(
          store.rows.singleWhere((row) => row['id'] == entity)['inbox'],
          isFalse,
        );
        for (final writer in _writers) {
          expect(
            await folder.read('$writer.jsonl'),
            File('$_fixture/$writer.jsonl').readAsBytesSync(),
          );
        }
        final before = store.rows;
        await store.close();
        store = await TaskStore.open(folder, '${root.path}/replay');
        expect(store.rows, before);
      } finally {
        await store?.close();
        await root.delete(recursive: true);
      }
    },
  );
}
