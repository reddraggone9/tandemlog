import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/unified_record.dart';

// Agent identities are ordinary installations without a count cap; byte
// bounds remain the only admission limit. The conversion manifest stays capped.
const space = '11111111-1111-4111-8111-111111111111';
const epoch = '22222222-2222-4222-8222-222222222222';
String identity(int index) =>
    '${index.toRadixString(16).padLeft(8, '0')}-3333-4333-8333-444444444444';

Future<LocalProfileDatabase> profileFor(String root, String writer) async {
  final p = await LocalProfileDatabase.open(root);
  p.transaction(
    () => p.database.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
      writer,
      utf8.encode(jsonEncode({'writer': writer, 'appearance': 'system'})),
    ]),
  );
  return p;
}

void main() {
  for (final count in [257, 1000]) {
    test('an action may observe $count writers', () {
      final record = UnifiedRecord(
        space: space,
        epoch: epoch,
        writer: identity(1),
        sequence: 1,
        clock: EventClock(BigInt.one),
        previousHash: unifiedGenesis(space, epoch, identity(1)),
        effect: UnifiedEffect.joined(),
        observed: {
          for (var i = 1; i <= count; i++)
            identity(i): UnifiedFrontier(
              0,
              unifiedGenesis(space, epoch, identity(i)),
            ),
        },
      );
      expect(UnifiedRecord.decode(record.encode()).observed, hasLength(count));
    });
  }

  test('the conversion manifest keeps its owner bound', () {
    final owners = {
      for (var i = 1; i <= 257; i++)
        identity(i): {
          'count': 0,
          'head': unifiedGenesis(space, epoch, identity(i)),
          'digest': bytesDigest([]),
        },
    };
    expect(
      () => UnifiedManifest(space, epoch, bytesDigest([]), owners, {
        identity(1): identity(1),
      }),
      throwsA(isA<FormatFailure>()),
    );
  });

  test('a workspace admits more than 256 installation histories', () async {
    final root = await Directory.systemTemp.createTemp('tandemlog-writers-');
    addTearDown(() => root.delete(recursive: true));
    final folder = LocalLogFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    final first = await profileFor('${root.path}/p0', identity(1));
    final h = await UnifiedHistory.create(
      folder,
      profile: first,
      writer: identity(1),
    );
    await h.close();
    await first.close();
    // Join the extra writers directly; each join is one small history file.
    for (var i = 2; i <= 258; i++) {
      final p = await profileFor('${root.path}/p$i', identity(i));
      final joined = await UnifiedHistory.open(
        folder,
        profile: p,
        writer: identity(i),
      );
      await joined.close();
      await p.close();
    }
    final again = await LocalProfileDatabase.open('${root.path}/p0');
    final reopened = await UnifiedHistory.open(
      folder,
      profile: again,
      writer: identity(1),
    );
    addTearDown(() async {
      await reopened.close();
      await again.close();
    });
    final histories = (await folder.list())
        .where((f) => f.name.endsWith('.applog'))
        .map((f) => f.name)
        .toList();
    // 257 joined installations have their own history; the creator's
    // starting state is the manifest until it first appends.
    expect(histories.length, greaterThan(256));
    expect(histories.where((n) => n.contains(identity(258))), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
