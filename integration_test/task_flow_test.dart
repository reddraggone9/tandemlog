import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native capture, edit, completion, undo, restart and error recovery',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('tandemlog-ui');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/private').create();
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': null}));
      // Interrupt startup before settling; discarded states must not retain a store/timer.
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create user'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Lee');
      await tester.tap(find.widgetWithText(FilledButton, 'Create user').last);
      await tester.pumpAndSettle();
      expect(find.text('A clear slate.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Pick up groceries');
      await tester.tap(find.byTooltip('Add tasks'));
      await tester.pumpAndSettle();
      expect(find.text('Pick up groceries'), findsOneWidget);
      await tester.tap(find.text('Pick up groceries'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Buy oats',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Notes'),
        'Large bag',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Buy oats'), findsOneWidget);
      expect(find.text('Large bag'), findsOneWidget);
      await tester.tap(find.byTooltip('Complete Buy oats'));
      await tester.pumpAndSettle();
      expect(find.text('A clear slate.'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Buy oats'), findsOneWidget);
      // Periodic ingestion must not steal an unfinished capture's input/focus.
      await tester.enterText(find.byType(TextField), 'Unsubmitted draft');
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Unsubmitted draft'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      expect(find.text('Buy oats'), findsOneWidget);
      expect(find.text('Large bag'), findsOneWidget);
      final bad = File(
        '${folder.path}/11111111-1111-4111-8111-111111111111.jsonl',
      );
      await bad.writeAsString('{"v":99}\n');
      await tester.tap(find.byTooltip('Refresh folder'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unsupported event version'), findsOneWidget);
      expect(find.text('Buy oats'), findsOneWidget);
      await bad.delete();
      await tester.tap(find.byTooltip('Refresh folder'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unsupported event version'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await root.delete(recursive: true);
    },
  );
}
