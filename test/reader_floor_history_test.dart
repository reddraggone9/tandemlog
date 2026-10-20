import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/domain/time_zone_policy.dart';
import 'package:tandemlog/domain/wall_time.dart'
    show timeZoneUpgradeRequiredMessage;
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/workspace_state.dart';
import 'package:tandemlog/storage/workspace_upgrade.dart';

import 'unified_conversion_test.dart' as fixture;

const _task = '77777777-7777-4777-8777-777777777777';
const _epoch = '88888888-8888-4888-8888-888888888888';
const _file = 'tandemlog-space.json';

Map<String, dynamic> _schedule() => TaskSchedule(
  dueDate: '2026-10-20',
  dueTime: '12:00',
  timeZone: 'CST6CDT',
).toJson();

UnifiedEffectBuilder _user(String writer) =>
    (seq, clock, head) => UnifiedEffect(
      'task',
      LogEvent(fixture.space, writer, seq, clock, _task, 'user.created', {
        'name': 'Compatible pending user',
      }).encode(previousHash: head),
    );
UnifiedEffectBuilder _alias(String writer) =>
    (seq, clock, head) => UnifiedEffect(
      'task',
      LogEvent(fixture.space, writer, seq, clock, _task, 'task.created', {
        'title': 'Additional zone',
        'description': '',
        'assignee': fixture.peer,
        'schedule': _schedule(),
      }).encode(previousHash: head),
    );

class _Folder extends LocalLogFolder {
  _Folder(super.location);
  void Function()? afterReplacement;
  @override
  Future<void> replaceOwned(
    String name,
    Uint8List expected,
    Uint8List bytes,
  ) async {
    await super.replaceOwned(name, expected, bytes);
    afterReplacement?.call();
  }
}

Future<LocalProfileDatabase> _profile(String path, String writer) async {
  final p = await LocalProfileDatabase.open(path);
  p.transaction(
    () => p.database.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
      writer,
      utf8.encode(jsonEncode({'writer': writer, 'appearance': 'system'})),
    ]),
  );
  return p;
}

