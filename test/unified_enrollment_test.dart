import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'unified_conversion_test.dart' as fixture;

const newcomer = '77777777-7777-4777-8777-777777777777';
const another = '88888888-8888-4888-8888-888888888888';

class CreationFaultFolder extends LocalLogFolder {
  CreationFaultFolder(super.location);
  int? cut;
  @override
  Future<void> create(String name, Uint8List bytes) async {
    final stop = cut;
    cut = null;
    if (stop == null) return super.create(name, bytes);
    if (stop > 0) {
      await super.create(name, Uint8List.fromList(bytes.take(stop).toList()));
    }
    throw const FileSystemException('Synthetic header creation interruption');
  }
}

void main() {
  late Directory root;
  late CreationFaultFolder folder;
  final profiles = <LocalProfileDatabase>[];
  final histories = <UnifiedHistory>[];

  Future<LocalProfileDatabase> profile(String writer) async {
    final p = await LocalProfileDatabase.open('${root.path}/profile-$writer');
    profiles.add(p);
    if (p.database.select('SELECT 1 FROM protected_settings').isEmpty) {
      p.transaction(
        () => p.database.execute(
          'INSERT INTO protected_settings VALUES (1,?,?)',
          [
            writer,
            utf8.encode(jsonEncode({'writer': writer, 'appearance': 'system'})),
          ],
        ),
      );
    }
    return p;
  }

  Future<UnifiedHistory> open(String writer, {LocalProfileDatabase? p}) async {
    final h = await UnifiedHistory.open(
      folder,
      profile: p ?? await profile(writer),
      writer: writer,
      now: () => DateTime.utc(2026, 10, 18),
    );
    histories.add(h);
    return h;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'tandemlog-disposable-enrollment-',
    );
    folder = CreationFaultFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    final p = fixture.plan(), converted = p.convert(fixture.ack(p));
    await folder.create(
      'tandemlog-space.json',
      Uint8List.fromList(utf8.encode(converted.manifest.encode())),
    );
    for (final entry in converted.files.entries) {
      await folder.create(entry.key, Uint8List.fromList(entry.value));
    }
  });
  tearDown(() async {
    for (final h in histories.reversed) {
      await h.close();
    }
    histories.clear();
    for (final p in profiles.reversed) {
      await p.close();
    }
    profiles.clear();
    await root.delete(recursive: true);
  });

  test(
    'new installations join distinct chains; duplicate labels never alias original ownership',
    () async {
      final original = await open(fixture.owner);
      final manifest = await folder.read('tandemlog-space.json');
      final oldBytes = await folder.read(unifiedLogName(fixture.owner));
      final first = await open(newcomer), second = await open(another);
      expect(first.physicalSequence, 1);
      expect(
        first.snapshot.records
            .where((r) => r.writer == newcomer)
            .single
            .effect
            .kind,
        'writer.joined',
      );
      await first.renameDevice('Office');
      await second.renameDevice('Office');
      final received = await original.refresh();
      expect(received.deviceName(newcomer), 'Office');
      expect(received.deviceName(another), 'Office');
      expect(
        received.records
            .where((r) => r.effect.kind == 'writer.joined')
            .map((r) => r.writer)
            .toSet(),
        {newcomer, another},
      );
      await first.appendAtomic([
        (seq, clock, head) => UnifiedEffect(
          'task',
          LogEvent(
            fixture.space,
            newcomer,
            seq,
            clock,
            newcomer,
            'user.created',
            {'name': 'New installation user'},
          ).encode(previousHash: head),
        ),
      ]);
      expect(first.physicalSequence, 3);
      expect(
        first.snapshot.tasks.where((t) => t.writer == newcomer).single.sequence,
        3,
      );
      expect(await folder.read('tandemlog-space.json'), manifest);
      expect(await folder.read(unifiedLogName(fixture.owner)), oldBytes);
      final own = await folder.read(unifiedLogName(newcomer));
      await first.rebuildOwned();
      expect(await folder.read(unifiedLogName(newcomer)), own);
    },
  );

  for (final cut in [0, 20, 1000000]) {
    test(
      'interrupted installation header recovers exact reserved bytes once, cut=$cut',
      () async {
        final p = await profile(newcomer);
        folder.cut = cut;
        await expectLater(
          open(newcomer, p: p),
          throwsA(isA<FileSystemException>()),
        );
        final row = p.database
            .select('SELECT * FROM protected_app_outbox')
            .single;
        final expected = Uint8List.fromList(row['raw'] as List<int>);
        final h = await open(newcomer, p: p);
        await h.recoverPrepared();
        expect(h.physicalSequence, 1);
        expect(h.hasPending, isFalse);
        expect(await folder.read(unifiedLogName(newcomer)), expected);
        await h.recoverPrepared();
        expect(await folder.read(unifiedLogName(newcomer)), expected);
      },
    );
  }

  test(
    'previously observed installation cannot disappear from files or protected inventory',
    () async {
      final original = await open(fixture.owner);
      final fresh = await open(newcomer);
      await fresh.renameDevice('Replacement');
      await original.refresh();
      final file = folder.file(unifiedLogName(newcomer));
      final bytes = await file.readAsBytes();
      await file.delete();
      await expectLater(original.refresh(), throwsA(isA<FormatFailure>()));
      await file.writeAsBytes(bytes, flush: true);
      await original.refresh();
      original.profile.transaction(
        () => original.profile.database.execute(
          'DELETE FROM protected_app_heads WHERE writer=?',
          [newcomer],
        ),
      );
      await expectLater(original.refresh(), throwsA(isA<FormatFailure>()));
    },
  );

  test('unlisted writer must start with a standalone joined header', () async {
    final original = await open(fixture.owner), m = original.manifest;
    final genesis = unifiedGenesis(fixture.space, m.epoch, newcomer);
    final r = UnifiedRecord(
      space: fixture.space,
      epoch: m.epoch,
      writer: newcomer,
      sequence: 1,
      clock: EventClock(BigInt.from(1000000000000000000)),
      previousHash: genesis,
      effect: UnifiedEffect.named('Unproven installation'),
      transactionStart: 1,
      transactionCount: 1,
      transactionIndex: 0,
      observed: {newcomer: UnifiedFrontier(0, genesis)},
    );
    await folder.create(
      unifiedLogName(newcomer),
      Uint8List.fromList(utf8.encode('${r.encode()}\n')),
    );
    await expectLater(original.refresh(), throwsA(isA<FormatFailure>()));
  });
}
