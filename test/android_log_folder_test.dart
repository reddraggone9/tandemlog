import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:tandemlog/platform/foreground_importer.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/presentation/failure_message.dart';
import 'package:tandemlog/domain/event.dart' show FormatFailure;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final folder = AndroidLogFolder('content://synthetic/tree/test');
  const watchMethods = MethodChannel('tandemlog/folder-events');
  tearDown(() {
    messenger.setMockMethodCallHandler(AndroidLogFolder.channel, null);
    messenger.setMockMethodCallHandler(watchMethods, null);
  });
  Future<void> event(Object? value) async {
    await messenger.handlePlatformMessage(
      AndroidLogFolder.eventsChannel.name,
      AndroidLogFolder.eventsChannel.codec.encodeSuccessEnvelope(value),
      (_) {},
    );
  }

  Future<void> watchError() async {
    await messenger.handlePlatformMessage(
      AndroidLogFolder.eventsChannel.name,
      AndroidLogFolder.eventsChannel.codec.encodeErrorEnvelope(
        code: 'watch_unavailable',
        message: 'Polling remains active',
      ),
      (_) {},
    );
  }

  test(
    'range bridge returns suffix and exposes nonseekable fallback explicitly',
    () async {
      final calls = <MethodCall>[];
      var seekable = true;
      messenger.setMockMethodCallHandler(AndroidLogFolder.channel, (
        call,
      ) async {
        calls.add(call);
        expect(call.method, 'readFrom');
        return seekable ? Uint8List.fromList([4, 5]) : null;
      });
      expect(await folder.readFrom('writer.jsonl', 3), [4, 5]);
      expect(calls.single.arguments, {
        'tree': folder.location,
        'name': 'writer.jsonl',
        'offset': 3,
      });
      seekable = false;
      expect(await folder.readFrom('writer.jsonl', 3), isNull);
      expect(calls, hasLength(2));
      await expectLater(
        folder.readFrom('writer.jsonl', -1),
        throwsArgumentError,
      );
      expect(calls, hasLength(2));
    },
  );

  test(
    'range truncation/provider errors remain failures rather than fallback',
    () async {
      messenger.setMockMethodCallHandler(
        AndroidLogFolder.channel,
        (_) async => throw PlatformException(
          code: 'folder',
          message: 'Log was truncated',
        ),
      );
      await expectLater(
        folder.readFrom('writer.jsonl', 3),
        throwsA(isA<FolderAccessFailure>()),
      );
    },
  );

  test(
    'unsupported watch retains 15-second foreground fallback and retries',
    () {
      var attempts = 0, reconciliations = 0;
      messenger.setMockMethodCallHandler(watchMethods, (call) async {
        if (call.method == 'listen') {
          attempts++;
          throw PlatformException(code: 'watch_unavailable');
        }
        return null;
      });
      fakeAsync((clock) {
        final importer = ForegroundImporter(
          events: folder.watch,
          reconcile: () async {
            reconciliations++;
          },
        );
        importer.start();
        clock.flushMicrotasks();
        expect(attempts, 1);
        final initial = reconciliations;
        clock.elapse(const Duration(seconds: 14));
        clock.flushMicrotasks();
        expect(attempts, 1);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(attempts, 2);
        expect(reconciliations, greaterThan(initial));
        importer.dispose();
        clock.flushMicrotasks();
        expect(clock.periodicTimerCount, 0);
      });
    },
  );

  test(
    'metadata remains optional observations and never creates trusted stamps',
    () async {
      var identity = 'before-replacement';
      messenger.setMockMethodCallHandler(
        AndroidLogFolder.channel,
        (_) async => [
          {
            'name': 'writer.jsonl',
            'documentId': identity,
            'size': 42,
            'modifiedMillis': 1000,
          },
          {
            'name': 'unknown.jsonl',
            'documentId': '',
            'size': null,
            'modifiedMillis': null,
          },
          {
            'name': 'invalid.jsonl',
            'size': -1,
            'modifiedMillis': 'unavailable',
          },
        ],
      );
      final before = await folder.list();
      final observation = before.first as AndroidLogFileInfo;
      expect(observation.documentId, 'before-replacement');
      expect(observation.size, 42);
      expect(observation.modifiedMillis, 1000);
      for (final entry in before.skip(1).cast<AndroidLogFileInfo>()) {
        expect(entry.documentId, isNull);
        expect(entry.size, isNull);
        expect(entry.modifiedMillis, isNull);
      }
      expect(before.every((entry) => entry.stamp.isEmpty), isTrue);
      identity = 'after-replacement';
      final after = await folder.list();
      expect(
        (after.first as AndroidLogFileInfo).documentId,
        'after-replacement',
      );
      expect(after.first.stamp, '');
      expect(observation.documentId, 'before-replacement');
    },
  );

  for (final name in ['tandemlog-space.json', 'writer.jsonl']) {
    for (final repeatedIdentity in [false, true]) {
      test(
        'list rejects duplicate $name before returning observations (same identity: $repeatedIdentity)',
        () async {
          final calls = <String>[];
          messenger.setMockMethodCallHandler(AndroidLogFolder.channel, (
            call,
          ) async {
            calls.add(call.method);
            return [
              {'name': name, 'documentId': 'first', 'size': 42},
              {
                'name': name,
                'documentId': repeatedIdentity ? 'first' : 'second',
                'size': 42,
              },
            ];
          });
          await expectLater(
            folder.list(),
            throwsA(
              isA<FolderAccessFailure>()
                  .having((e) => e.message, 'affected name', contains(name))
                  .having((e) => e.message, 'ambiguity', contains('duplicate'))
                  .having(
                    (e) => e.message,
                    'fail closed',
                    contains('No file was selected'),
                  ),
            ),
          );
          expect(calls, ['list']);
        },
      );
    }
  }

  test('unrelated duplicate names do not reject the folder', () async {
    messenger.setMockMethodCallHandler(
      AndroidLogFolder.channel,
      (_) async => [
        {'name': 'notes.txt', 'documentId': 'note-one'},
        {'name': 'notes.txt', 'documentId': 'note-two'},
        {'name': 'writer.JSONL', 'documentId': 'unrelated-one'},
        {'name': 'writer.JSONL', 'documentId': 'unrelated-two'},
        {'name': 'tandemlog-space.json', 'documentId': 'manifest'},
        {'name': 'writer.jsonl', 'documentId': 'log'},
      ],
    );
    final entries = await folder.list();
    expect(entries, hasLength(6));
    expect(entries.where((entry) => entry.name == 'notes.txt'), hasLength(2));
  });

  for (final method in ['list', 'read', 'readFrom', 'append', 'create']) {
    test(
      '$method preserves native duplicate-name diagnostics and fails closed',
      () async {
        final calls = <String>[];
        messenger.setMockMethodCallHandler(AndroidLogFolder.channel, (
          call,
        ) async {
          calls.add(call.method);
          throw PlatformException(
            code: 'duplicate_file',
            message:
                'Folder access failed: Duplicate canonical filename writer.jsonl',
            details: {'name': 'writer.jsonl'},
          );
        });
        final operation = switch (method) {
          'list' => folder.list(),
          'read' => folder.read('writer.jsonl'),
          'readFrom' => folder.readFrom('writer.jsonl', 10),
          'append' => folder.append('writer.jsonl', Uint8List.fromList([1])),
          _ => folder.create('writer.jsonl', Uint8List.fromList([1])),
        };
        await expectLater(
          operation,
          throwsA(
            isA<FolderAccessFailure>()
                .having(
                  (e) => e.message,
                  'affected name',
                  contains('writer.jsonl'),
                )
                .having(
                  (e) => e.message,
                  'action',
                  contains('Resolve the duplicate names'),
                )
                .having(
                  (e) => e.message,
                  'fail closed',
                  contains('No file was selected'),
                )
                .having(
                  (e) => e.message,
                  'not a grant error',
                  isNot(contains('permission')),
                )
                .having(
                  (e) => e.cause,
                  'native diagnostic cause',
                  isA<PlatformException>(),
                ),
          ),
        );
        expect(calls, [method]);
      },
    );
  }

  test(
    'watch cancellation and old callbacks cannot trigger the new folder',
    () async {
      final calls = <MethodCall>[];
      final cancelled = Completer<void>();
      messenger.setMockMethodCallHandler(watchMethods, (call) async {
        calls.add(call);
        if (call.method == 'cancel' &&
            call.arguments['tree'] == folder.location) {
          await cancelled.future;
        }
        return null;
      });
      final oldEvents = <Object?>[], newEvents = <Object?>[];
      final old = folder.watch().listen(oldEvents.add);
      await Future<void>.delayed(Duration.zero);
      final oldToken = calls.first.arguments['token'];
      await event({'tree': folder.location, 'token': oldToken});
      await Future<void>.delayed(Duration.zero);
      expect(oldEvents, hasLength(1));
      final oldCancellation = old.cancel();
      final nextFolder = AndroidLogFolder('content://synthetic/tree/next');
      final next = nextFolder.watch().listen(newEvents.add);
      try {
        await Future<void>.delayed(Duration.zero);
        final nextToken = calls
            .lastWhere((call) => call.method == 'listen')
            .arguments['token'];
        expect(nextToken, isNot(oldToken));
        await event({'tree': folder.location, 'token': oldToken});
        await event({'tree': nextFolder.location, 'token': oldToken});
        await event({'tree': folder.location, 'token': nextToken});
        await event({'tree': nextFolder.location, 'token': nextToken});
        cancelled.complete();
        await oldCancellation;
        await event({'tree': nextFolder.location, 'token': nextToken});
        await Future<void>.delayed(Duration.zero);
        expect(oldEvents, hasLength(1));
        expect(newEvents, hasLength(2));
      } finally {
        if (!cancelled.isCompleted) cancelled.complete();
        await oldCancellation;
        await next.cancel();
      }
      expect(calls.where((call) => call.method == 'cancel'), hasLength(2));
    },
  );

  test(
    'unsupported watch activation becomes a stream error for polling fallback',
    () async {
      messenger.setMockMethodCallHandler(watchMethods, (call) async {
        if (call.method == 'listen') {
          throw MissingPluginException('Unsupported observer');
        }
        return null;
      });
      final error = Completer<Object>();
      final subscription = folder.watch().listen(
        (_) {},
        onError: error.complete,
      );
      try {
        expect(await error.future, isA<MissingPluginException>());
      } finally {
        await subscription.cancel();
      }
    },
  );

  test(
    'observer error is delivered and a resumed watch uses fresh token',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(watchMethods, (call) async {
        calls.add(call);
        return null;
      });
      final error = Completer<Object>();
      final first = folder.watch().listen((_) {}, onError: error.complete);
      await Future<void>.delayed(Duration.zero);
      final oldToken = calls.first.arguments['token'];
      await watchError();
      expect(
        await error.future,
        isA<PlatformException>().having(
          (error) => error.code,
          'fallback',
          'watch_unavailable',
        ),
      );
      await first.cancel();
      final observed = <Object?>[];
      final resumed = folder.watch().listen(observed.add);
      try {
        await Future<void>.delayed(Duration.zero);
        final token = calls.last.arguments['token'];
        await event({'tree': folder.location, 'token': oldToken});
        await event({'tree': folder.location, 'token': token});
        await Future<void>.delayed(Duration.zero);
        expect(observed, hasLength(1));
      } finally {
        await resumed.cancel();
      }
    },
  );

  test(
    'successful folder calls preserve bytes, names and forced revalidation',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(AndroidLogFolder.channel, (
        call,
      ) async {
        calls.add(call);
        return switch (call.method) {
          'pick' => folder.location,
          'list' => [
            {'name': 'tandemlog-space.json'},
          ],
          'read' => Uint8List.fromList([1, 2, 3]),
          _ => null,
        };
      });
      expect(await AndroidLogFolder.pick(), folder.location);
      final entries = await folder.list();
      expect(entries.single.name, 'tandemlog-space.json');
      expect(entries.single.stamp, '');
      expect(await folder.read('test.jsonl'), [1, 2, 3]);
      await folder.append('test.jsonl', Uint8List.fromList([4, 5]));
      await folder.create('test.jsonl', Uint8List.fromList([6]));
      expect(calls.map((c) => c.method), [
        'pick',
        'list',
        'read',
        'append',
        'create',
      ]);
      expect(calls[3].arguments['bytes'], [4, 5]);
    },
  );

  test(
    'missing manifest gives restoration guidance without blaming permission',
    () async {
      messenger.setMockMethodCallHandler(
        AndroidLogFolder.channel,
        (_) async => throw PlatformException(
          code: 'missing_file',
          message: 'Folder access failed: Missing tandemlog-space.json',
          details: {'name': 'tandemlog-space.json'},
        ),
      );
      await expectLater(
        folder.read('tandemlog-space.json'),
        throwsA(
          isA<FolderAccessFailure>()
              .having(
                (e) => e.message,
                'message',
                contains('missing tandemlog-space.json'),
              )
              .having(
                (e) => e.message,
                'recovery',
                contains('Restore this file'),
              )
              .having(
                (e) => e.message,
                'permissions',
                isNot(contains('permission')),
              )
              .having(
                (e) => e.toString(),
                'wrapper',
                isNot(contains('PlatformException')),
              )
              .having(
                (e) => e.cause,
                'diagnostic cause',
                isA<PlatformException>(),
              ),
        ),
      );
    },
  );

  for (final method in ['list', 'read', 'append', 'create']) {
    test(
      '$method generic IO failure stays honest and omits provider internals',
      () async {
        messenger.setMockMethodCallHandler(
          AndroidLogFolder.channel,
          (_) async => throw PlatformException(
            code: 'folder',
            message: 'java.io.IOException: synthetic provider internals',
          ),
        );
        final operation = switch (method) {
          'list' => folder.list(),
          'read' => folder.read('test.jsonl'),
          'append' => folder.append('test.jsonl', Uint8List(0)),
          _ => folder.create('test.jsonl', Uint8List(0)),
        };
        await expectLater(
          operation,
          throwsA(
            isA<FolderAccessFailure>()
                .having(
                  (e) => e.message,
                  'operation',
                  contains(
                    method == 'read' || method == 'list' ? 'read' : 'saving',
                  ),
                )
                .having(
                  (e) => e.message,
                  'permission assumption',
                  isNot(contains('permission')),
                )
                .having(
                  (e) => e.message,
                  'internal details',
                  isNot(contains('java.')),
                )
                .having(
                  (e) => e.message,
                  'framework wrapper',
                  isNot(contains('PlatformException')),
                ),
          ),
        );
      },
    );
  }

  test(
    'actual denied access and picker failures have specific recovery',
    () async {
      messenger.setMockMethodCallHandler(
        AndroidLogFolder.channel,
        (_) async => throw PlatformException(code: 'permission'),
      );
      await expectLater(
        folder.list(),
        throwsA(
          isA<FolderAccessFailure>()
              .having((e) => e.message, 'denied', contains('denied'))
              .having((e) => e.message, 'settings', contains('Settings')),
        ),
      );
      await expectLater(
        AndroidLogFolder.pick(),
        throwsA(
          isA<FolderAccessFailure>().having(
            (e) => e.message,
            'retain grant',
            contains('could not be kept'),
          ),
        ),
      );
      messenger.setMockMethodCallHandler(
        AndroidLogFolder.channel,
        (_) async => throw PlatformException(code: 'busy'),
      );
      await expectLater(
        AndroidLogFolder.pick(),
        throwsA(
          isA<FolderAccessFailure>().having(
            (e) => e.message,
            'picker busy',
            'The folder picker is already open.',
          ),
        ),
      );
    },
  );

  test(
    'presentation retains partial progress and canonical validation messages',
    () {
      final access = FolderAccessFailure(
        'Could not finish saving to the data folder.',
      );
      expect(
        failureMessage(StateError('1 task confirmed saved; 2 remain. $access')),
        '1 task confirmed saved; 2 remain. Could not finish saving to the data folder.',
      );
      final invalid = FormatFailure('Unsupported canonical event version.');
      expect(failureMessage(invalid), 'Unsupported canonical event version.');
    },
  );
}
