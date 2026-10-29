import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

/// The close-time seal compares the live and validator Task cache rows
/// exactly instead of digesting both: equality must imply identical digest
/// input bytes, and every case the old digest comparison refused stays
/// refused.
void main() {
  List<List<List<Object?>>> rows(Object? value) => [
    [
      ['id', 1, 'text', null],
      [
        'id2',
        value,
        Uint8List.fromList([1, 2, 3]),
        2.5,
      ],
    ],
    [],
  ];

  String encoded(List<List<List<Object?>>> r) =>
      utf8.decode(JsonUtf8Encoder().convert({'rows': r, 'ready': <String>[]}));

  test('equal rows are equal, and encode identically', () {
    for (final value in <Object?>[
      null,
      0,
      -1,
      1 << 40,
      0.5,
      0.0,
      'É😀\n"\\',
      Uint8List.fromList([0, 255]),
    ]) {
      final a = rows(value),
          b = rows(value is Uint8List ? Uint8List.fromList(value) : value);
      expect(sameTaskCacheRows(a, b), isTrue, reason: '$value');
      expect(encoded(a), encoded(b));
    }
  });

  test('anything the digest would distinguish is different', () {
    final pairs = <(Object?, Object?)>[
      (1, 1.0),
      (0.0, -0.0),
      (double.nan, double.nan),
      ('1', 1),
      (null, ''),
      (Uint8List.fromList([1]), Uint8List.fromList([2])),
      (Uint8List.fromList([1]), Uint8List.fromList([1, 0])),
      ('a', 'b'),
    ];
    for (final (x, y) in pairs) {
      expect(sameTaskCacheRows(rows(x), rows(y)), isFalse, reason: '$x/$y');
    }
    // Shape differences: an extra row, column or table.
    final base = rows(1);
    expect(sameTaskCacheRows(base, [base[0]]), isFalse);
    expect(
      sameTaskCacheRows(base, [
        [
          ...base[0],
          ['extra'],
        ],
        [],
      ]),
      isFalse,
    );
    expect(
      sameTaskCacheRows(base, [
        [
          base[0][0],
          [...base[0][1], null],
        ],
        [],
      ]),
      isFalse,
    );
  });

  for (final tamper in [false, true]) {
    test('close seals only an unchanged live cache; tampered=$tamper', () async {
      final root = await Directory.systemTemp.createTemp('task-seal-compare-');
      addTearDown(() => root.delete(recursive: true));
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final profilePath = '${root.path}/profile';
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      addTearDown(engine.dispose);
      final store = await TaskStore.open(
        folder,
        profilePath,
        textEngine: engine,
      );
      final user = const Uuid().v4(), task = const Uuid().v4();
      await store.command(user, 'user.created', {'name': 'Lee'});
      expect(
        (await store.createTasks({task: 'Seal me'}, user)).succeeded,
        isTrue,
      );
      if (tamper) {
        // An unobserved change to the live disposable projection.
        store.db.execute(
          "UPDATE ${store.tables.views} SET raw=json_set(raw,'\$.title','x') WHERE id=?",
          [task],
        );
      }
      await store.close();
      final profile = await LocalProfileDatabase.open(profilePath);
      try {
        final proofs = profile.database.select(
          "SELECT 1 FROM profile_metadata WHERE key LIKE 'app5.task.cache.%'",
        );
        expect(proofs, hasLength(tamper ? 0 : 1));
      } finally {
        await profile.close();
      }
    });
  }
}
