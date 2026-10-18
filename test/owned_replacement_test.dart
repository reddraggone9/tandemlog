import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/local_durability.dart';
import 'package:tandemlog/storage/log_folder.dart';

class _UnconfirmedDurability extends LocalDurability {
  @override
  Future<void> writeAtomicDurable(File destination, List<int> bytes) async {
    await destination.writeAsBytes(bytes, flush: true);
    throw const FileSystemException('Synthetic interruption after replacement');
  }
}

void main() {
  late Directory directory;
  late LocalLogFolder folder;
  final expected = Uint8List.fromList([1, 2, 3, 4]);
  final replacement = Uint8List.fromList([5, 6]);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('owned-replacement-');
    folder = LocalLogFolder(directory.path);
    await File(
      '${directory.path}/tandemlog-space.json',
    ).writeAsBytes(expected, flush: true);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('preflight reads without creating files or changing source', () async {
    await folder.checkReplacementSupport('tandemlog-space.json', 4);
    expect(await folder.read('tandemlog-space.json'), expected);
    expect((await directory.list().toList()), hasLength(1));
    await expectLater(
      folder.checkReplacementSupport('tandemlog-space.json', 3),
      throwsFormatException,
    );
    expect(await folder.read('tandemlog-space.json'), expected);
  });

  test('checked replacement truncates and confirms exact new bytes', () async {
    await folder.replaceOwned('tandemlog-space.json', expected, replacement);
    expect(await folder.read('tandemlog-space.json'), replacement);
    expect((await directory.list().toList()), hasLength(1));
  });

  test('changed source blocks before mutation', () async {
    await expectLater(
      folder.replaceOwned(
        'tandemlog-space.json',
        Uint8List.fromList([0]),
        replacement,
      ),
      throwsA(
        isA<OwnedReplacementFailure>()
            .having((e) => e.phase, 'phase', 'source_changed')
            .having((e) => e.mayHaveChanged, 'uncertain', false),
      ),
    );
    expect(await folder.read('tandemlog-space.json'), expected);
    expect((await directory.list().toList()), hasLength(1));
  });

  test('interrupted local temporary file is preserved', () async {
    final temporary = File('${directory.path}/tandemlog-space.json.tmp');
    await temporary.writeAsBytes([9, 8, 7], flush: true);
    await expectLater(
      folder.replaceOwned('tandemlog-space.json', expected, replacement),
      throwsA(
        isA<OwnedReplacementFailure>()
            .having((e) => e.phase, 'phase', 'temporary_exists')
            .having((e) => e.mayHaveChanged, 'uncertain', false),
      ),
    );
    expect(await temporary.readAsBytes(), [9, 8, 7]);
    expect(await folder.read('tandemlog-space.json'), expected);
  });

  test(
    'unconfirmed barrier remains uncertain even with complete new bytes',
    () async {
      folder = LocalLogFolder(
        directory.path,
        durability: _UnconfirmedDurability(),
      );
      await expectLater(
        folder.replaceOwned('tandemlog-space.json', expected, replacement),
        throwsA(
          isA<OwnedReplacementFailure>()
              .having((e) => e.mayHaveChanged, 'uncertain', true)
              .having(
                (e) => e.cause,
                'original failure',
                isA<FileSystemException>(),
              ),
        ),
      );
      expect(await folder.read('tandemlog-space.json'), replacement);
    },
  );

  for (final partial in [
    <int>[],
    [5],
    [5, 6],
  ]) {
    test(
      'journal-authorized recovery preserves partial temporary $partial',
      () async {
        final temporary = File('${directory.path}/tandemlog-space.json.tmp');
        await temporary.writeAsBytes(partial, flush: true);
        await folder.recoverOwned(
          'tandemlog-space.json',
          expected,
          replacement,
        );
        expect(await folder.read('tandemlog-space.json'), replacement);
        expect(await temporary.exists(), false);
        final archives = (await folder.list())
            .where((entry) => entry.name.contains('.recovery-'))
            .toList();
        expect(archives, hasLength(1));
        expect(await folder.read(archives.single.name), partial);
      },
    );
  }

  test(
    'recovery refuses unknown temporary bytes without changing evidence',
    () async {
      final temporary = File('${directory.path}/tandemlog-space.json.tmp');
      await temporary.writeAsBytes([9], flush: true);
      await expectLater(
        folder.recoverOwned('tandemlog-space.json', expected, replacement),
        throwsA(
          isA<OwnedReplacementFailure>()
              .having((e) => e.phase, 'phase', 'temporary_changed')
              .having((e) => e.mayHaveChanged, 'uncertain', false),
        ),
      );
      expect(await folder.read('tandemlog-space.json'), expected);
      expect(await temporary.readAsBytes(), [9]);
      expect(await directory.list().length, 2);
    },
  );

  test(
    'recovery rechecks current target before archiving its temporary',
    () async {
      final temporary = File('${directory.path}/tandemlog-space.json.tmp');
      await temporary.writeAsBytes([5], flush: true);
      await expectLater(
        folder.recoverOwned(
          'tandemlog-space.json',
          Uint8List.fromList([0]),
          replacement,
        ),
        throwsA(
          isA<OwnedReplacementFailure>().having(
            (e) => e.phase,
            'phase',
            'source_changed',
          ),
        ),
      );
      expect(await folder.read('tandemlog-space.json'), expected);
      expect(await temporary.readAsBytes(), [5]);
      expect(await directory.list().length, 2);
    },
  );

  test('unsafe names and oversize preflight cannot create output', () async {
    await expectLater(
      folder.replaceOwned('../escape', expected, replacement),
      throwsArgumentError,
    );
    await expectLater(
      folder.checkReplacementSupport(
        'tandemlog-space.json',
        maximumOwnedReplacementBytes + 1,
      ),
      throwsArgumentError,
    );
    expect((await directory.list().toList()), hasLength(1));
  });
}
