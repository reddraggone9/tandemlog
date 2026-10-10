import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import '../tool/food_preview.dart';

void expectUntruncatedGuidance(WidgetTester tester) {
  final dialog = find.byType(AlertDialog);
  for (final fragment in ['YYYY-MM-DD', 'Inbox']) {
    final text = find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text && (widget.data?.contains(fragment) ?? false),
      ),
    );
    expect(text, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '$fragment must remain readable without reducing text size',
    );
  }
}

// Use the SDK's production font: Ahem's square glyphs spuriously overflow the
// unchanged certainty selector and cannot establish native text readability.
Future<void> loadSdkRoboto() async {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final font = File(
      '${directory.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    if (await font.exists()) {
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
      return;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) throw StateError('SDK Roboto not found');
    directory = parent;
  }
}

Future<void> verifyExpiryGuidanceWorkflow(
  WidgetTester tester, {
  required Brightness brightness,
  required double textScale,
  Future<void> Function(String)? capture,
  Future<void> Function(Finder)? input,
}) async {
  Future<void> tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    try {
      if (input != null) {
        await input(target);
      } else {
        await tester.tap(target);
      }
    } finally {
      WidgetController.hitTestWarningShouldBeFatal = previous;
    }
  }

  Future<void> type(Finder target, String value) async {
    final editable = find.descendant(
      of: target,
      matching: find.byType(EditableText),
    );
    await tap(editable);
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(target).controller!.text, value);
  }

  final name = '${brightness.name}-${textScale.toInt()}x';
  await tester.pumpWidget(
    FoodPreviewApp(
      key: ValueKey(name),
      brightness: brightness,
      textScale: textScale,
      initialOperations: const [],
    ),
  );
  await tester.pumpAndSettle();
  await tap(find.byTooltip('Add food'));
  await tester.pumpAndSettle();
  expectUntruncatedGuidance(tester);
  final expiry = find.widgetWithText(TextField, 'Expiration');
  await Scrollable.ensureVisible(tester.element(expiry), alignment: 0.15);
  await tester.pumpAndSettle();
  expectUntruncatedGuidance(tester);
  await capture?.call('$name-add-blank');
  await type(find.widgetWithText(TextField, 'Food name'), 'Test beans');
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<EditableText>(
          find.descendant(of: expiry, matching: find.byType(EditableText)),
        )
        .focusNode
        .hasFocus,
    isTrue,
  );
  await type(expiry, '2027-02-30');
  await Scrollable.ensureVisible(tester.element(expiry), alignment: 0.15);
  await tester.pumpAndSettle();
  expectUntruncatedGuidance(tester);
  await capture?.call('$name-add-focused');
  await tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pumpAndSettle();
  final error = find.text('Invalid food expiration.');
  expect(error, findsOneWidget);
  expect(
    tester
        .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
        .state
        .active,
    isEmpty,
  );
  expect(tester.widget<TextField>(expiry).controller!.text, '2027-02-30');
  await tester.ensureVisible(error);
  await tester.pumpAndSettle();
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: error, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  await capture?.call('$name-invalid-date');
  await Scrollable.ensureVisible(tester.element(expiry), alignment: 0.15);
  await tester.pumpAndSettle();
  await type(expiry, '2027-06-01');
  await tester.pumpAndSettle();
  await tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pumpAndSettle();
  FoodInventoryPage page() => tester.widget(find.byType(FoodInventoryPage));
  expect(page().state.active.single.details.expiry, '2027-06-01');
  await tap(find.byTooltip('Inspect Test beans containers'));
  await tester.pumpAndSettle();
  await tap(find.byTooltip('Actions for Test beans'));
  await tester.pumpAndSettle();
  await tap(find.text('Edit group details'));
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(expiry), alignment: 0.15);
  await tester.pumpAndSettle();
  expectUntruncatedGuidance(tester);
  await capture?.call('$name-edit-date');
  await type(expiry, '');
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await tap(find.text('Discard'));
  await tester.pumpAndSettle();
  expect(page().state.active.single.details.expiry, '2027-06-01');
  await tap(find.byTooltip('Actions for Test beans'));
  await tester.pumpAndSettle();
  await tap(find.text('Edit group details'));
  await tester.pumpAndSettle();
  await type(expiry, '');
  await tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
  expect(page().state.active.single.details.expiry, isNull);
  await tap(find.text('Inbox'));
  await tester.pumpAndSettle();
  expect(find.text('Test beans'), findsOneWidget);
  await capture?.call('$name-blank-saved-inbox');
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadSdkRoboto);
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '320dp ${brightness.name} ${scale}x date guidance and saving',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await verifyExpiryGuidanceWorkflow(
            tester,
            brightness: brightness,
            textScale: scale,
          );
        },
      );
    }
  }
}
