import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as updated_database;
import 'package:timezone/timezone.dart' as tz;
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/domain/time_zone_policy.dart';
import 'package:tandemlog/domain/timezone_data/iana_2025c.dart'
    as legacy_database;
import 'package:tandemlog/domain/wall_time.dart';
import 'package:tandemlog/presentation/form_validation.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';

import 'fixtures/timezone-2025c/app/schedule.dart' as historical_schedule;
import 'fixtures/timezone-2025c/app/wall_time.dart' as historical_wall_time;

const _fixture = 'test/fixtures/timezone-2025c';
const _blocked = ['CST6CDT', 'EST5EDT', 'MST7MDT', 'PST8PDT'];
const _writer = '22222222-2222-4222-8222-222222222222';
const _user = '33333333-3333-4333-8333-333333333333';
const _task = '44444444-4444-4444-8444-444444444444';
const _oldDataHash =
    'e67e57be5d320b54e96381b59fdc2e7b0ec803b7e1be98621e445312cf5f295e';

class _CountingFolder implements LogFolder, BoundedLogFolder {
  _CountingFolder(this.inner);
  final LocalLogFolder inner;
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      inner.readBounded(name, maximumBytes);

  int appends = 0;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) {
    appends++;
    return inner.append(name, bytes);
  }
}

Map<String, dynamic> _editorTask() => {
  'id': _task,
  'title': 'Existing task',
  'description': '',
  'assignee': _user,
  'tags': <String>[],
  'tagRefs': <String, String>{},
  'schedule': {'dueDate': '2026-11-02'},
};

