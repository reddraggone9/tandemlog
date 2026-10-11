import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/folder_actions.dart';

// Run only in the isolated desktop-handler environment prepared by the audit.
// This exercises the real native plugin rather than a mocked launch channel.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['TANDEMLOG_FOLDER_SMOKE_ROOT'];
  final missing = Platform.environment['TANDEMLOG_FOLDER_SMOKE_MISSING'] == '1';
  testWidgets(
    'native folder opening preserves spaces, Unicode and data; missing handler disables Settings action',
    (tester) async {
      final folder = await Directory('$root/Household café 東京').create();
      final sentinel = File('${folder.path}/retained.json');
      final original = utf8.encode('{"synthetic":"unchanged — 東京"}\n');
      await sentinel.writeAsBytes(original);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Folder launch smoke'))),
      );
      final actions = FolderActions();
      await tester.runAsync(() async {
        expect(await actions.canOpen(folder.path), !missing);
        if (!missing) {
          await actions.open(folder.path);
          final capture = File('$root/launch.json');
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          while (!capture.existsSync() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(capture.existsSync(), isTrue);
          final arguments = jsonDecode(await capture.readAsString()) as List;
          expect(arguments, hasLength(1));
          // Desktop launchers may pass either a local path or a file URI.
          final argument = arguments.single as String;
          final received = argument.startsWith('file:')
              ? Uri.parse(argument).toFilePath()
              : argument;
          expect(Uri.directory(received), Uri.directory(folder.path));
        }
      });
      if (missing) {
        final profile = await Directory('$root/profile').create();
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({'folder': folder.path}),
        );
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        expect(
          find.text('No file manager is available to open this folder.'),
          findsOneWidget,
        );
        final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Open data folder'),
        );
        expect(button.onPressed, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      expect(await sentinel.readAsBytes(), original);
      expect(folder.listSync().map((entry) => entry.path), [sentinel.path]);
    },
    skip: !Platform.isLinux || root == null,
  );
}
