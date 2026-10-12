import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/platform/folder_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  test(
    'rejected folder launch preserves URI and gives recovery message',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'folder-action-test-',
      );
      final location = '${folder.path}/Household café 東京';
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return false;
      });
      try {
        final actions = FolderActions();
        expect(await actions.canOpen(location), isFalse);
        await expectLater(
          actions.open(location),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'recovery message',
              'No file manager could open this folder. Your data is unchanged.',
            ),
          ),
        );
        expect(calls.map((call) => call.method), ['canLaunch', 'launch']);
        for (final call in calls) {
          expect(
            (call.arguments as Map)['url'],
            Uri.directory(location).toString(),
          );
        }
        expect(folder.listSync(), isEmpty);
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        await folder.delete();
      }
    },
  );
}