void main() {
  late Directory root;
  late _Folder folder;
  late LocalProfileDatabase profile;
  late UnifiedHistory history;
  late TaskStore tasks;
  late FoodStore food;
  late WorkspaceState state;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('reader-floor-core-');
    folder = _Folder((await Directory('${root.path}/shared').create()).path);
    final plan = fixture.plan(), converted = plan.convert(fixture.ack(plan));
    await folder.create(
      _file,
      Uint8List.fromList(utf8.encode(converted.manifest.encode())),
    );
    for (final entry in converted.files.entries) {
      await folder.create(entry.key, Uint8List.fromList(entry.value));
    }
    profile = await _profile('${root.path}/profile', fixture.owner);
    history = await UnifiedHistory.open(
      folder,
      profile: profile,
      writer: fixture.owner,
    );
    tasks = await TaskStore.openUnified(history);
    food = await FoodStore.openUnified(history);
    state = WorkspaceState(tasks: tasks, food: food);
  });
  tearDown(() async {
    state.close();
    await food.close();
    await tasks.close();
    await history.close();
    await profile.close();
    await root.delete(recursive: true);
  });

  test(
    'deterministic exact eighth field rejects unknown descriptor or changed base',
    () {
      final base = history.manifest.encode();
      final target = history.manifest.withAdditionalTimeZones().encode();
      expect(jsonDecode(base), hasLength(7));
      expect(jsonDecode(target), hasLength(8));
      expect(validateTimeZoneExtension(base, target)!.baseRaw, base);
      expect(history.manifest.withAdditionalTimeZones().encode(), target);
      for (final field in [
        'minimumBuild',
        'legacyData',
        'additionalData',
        'reader',
        'names',
      ]) {
        final changed = jsonDecode(target) as Map<String, dynamic>;
        final descriptor =
            (changed['requiredCapabilities']
                    as Map)[additionalTimeZonesCapability]
                as Map;
        descriptor[field] = field == 'names'
            ? ['CST6CDT']
            : field.endsWith('Data')
            ? '0' * 64
            : 999;
        expect(
          () => UnifiedManifest.decode(canonicalDataJson(changed)),
          throwsA(isA<FormatFailure>()),
        );
      }
      final changed = jsonDecode(target) as Map<String, dynamic>;
      changed['epoch'] = _epoch;
      expect(
        validateTimeZoneExtension(base, canonicalDataJson(changed)),
        isNull,
      );
    },
  );

  test(
    'no permission means no direct or raw reservation before callbacks',
    () async {
      final before = await folder.read(unifiedLogName(fixture.owner));
      var callback = false;
      await expectLater(
        tasks.command(_task, 'task.created', {
          'title': 'Denied zone',
          'description': '',
          'assignee': fixture.peer,
          'schedule': _schedule(),
        }, onPrepared: (_) => callback = true),
        throwsA(
          isA<FormatFailure>().having(
            (error) => error.toString(),
            'workspace policy diagnostic',
            contains(timeZoneUpgradeRequiredMessage),
          ),
        ),
      );
      await expectLater(
        history.appendAtomic([_alias(fixture.owner)]),
        throwsA(
          isA<FormatFailure>().having(
            (error) => error.toString(),
            'workspace policy diagnostic',
            contains(timeZoneUpgradeRequiredMessage),
          ),
        ),
      );
      expect(callback, isFalse);
      expect(
        profile.database.select('SELECT * FROM protected_app_outbox'),
        isEmpty,
      );
      expect(await folder.read(unifiedLogName(fixture.owner)), before);
      expect(state.current.timeZonePolicy, TimeZoneNamePolicy.legacy);
    },
  );

  test(
    'explicit activation keeps handles and slices; actual alias command succeeds',
    () async {
      final before = state.current;
      final originals = {
        for (final info in await folder.list())
          info.name: await folder.read(info.name),
      };
      await expectLater(
        history.enableAdditionalTimeZones(confirmed: false),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        profile.database.select(
          'SELECT * FROM protected_workspace_capabilities',
        ),
        isEmpty,
      );
      await history.enableAdditionalTimeZones(confirmed: true);
      expect(
        state.current.timeZonePolicy,
        TimeZoneNamePolicy.additional2026eV1,
      );
      expect(identical(state.current.tasks, before.tasks), isTrue);
      expect(identical(state.current.tasks.users, before.tasks.users), isTrue);
      expect(identical(state.current.food, before.food), isTrue);
      expect(identical(state.tasks, tasks), isTrue);
      for (final entry in originals.entries) {
        if (entry.key != _file) {
          expect(await folder.read(entry.key), entry.value);
        }
      }
      expect(
        profile.database
            .select('SELECT state FROM protected_workspace_capabilities')
            .single['state'],
        'complete',
      );
      await history.appendAtomic([_alias(fixture.owner)]);
      expect(
        state.current.tasks.rows.singleWhere(
          (row) => row['id'] == _task,
        )['schedule'],
        _schedule(),
      );
      final bytes = await folder.read(unifiedLogName(fixture.owner));
      await history.enableAdditionalTimeZones(confirmed: true);
      expect(await folder.read(unifiedLogName(fixture.owner)), bytes);
    },
  );

  test(
    'projection failure cannot promote protected manifest or complete intent',
    () async {
      final base = history.manifest.encode();
      final prior = state.current;
      var armed = false;
      final owner = Object();
      await profile.serialize(
        () async => history.attachProjectionInProfileQueue(owner, (snapshot) {
          if (armed) throw StateError('Synthetic full projection failure');
          return () {};
        }),
      );
      folder.afterReplacement = () => armed = true;
      await expectLater(
        history.enableAdditionalTimeZones(confirmed: true),
        throwsStateError,
      );
      expect(
        UnifiedManifest.decode(
          utf8.decode(await folder.read(_file)),
        ).additionalTimeZonesEnabled,
        isTrue,
      );
      expect(
        profile.database
            .select('SELECT manifest FROM protected_app_workspaces')
            .single['manifest'],
        base,
      );
      expect(
        profile.database
            .select('SELECT state FROM protected_workspace_capabilities')
            .single['state'],
        isNot('complete'),
      );
      expect(identical(state.current.tasks, prior.tasks), isTrue);
      expect(state.current.timeZonePolicy, TimeZoneNamePolicy.legacy);
      armed = false;
      await history.refresh();
      expect(
        state.current.timeZonePolicy,
        TimeZoneNamePolicy.additional2026eV1,
      );
      expect(
        profile.database
            .select('SELECT state FROM protected_workspace_capabilities')
            .single['state'],
        'complete',
      );
      await profile.serialize(
        () async => history.detachProjectionInProfileQueue(owner),
      );
    },
  );

  test(
    'bound peer adopts and recovers its exact old-compatible pending bytes once',
    () async {
      final p = await _profile('${root.path}/peer', fixture.peer);
      final peer = await UnifiedHistory.open(
        folder,
        profile: p,
        writer: fixture.peer,
      );
      try {
        final reservation = await p.serialize(
          () => peer.prepareInProfileQueue([_user(fixture.peer)]),
        );
        final pending = List<int>.from(
          p.database
                  .select('SELECT raw FROM protected_app_outbox')
                  .single['raw']
              as List,
        );
        await history.enableAdditionalTimeZones(confirmed: true);
        await peer.refresh();
        expect(peer.manifest.additionalTimeZonesEnabled, isTrue);
        expect(
          p.database
              .select('SELECT raw FROM protected_app_outbox')
              .single['raw'],
          pending,
        );
        expect(
          p.database
              .select('SELECT state FROM protected_workspace_capabilities')
              .single['state'],
          'complete',
        );
        await peer.recoverPrepared();
        final actual = await folder.read(unifiedLogName(fixture.peer));
        expect(
          actual.sublist(actual.length - reservation.bytes.length),
          reservation.bytes,
        );
        await peer.recoverPrepared();
        expect(await folder.read(unifiedLogName(fixture.peer)), actual);
      } finally {
        await peer.close();
        await p.close();
      }
    },
  );

  test(
    'adoption rejects malicious old-policy alias reservation before journalling',
    () async {
      final p = await _profile('${root.path}/malicious-peer', fixture.peer);
      final peer = await UnifiedHistory.open(
        folder,
        profile: p,
        writer: fixture.peer,
      );
      try {
        await p.serialize(
          () => peer.prepareInProfileQueue([_user(fixture.peer)]),
        );
        final row = p.database
            .select('SELECT * FROM protected_app_outbox')
            .single;
        final seq = (row['base_sequence'] as int) + 1;
        final clock = EventClock.next(
          BigInt.from(DateTime.now().microsecondsSinceEpoch) *
              BigInt.from(1000),
          peer.maximumClock,
        );
        final effect = _alias(fixture.peer)(
          seq,
          clock,
          row['base_hash'] as String,
        );
        final forged = peer.preview(
          effect,
          sequence: seq,
          clock: clock,
          predecessor: row['base_hash'] as String,
          start: seq,
          count: 1,
          index: 0,
        );
        final raw = Uint8List.fromList(utf8.encode('${forged.encode()}\n'));
        // Deliberately invalid local authority, never a legitimately prepared old save.
        p.transaction(
          () => p.database.execute('UPDATE protected_app_outbox SET raw=?', [
            raw,
          ]),
        );
        await history.enableAdditionalTimeZones(confirmed: true);
        await expectLater(
          peer.refresh(),
          throwsA(
            isA<FormatFailure>().having(
              (error) => error.toString(),
              'workspace policy diagnostic',
              contains(timeZoneUpgradeRequiredMessage),
            ),
          ),
        );
        expect(
          p.database.select('SELECT * FROM protected_workspace_capabilities'),
          isEmpty,
        );
        expect(
          UnifiedManifest.decode(
            p.database
                    .select('SELECT manifest FROM protected_app_workspaces')
                    .single['manifest']
                as String,
          ).additionalTimeZonesEnabled,
          isFalse,
        );
        expect(
          p.database
              .select('SELECT raw FROM protected_app_outbox')
              .single['raw'],
          raw,
        );
      } finally {
        await peer.close();
        await p.close();
      }
    },
  );

  test(
    'historical v3 aliases remain forbidden in pure conversion and fresh activated8',
    () async {
      final raw = LogEvent(
        fixture.space,
        fixture.owner,
        1,
        EventClock(BigInt.one),
        _task,
        'task.created',
        {
          'title': 'Malformed historical alias',
          'description': '',
          'assignee': fixture.peer,
          'schedule': _schedule(),
        },
      ).encode();
      final source = utf8.encode('$raw\n');
      expect(
        () => UnifiedCutoverPlan.inspect(
          space: fixture.space,
          owners: {fixture.owner},
          participants: {fixture.owner},
          sources: {'${fixture.owner}.jsonl': source},
          hasUnresolvedPreparedWrites: false,
        ),
        throwsA(
          isA<FormatFailure>().having(
            (error) => error.toString(),
            'historical legacy policy diagnostic',
            contains(timeZoneUpgradeRequiredMessage),
          ),
        ),
      );
      final physical = UnifiedRecord(
        space: fixture.space,
        epoch: _epoch,
        writer: fixture.owner,
        sequence: 1,
        clock: EventClock(BigInt.one),
        previousHash: unifiedGenesis(fixture.space, _epoch, fixture.owner),
        effect: UnifiedEffect('legacy.task', raw),
        transactionStart: 1,
        transactionCount: 1,
        transactionIndex: 0,
      );
      final bytes = utf8.encode('${physical.encode()}\n');
      final manifest = UnifiedManifest(
        fixture.space,
        _epoch,
        '0' * 64,
        {
          fixture.owner: {
            'count': 1,
            'head': physical.hash,
            'digest': bytesDigest(bytes),
          },
        },
        [
          LegacySeal(
            '${fixture.owner}.jsonl',
            fixture.owner,
            'legacy.task',
            source.length,
            bytesDigest(source),
            1,
            LogEvent.decode(raw).hash!,
          ),
        ],
        additionalTimeZonesEnabled: true,
      );
      final bad = LocalLogFolder(
        (await Directory('${root.path}/bad-history').create()).path,
      );
      await bad.create(
        _file,
        Uint8List.fromList(utf8.encode(manifest.encode())),
      );
      await bad.create(
        unifiedLogName(fixture.owner),
        Uint8List.fromList(bytes),
      );
      await bad.create('${fixture.owner}.jsonl', Uint8List.fromList(source));
      final p = await _profile('${root.path}/bad-profile', fixture.owner);
      try {
        await expectLater(
          UnifiedHistory.preflight(bad, profile: p, writer: fixture.owner),
          throwsA(
            isA<FormatFailure>().having(
              (error) => error.toString(),
              'historical legacy policy diagnostic',
              contains(timeZoneUpgradeRequiredMessage),
            ),
          ),
        );
        expect(
          p.database.select('SELECT * FROM protected_app_workspaces'),
          isEmpty,
        );
      } finally {
        await p.close();
      }
    },
  );

  test(
    'ACKed peer completes original upgrade after actual owner capability activation',
    () async {
      final shared = LocalLogFolder(
        (await Directory('${root.path}/upgrade-shared').create()).path,
      );
      await shared.create(
        _file,
        Uint8List.fromList(
          utf8.encode(jsonEncode({'v': 3, 'id': fixture.space})),
        ),
      );
      for (final entry in fixture.sources().entries) {
        await shared.create(entry.key, Uint8List.fromList(entry.value));
      }
      final a = await _profile('${root.path}/upgrade-a', fixture.owner);
      final b = await _profile('${root.path}/upgrade-b', fixture.peer);
      UnifiedHistory? owner;
      try {
        final start = await WorkspaceUpgrade.start(
          folder: shared,
          profile: a,
          writer: fixture.owner,
          participants: {fixture.owner, fixture.peer},
        );
        final peer = (await WorkspaceUpgrade.open(
          folder: shared,
          profile: b,
          writer: fixture.peer,
        ))!;
        await peer.consentToUpgrade();
        await start.acknowledgeInput();
        await peer.acknowledgeInput();
        await start.stage();
        await start.acknowledgeOutput();
        await peer.acknowledgeOutput();
        await start.activate();
        await start.complete();
        final originalReceipt = a.database
            .select(
              "SELECT value FROM profile_metadata WHERE key LIKE 'upgrade.complete:%'",
            )
            .single['value'];
        owner = await UnifiedHistory.open(
          shared,
          profile: a,
          writer: fixture.owner,
        );
        await owner.enableAdditionalTimeZones(confirmed: true);
        await owner.appendAtomic([_alias(fixture.owner)]);
        final reopened = (await WorkspaceUpgrade.open(
          folder: shared,
          profile: b,
          writer: fixture.peer,
        ))!;
        await reopened.complete();
        expect(reopened.phase, 'complete');
        expect(
          a.database
              .select(
                "SELECT value FROM profile_metadata WHERE key LIKE 'upgrade.complete:%'",
              )
              .single['value'],
          originalReceipt,
        );
        expect(
          await WorkspaceUpgrade.open(
            folder: shared,
            profile: a,
            writer: fixture.owner,
          ),
          isNull,
        );
        for (final entry in fixture.sources().entries) {
          expect(await shared.read(entry.key), entry.value);
        }
      } finally {
        await owner?.close();
        await a.close();
        await b.close();
      }
    },
  );

  test(
    'exact synthetic schema4 upgrades additively; missing schema5 authority never rebuilds',
    () async {
      final path = '${root.path}/schema-profile';
      var p = await _profile(path, fixture.owner);
      final settings = p.database
          .select('SELECT * FROM protected_settings')
          .single;
      p.transaction(() {
        p.database.execute('DROP TABLE protected_workspace_capabilities');
        p.database.execute('PRAGMA user_version=4');
        p.database.execute(
          "UPDATE profile_metadata SET value='4' WHERE key='schema'",
        );
      });
      await p.close();
      p = await LocalProfileDatabase.open(path);
      expect(p.database.select('PRAGMA user_version').single.values.single, 5);
      expect(
        p.database.select('SELECT * FROM protected_settings').single,
        settings,
      );
      p.transaction(
        () => p.database.execute('DROP TABLE protected_workspace_capabilities'),
      );
      await p.close();
      await expectLater(
        LocalProfileDatabase.open(path),
        throwsA(isA<LocalDatabaseFailure>()),
      );
    },
  );
}
