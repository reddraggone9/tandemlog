import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerReleaseVersionTests();
}

void registerReleaseVersionTests() {
  testWidgets(
    'Settings copies the running release name without changing tasks',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('release-version-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final seed = await openNativeFixtureStore(
        LocalLogFolder(folder.path),
        '${root.path}/seed',
      );
      final user = const Uuid().v4();
      await seed.command(user, 'user.created', {'name': 'Alex Example'});
      await seed.createTasks({const Uuid().v4(): 'Reference task'}, user);
      await seed.close();
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      Future<Map<String, String>> canonical() async => {
        await for (final file in folder.list())
          if (file is File) file.path: base64Encode(await file.readAsBytes()),
      };
      final before = await canonical();
      final oldClipboard = await Clipboard.getData(Clipboard.kTextPlain);
      try {
        expect(appBuildName, isNotNull);
        expect(appBuildName, isNot(contains('+')));
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await flows.waitForUi(
          tester,
          () => find.text('Reference task').evaluate().isNotEmpty,
        );
        final capture = find.widgetWithText(TextField, 'What needs doing?');
        await tester.enterText(capture, 'Retained draft');
        expect(find.text('Version'), findsNothing);
        for (final variant in const [
          (width: 1200.0, scale: 1.0, brightness: Brightness.light),
          (width: 1200.0, scale: 2.0, brightness: Brightness.dark),
          (width: 390.0, scale: 1.0, brightness: Brightness.dark),
          (width: 320.0, scale: 2.0, brightness: Brightness.light),
        ]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(variant.width, 820);
          tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
          tester.platformDispatcher.platformBrightnessTestValue =
              variant.brightness;
          await tester.pumpAndSettle();
          await flows.openSettings(tester);
          final copy = find.byTooltip('Copy version');
          await tester.ensureVisible(copy);
          await tester.pumpAndSettle();
          expect(find.text(appBuildName!), findsOneWidget);
          expect(tester.getSize(copy).width, greaterThanOrEqualTo(48));
          await Clipboard.setData(const ClipboardData(text: 'Previous value'));
          await tester.tap(copy);
          await tester.pumpAndSettle();
          expect(
            (await Clipboard.getData(Clipboard.kTextPlain))!.text,
            appBuildName,
          );
          expect(find.byIcon(Icons.check), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Done').last);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(capture).controller!.text,
            'Retained draft',
          );
          expect(await canonical(), before);
        }
      } finally {
        if (oldClipboard?.text != null) await Clipboard.setData(oldClipboard!);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        await root.delete(recursive: true);
      }
    },
  );
}
