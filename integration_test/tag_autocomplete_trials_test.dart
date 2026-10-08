import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../tool/tag_trials/main.dart';
import 'native_text_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('lightweight tag-entry comparison on real GTK', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final width in [1000.0, 390.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 820);
      for (final option in [0, 1]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(const TagTrialsApp());
        await tester.pumpAndSettle();
        if (option == 1) {
          await tester.tap(find.text('B · Chips + query'));
          await tester.pumpAndSettle();
        }
        final query = find.byKey(const ValueKey('query-tags'));
        await tester.ensureVisible(query);
        await tester.pumpAndSettle();
        await tester.tap(query);
        await tester.enterText(query, option == 0 ? 'home #ba' : 'ba');
        await tester.pumpAndSettle();
        expect(find.text('#backlog'), findsOneWidget);
        await captureNativeFixtureUi(
          tester,
          '${option == 0 ? 'a' : 'b'}-${width.toInt()}-suggestions',
        );
        if (option == 0) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(query).controller!.text,
            'home backlog',
          );
        } else {
          await tester.tap(find.text('#backlog'));
          await tester.pumpAndSettle();
          expect(find.text('#home'), findsOneWidget);
          expect(find.text('#backlog'), findsOneWidget);
          expect(tester.widget<TextField>(query).controller!.text, isEmpty);
        }
        await captureNativeFixtureUi(
          tester,
          '${option == 0 ? 'a' : 'b'}-${width.toInt()}-selected',
        );
        if (option == 1) {
          await tester.enterText(query, '#fresh-tag');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(find.text('#fresh-tag'), findsOneWidget);
          tester
              .widget<InputChip>(find.widgetWithText(InputChip, '#home'))
              .onDeleted!();
          await tester.pumpAndSettle();
          expect(find.text('#home'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const TagTrialsApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bulk entry'));
    await tester.pumpAndSettle();
    for (final option in [0, 1]) {
      if (option == 1) {
        await tester.tap(find.text('B · Chips + query'));
        await tester.pumpAndSettle();
      }
      final query = find.byKey(const ValueKey('query-addTags'));
      await tester.ensureVisible(query);
      await tester.pumpAndSettle();
      await tester.tap(query);
      await tester.enterText(query, 'ba');
      await tester.pumpAndSettle();
      await captureNativeFixtureUi(
        tester,
        '${option == 0 ? 'a' : 'b'}-390-bulk',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