void main() {
  late tz.Location originalGlobalWinnipeg;
  setUpAll(() {
    timeZoneLocation('America/Winnipeg');
    originalGlobalWinnipeg = tz.getLocation('America/Winnipeg');
  });
  final names = List<String>.from(
    jsonDecode(File('$_fixture/names.json').readAsStringSync()) as List,
  );
  final vectors =
      (jsonDecode(File('$_fixture/wall-time-vectors.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();

  test('frozen reader and generated table retain exact source provenance', () {
    final provenanceFile = File('$_fixture/provenance.json');
    expect(
      sha256.convert(provenanceFile.readAsBytesSync()).toString(),
      'b2617f3f625cf88bfe47a3020ff29a2144d486a9ab41b58e0a13def019bbecb1',
    );
    final provenance =
        jsonDecode(provenanceFile.readAsStringSync()) as Map<String, dynamic>;
    expect(provenance['defaultTZFSHA256'], _oldDataHash);
    expect(
      sha256
          .convert(File('$_fixture/default.tzf').readAsBytesSync())
          .toString(),
      _oldDataHash,
    );
    for (final entry
        in (provenance['fixtureFiles'] as Map<String, dynamic>).entries) {
      expect(
        sha256
            .convert(File('$_fixture/${entry.key}').readAsBytesSync())
            .toString(),
        entry.value,
        reason: entry.key,
      );
    }
    final generatedFile = File('lib/domain/timezone_data/iana_2025c.dart');
    expect(
      sha256.convert(generatedFile.readAsBytesSync()).toString(),
      provenance['adaptedGeneratedDartSHA256'],
    );
    final generated = generatedFile
        .readAsStringSync()
        .split('const _embeddedData =')
        .last;
    final embedded = RegExp(r'\\x([0-9a-f]{2})')
        .allMatches(generated)
        .map((match) => int.parse(match[1]!, radix: 16))
        .toList();
    expect(embedded, hasLength(253760));
    expect(sha256.convert(embedded).toString(), _oldDataHash);
  });

  test('four additional tables retain exact source bytes and complete rules', () {
    const fixture = 'test/fixtures/timezone-additional-2026e';
    final provenance =
        jsonDecode(File('$fixture/provenance.json').readAsStringSync())
            as Map<String, dynamic>;
    final bytes = File('$fixture/default-four.tzf').readAsBytesSync();
    expect(bytes, hasLength(5696));
    expect(
      sha256.convert(bytes).toString(),
      '157d7906210f5331f21db80763a5e85601182890ff5c2a32adb0bd4721b7047f',
    );
    expect(provenance['selectedDataSHA256'], sha256.convert(bytes).toString());
    expect(provenance['sourceDataSHA256'], additionalTimeZoneDataSha256);
    expect(
      provenance['archiveSHA256'],
      '9f4e5a1a0e4fef7dd3424842c0575db01bfb7a11730e8d55753fcd5c5c98767b',
    );
    expect(provenance['names'], additionalTimeZoneNames);
    expect(additionalTimeZoneCapabilityDescriptor, {
      'reader': 1,
      'minimumBuild': 98,
      'legacyData': _oldDataHash,
      'additionalData':
          'a49273d40c8560e4559e79178dd7384d3fb427933929ebe6d22ccfa336bf5a17',
      'names': _blocked,
    });
    final generated = File(
      'lib/domain/timezone_data/iana_2026e_additional.dart',
    ).readAsStringSync().split('const _embeddedData =').last;
    final embedded = RegExp(
      r'\\x([0-9a-f]{2})',
    ).allMatches(generated).map((m) => int.parse(m[1]!, radix: 16)).toList();
    expect(embedded, bytes);
    // The fixture provides a separate deserialization, never the production map.
    tz.initializeDatabase(bytes);
    try {
      expect(tz.timeZoneDatabase.locations.keys.toList()..sort(), _blocked);
      for (final name in _blocked) {
        final actual = timeZoneLocation(name), expected = tz.getLocation(name);
        expect(actual, isNot(same(expected)));
        expect(actual.transitionAt, expected.transitionAt, reason: name);
        expect(actual.transitionZone, expected.transitionZone, reason: name);
        expect(
          actual.zones
              .map((z) => (z.offset.inSeconds, z.isDst, z.abbreviation))
              .toList(),
          expected.zones
              .map((z) => (z.offset.inSeconds, z.isDst, z.abbreviation))
              .toList(),
          reason: name,
        );
      }
    } finally {
      legacy_database.initializeTimeZones();
    }
  });

  for (var index = 0; index < _blocked.length; index++) {
    final zone = _blocked[index];
    final standardHours =
        6 +
        (index == 0
            ? 0
            : index == 1
            ? -1
            : index == 2
            ? 1
            : 2);
    test(
      'additional $zone keeps winter summer gap and earlier fold meaning',
      () {
        expect(
          resolveZonedWallTime('2026-01-02', '09:00', zone).instant,
          DateTime.utc(2026, 1, 2, 9 + standardHours),
        );
        expect(
          resolveZonedWallTime('2026-07-02', '09:00', zone).instant,
          DateTime.utc(2026, 7, 2, 8 + standardHours),
        );
        final gap = resolveZonedWallTime('2026-03-08', '02:30', zone);
        expect(gap.instant, DateTime.utc(2026, 3, 8, 2 + standardHours, 30));
        expect(gap.gapShift, const Duration(hours: 1));
        expect(gap.ambiguous, isFalse);
        final fold = resolveZonedWallTime('2026-11-01', '01:30', zone);
        expect(fold.instant, DateTime.utc(2026, 11, 1, standardHours, 30));
        expect(fold.gapShift, Duration.zero);
        expect(fold.ambiguous, isTrue);
      },
    );
  }

  test(
    'workspace policy covers direct successor and native schedule envelopes',
    () {
      for (final zone in _blocked) {
        for (final data in <Map<String, dynamic>>[
          {
            'schedule': {'timeZone': zone},
          },
          {
            'successor': {
              'schedule': {'timeZone': zone},
            },
          },
          {
            'nonText': {
              'schedule': {'timeZone': zone},
            },
          },
          {
            'nonText': {
              'successor': {
                'schedule': {'timeZone': zone},
              },
            },
          },
          {
            'successor': <dynamic, dynamic>{
              'schedule': <dynamic, dynamic>{'timeZone': zone},
            },
          },
        ]) {
          final event = LogEvent(
            '11111111-1111-4111-8111-111111111111',
            _writer,
            1,
            EventClock(BigInt.one),
            _task,
            'task.completed',
            data,
          );
          expect(
            () => TimeZoneNamePolicy.legacy.assertTaskEventAllowed(event),
            throwsA(isA<TimeZoneUpgradeRequired>()),
          );
          TimeZoneNamePolicy.additional2026eV1.assertTaskEventAllowed(event);
        }
      }
      for (final name in [...names, 'UTC']) {
        TimeZoneNamePolicy.legacy.assertScheduleAllowed({'timeZone': name});
      }
      expect(TimeZoneNamePolicy.legacy.allowsAdditionalTimeZones, isFalse);
      expect(
        TimeZoneNamePolicy.additional2026eV1.allowsAdditionalTimeZones,
        isTrue,
      );
    },
  );

  test('all341 released names keep complete tables and readable schedules', () {
    expect(names, hasLength(341));
    for (final name in names) {
      final oldLocation = historical_wall_time.timeZoneLocation(name);
      final current = timeZoneLocation(name);
      expect(current.name, oldLocation.name, reason: name);
      expect(current.transitionAt, oldLocation.transitionAt, reason: name);
      expect(current.transitionZone, oldLocation.transitionZone, reason: name);
      expect(
        current.zones
            .map((z) => (z.offset.inSeconds, z.isDst, z.abbreviation))
            .toList(),
        oldLocation.zones
            .map((z) => (z.offset.inSeconds, z.isDst, z.abbreviation))
            .toList(),
        reason: name,
      );
      final raw = <String, dynamic>{
        'dueDate': '2026-11-02',
        'dueTime': '09:00',
        'timeZone': name,
      };
      expect(
        TaskSchedule.fromJson(raw).toJson(),
        historical_schedule.TaskSchedule.fromJson(raw).toJson(),
        reason: name,
      );
    }
  });

  for (final vector in vectors) {
    test(
      'frozen wall meaning ${vector['zone']} ${vector['date']} ${vector['time']}',
      () {
        final old = historical_wall_time.resolveZonedWallTime(
          vector['date'] as String,
          vector['time'] as String,
          vector['zone'] as String,
        );
        final current = resolveZonedWallTime(
          vector['date'] as String,
          vector['time'] as String,
          vector['zone'] as String,
        );
        final expected = DateTime.parse(vector['instant'] as String);
        expect(old.instant, expected);
        expect(current.instant, expected);
        expect(current.gapShift.inMinutes, vector['gapMinutes'] ?? 0);
        expect(current.gapShift, old.gapShift);
        expect(current.ambiguous, vector['ambiguous'] ?? false);
        expect(current.ambiguous, old.ambiguous);
      },
    );
  }

  for (final zone in _blocked) {
    test('new name $zone requires the admitted workspace policy', () {
      expect(
        () => historical_schedule.TaskSchedule(timeZone: zone),
        throwsA(isA<historical_schedule.ScheduleValidationException>()),
      );
      expect(timeZoneLocation(zone).name, zone);
      final raw = <String, dynamic>{
        'dueDate': '2026-11-02',
        'dueTime': '09:00',
        'timeZone': zone,
      };
      expect(TaskSchedule.fromJson(raw).toJson()['timeZone'], zone);
      expect(
        () => TimeZoneNamePolicy.legacy.assertScheduleAllowed(raw),
        throwsA(
          isA<TimeZoneUpgradeRequired>().having(
            (error) => error.message,
            'message',
            timeZoneUpgradeRequiredMessage,
          ),
        ),
      );
      TimeZoneNamePolicy.additional2026eV1.assertScheduleAllowed(raw);
      final encoded = LogEvent(
        '11111111-1111-4111-8111-111111111111',
        _writer,
        1,
        EventClock(BigInt.one),
        _task,
        'task.edited',
        {'schedule': raw},
      ).encode();
      final decoded = LogEvent.decode(encoded);
      expect(
        () => TimeZoneNamePolicy.legacy.assertTaskEventAllowed(decoded),
        throwsA(isA<TimeZoneUpgradeRequired>()),
      );
      TimeZoneNamePolicy.additional2026eV1.assertTaskEventAllowed(decoded);
    });
  }

  test(
    'returned location tables are immutable for all legacy names and UTC',
    () {
      for (final name in [...names, ..._blocked, 'UTC']) {
        final location = timeZoneLocation(name);
        expect(
          () => location.transitionAt.clear(),
          throwsUnsupportedError,
          reason: name,
        );
        expect(
          () => location.transitionZone.clear(),
          throwsUnsupportedError,
          reason: name,
        );
        expect(
          () => location.zones.clear(),
          throwsUnsupportedError,
          reason: name,
        );
      }
    },
  );

  test(
    'mutating original global location lists cannot change private rules',
    () {
      final location = timeZoneLocation('America/Winnipeg');
      final original = originalGlobalWinnipeg;
      expect(location, isNot(same(original)));
      expect(location.transitionAt, isNot(same(original.transitionAt)));
      expect(location.transitionZone, isNot(same(original.transitionZone)));
      expect(location.zones, isNot(same(original.zones)));
      final transitions = List<int>.of(original.transitionAt);
      final indices = List<int>.of(original.transitionZone);
      final zones = List<tz.TimeZone>.of(original.zones);
      try {
        original.transitionAt.clear();
        original.transitionZone.clear();
        original.zones.clear();
        expect(
          resolveZonedWallTime(
            '2026-11-02',
            '09:00',
            'America/Winnipeg',
          ).instant,
          DateTime.utc(2026, 11, 2, 15),
        );
        expect(location.transitionAt, transitions);
        expect(location.transitionZone, indices);
        expect(location.zones, zones);
      } finally {
        original.transitionAt.addAll(transitions);
        original.transitionZone.addAll(indices);
        original.zones.addAll(zones);
      }
    },
  );

  test('mutating package global UTC cannot change private UTC meaning', () {
    final location = timeZoneLocation('UTC');
    final original = tz.UTC;
    expect(location, isNot(same(original)));
    final transitions = List<int>.of(original.transitionAt);
    final indices = List<int>.of(original.transitionZone);
    final zones = List<tz.TimeZone>.of(original.zones);
    try {
      original.transitionAt.clear();
      original.transitionZone.clear();
      original.zones.clear();
      expect(
        resolveZonedWallTime('2026-11-02', '09:00', 'UTC').instant,
        DateTime.utc(2026, 11, 2, 9),
      );
      expect(location.name, 'Etc/UTC');
      expect(location.transitionAt, [tz.minTime]);
      expect(location.transitionZone, [0]);
      expect(location.zones, [tz.TimeZone.UTC]);
    } finally {
      original.transitionAt.addAll(transitions);
      original.transitionZone.addAll(indices);
      original.zones.addAll(zones);
    }
  });

  test(
    'updated package initializer cannot change captured rules or open gate',
    () {
      final legacy = timeZoneLocation('America/Winnipeg');
      updated_database.initializeTimeZones();
      addTearDown(legacy_database.initializeTimeZones);
      final instant = DateTime.utc(2026, 11, 2, 9).millisecondsSinceEpoch;
      expect(tz.timeZoneDatabase.locations.keys, containsAll(_blocked));
      expect(
        tz.getLocation('America/Winnipeg').timeZone(instant).offset.inHours,
        -5,
        reason:
            'Counterfactual proves the resolved package contains2026e rules',
      );
      expect(
        timeZoneLocation('America/Winnipeg').timeZone(instant).offset.inHours,
        -6,
      );
      expect(timeZoneLocation('America/Winnipeg'), same(legacy));
      for (final zone in _blocked) {
        expect(timeZoneLocation(zone).name, zone);
        expect(
          () => TimeZoneNamePolicy.legacy.assertScheduleAllowed({
            'timeZone': zone,
          }),
          throwsA(isA<TimeZoneUpgradeRequired>()),
        );
      }
    },
  );

  test(
    'unknown names and UTC floating calendar schedules keep old behavior',
    () {
      expect(
        () => TaskSchedule(timeZone: 'Imaginary/Zone'),
        throwsA(
          isA<ScheduleValidationException>().having(
            (error) => error.message,
            'message',
            'Unknown time zone identifier.',
          ),
        ),
      );
      for (final zone in <String?>[null, 'UTC', 'America/Winnipeg']) {
        final raw = <String, dynamic>{
          'dueDate': '2026-10-31',
          'dueTime': '09:00',
          'timeZone': zone,
          'recurrence': 'every day',
        };
        final current = TaskSchedule.fromJson(raw);
        final old = historical_schedule.TaskSchedule.fromJson(raw);
        expect(current.toJson(), old.toJson());
        expect(
          current.next(DateTime.utc(2026, 11, 1)).toJson(),
          old.next(DateTime.utc(2026, 11, 1)).toJson(),
        );
        expect(current.toJson().keys, isNot(contains('timeZoneRules')));
      }
    },
  );

  for (final bulk in [false, true]) {
    test(
      'first-use timezone revisions persist automatically bulk=$bulk',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'timezone-first-use-',
        );
        TaskStore? store;
        try {
          final folder = _CountingFolder(
            LocalLogFolder(
              (await Directory('${root.path}/shared').create()).path,
            ),
          );
          store = await TaskStore.open(
            folder,
            '${root.path}/profile',
            writerIdentity: _writer,
          );
          await store.command(_user, 'user.created', {
            'name': 'Synthetic user',
          });
          await store.command(_task, 'task.created', {
            'title': 'Existing task',
            'description': '',
            'assignee': _user,
            'schedule': {
              'dueDate': '2026-11-02',
              'dueTime': '09:00',
              'timeZone': 'America/Winnipeg',
            },
          });
          final manifest = await folder.read('tandemlog-space.json');
          for (final zone in _blocked) {
            final appends = folder.appends;
            var prepared = 0;
            if (bulk) {
              final result = await store.bulkEdit(
                [_task],
                BulkTaskEdit(schedulePatch: {'timeZone': zone}),
                expectedTaskSnapshot: store.taskSnapshot,
                onPrepared: (_) => prepared++,
              );
              expect(
                result.succeeded,
                isTrue,
                reason: result.error?.toString(),
              );
            } else {
              await store.command(_task, 'task.edited', {
                'schedule': {
                  'dueDate': '2026-11-02',
                  'dueTime': '09:00',
                  'timeZone': zone,
                },
              }, onPrepared: (_) => prepared++);
            }
            expect(prepared, 1);
            expect(folder.appends, appends + 1);
            final action = store.unified!.snapshot.records.last;
            final operation = jsonDecode(action.effects.single.raw) as Map;
            expect(operation['operation'], {
              'family': 'task.update',
              'revision': 2,
            });
            expect(
              store.rows.singleWhere(
                (r) => r['id'] == _task,
              )['schedule']['timeZone'],
              zone,
            );
            expect(await folder.read('tandemlog-space.json'), manifest);
          }
          final before = await folder.read('$_writer.applog'),
              appends = folder.appends;
          await expectLater(
            store.command(_task, 'task.edited', {
              'schedule': {'timeZone': 'Mars/Olympus'},
            }),
            throwsA(isA<FormatFailure>()),
          );
          expect(folder.appends, appends);
          expect(await folder.read('$_writer.applog'), before);
          await store.close();
          store = await TaskStore.open(
            folder,
            '${root.path}/profile',
            writerIdentity: _writer,
          );
          expect(
            store.rows.singleWhere(
              (r) => r['id'] == _task,
            )['schedule']['timeZone'],
            'PST8PDT',
          );
          expect(await folder.read('$_writer.applog'), before);
          expect(await folder.read('tandemlog-space.json'), manifest);
        } finally {
          await store?.close();
          await root.delete(recursive: true);
        }
      },
    );
  }

  for (final bulk in [false, true]) {
    testWidgets('editor bulk=$bulk policy change invalidates a held Save', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var policy = TimeZoneNamePolicy.legacy;
      late StateSetter refreshHost;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                refreshHost = setState;
                return bulk
                    ? BulkTaskEditor(
                        panel: true,
                        timeZonePolicy: policy,
                        tasks: [_editorTask()],
                        onClose: () {},
                        onSave: (_) async {
                          saves++;
                        },
                      )
                    : TaskEditor(
                        panel: true,
                        timeZonePolicy: policy,
                        task: _editorTask(),
                        onClose: () {},
                        save: (_, _, _) async {
                          saves++;
                        },
                      );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('timeZone'));
      await tester.ensureVisible(input);
      await tester.enterText(input, 'UTC');
      final primary = find.descendant(
        of: find.byType(ValidationActionButton),
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(primary);
      final held = await tester.startGesture(tester.getCenter(primary));
      await tester.pump();
      refreshHost(() => policy = TimeZoneNamePolicy.additional2026eV1);
      await tester.pumpAndSettle();
      await held.up();
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(tester.widget<TextField>(input).controller!.text, 'UTC');
      await tester.tap(primary);
      await tester.pumpAndSettle();
      expect(saves, 1);
    });
  }

  for (final bulk in [false, true]) {
    for (final zone in _blocked) {
      testWidgets('editor bulk=$bulk policy update keeps draft and saves $zone', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(900, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var policy = TimeZoneNamePolicy.legacy;
        late StateSetter refreshHost;
        var saves = 0;
        Map<String, dynamic>? savedSchedule;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  refreshHost = setState;
                  return bulk
                      ? BulkTaskEditor(
                          key: const ValueKey('policy-editor'),
                          panel: true,
                          timeZonePolicy: policy,
                          tasks: [
                            _editorTask(),
                            {..._editorTask(), 'id': _user},
                          ],
                          onClose: () {},
                          onSave: (edit) async {
                            saves++;
                            savedSchedule = edit.schedulePatch;
                          },
                        )
                      : TaskEditor(
                          key: const ValueKey('policy-editor'),
                          panel: true,
                          timeZonePolicy: policy,
                          task: _editorTask(),
                          onClose: () {},
                          save: (fields, _, _) async {
                            saves++;
                            savedSchedule = Map<String, dynamic>.from(
                              fields['schedule'] as Map,
                            );
                          },
                        );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('timeZone'));
        await tester.ensureVisible(input);
        await tester.enterText(input, zone);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(input).decoration!.errorText,
          timeZoneUpgradeRequiredMessage,
        );
        await tester.tap(input);
        await tester.pumpAndSettle();
        final before = tester.widget<TextField>(input);
        final controller = before.controller!;
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 5,
        );
        await tester.pump();
        final value = controller.value;
        final focus = before.focusNode!;
        expect(focus.hasFocus, isTrue);
        // An unchanged policy (Later/unrelated host update) preserves the draft.
        refreshHost(() {});
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).controller, same(controller));
        expect(controller.value, value);
        expect(
          tester.widget<TextField>(input).decoration!.errorText,
          timeZoneUpgradeRequiredMessage,
        );
        // Successful additive metadata admission updates this same keyed editor.
        refreshHost(() => policy = TimeZoneNamePolicy.additional2026eV1);
        await tester.pumpAndSettle();
        final after = tester.widget<TextField>(input);
        expect(after.controller, same(controller));
        expect(after.controller!.value, value);
        expect(after.focusNode, same(focus));
        expect(focus.hasFocus, isTrue);
        expect(after.decoration!.errorText, isNull);
        expect(saves, 0);
        final primary = find.descendant(
          of: find.byType(ValidationActionButton),
          matching: find.byType(FilledButton),
        );
        await tester.ensureVisible(primary);
        await tester.tap(primary);
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(savedSchedule!['timeZone'], zone);
        if (!bulk) expect(savedSchedule!['dueDate'], '2026-11-02');
      });
    }
  }

  for (final bulk in [false, true]) {
    for (final zone in _blocked) {
      testWidgets('editor bulk=$bulk rejects $zone without Save', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(900, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var saves = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: bulk
                  ? BulkTaskEditor(
                      panel: true,
                      tasks: [
                        _editorTask(),
                        {..._editorTask(), 'id': _user},
                      ],
                      onSave: (_) async {
                        saves++;
                      },
                    )
                  : TaskEditor(
                      panel: true,
                      task: _editorTask(),
                      save: (_, _, _) async {
                        saves++;
                      },
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('timeZone'));
        await tester.ensureVisible(input);
        await tester.enterText(input, zone);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(input).decoration!.errorText,
          timeZoneUpgradeRequiredMessage,
        );
        final primary = find.descendant(
          of: find.byType(ValidationActionButton),
          matching: find.byType(FilledButton),
        );
        await tester.ensureVisible(primary);
        await tester.tap(primary);
        await tester.pumpAndSettle();
        expect(saves, 0);
        expect(tester.widget<TextField>(input).controller!.text, zone);
      });
    }
  }
}
