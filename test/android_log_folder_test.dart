import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/presentation/failure_message.dart';
import 'package:tandemlog/domain/event.dart' show FormatFailure;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final folder = AndroidLogFolder('content://synthetic/tree/test');
  tearDown(
    () => messenger.setMockMethodCallHandler(AndroidLogFolder.channel, null),
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
