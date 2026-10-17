import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import '../tool/food_preview.dart';

// Choose a view through the same visible Filter menu as the application.
// Inbox is a Stock group, so tests targeting undated rows choose Stock.
Future<void> selectFoodView(
  WidgetTester tester,
  FoodView view, {
  Future<void> Function(Finder)? input,
}) async {
  Future<void> tap(Finder target) async {
    expect(target.hitTestable(), findsOneWidget);
    if (input == null) {
      await tester.tap(target);
    } else {
      await input(target);
    }
    await tester.pumpAndSettle();
  }

  await tap(find.byKey(const ValueKey('food-filter')));
  final label = switch (view) {
    FoodView.inventory || FoodView.inbox => 'Stock',
    FoodView.retained => 'Retained',
    FoodView.deleted => 'Deleted',
  };
  await tap(find.widgetWithText(PopupMenuItem<FoodView>, label));
}

Widget foodFixtureIdentityMenu(Widget? child) => PopupMenuButton<String>(
  key: const ValueKey('identity-menu'),
  tooltip: 'Active user: Synthetic household',
  onSelected: (_) {},
  itemBuilder: (_) => const [
    CheckedPopupMenuItem(
      value: 'synthetic',
      checked: true,
      child: Text('Synthetic household'),
    ),
    PopupMenuItem(value: 'new', child: Text('Manage users')),
    PopupMenuDivider(),
    PopupMenuItem(value: 'settings', child: Text('Settings')),
  ],
  child: child,
);

void expectUntruncatedGuidance(WidgetTester tester) {
  final field = find.widgetWithText(TextField, 'Expiration');
  final input = tester.widget<TextField>(field);
  expect(input.decoration!.hintText, 'YYYY-MM-DD');
  final calendar = find.byTooltip('Choose Expiration');
  expect(calendar, findsOneWidget);
  expect(tester.getSize(calendar).height, greaterThanOrEqualTo(48));
  expect(tester.getSize(calendar).width, greaterThanOrEqualTo(48));
  final editable = tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  if (input.controller!.text.isEmpty && editable.focusNode.hasFocus) {
    final hint = find.text('YYYY-MM-DD');
    expect(hint, findsOneWidget);
    final rich = find.descendant(of: hint, matching: find.byType(RichText));
    final paragraph = tester.renderObject<RenderParagraph>(rich);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 10),
      ),
      isNotEmpty,
      reason: 'The focused blank date must render its format hint',
    );
  }
}

// Use the SDK's production font: Ahem's square glyphs cannot establish native
// text readability.
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

  final action = find.byKey(const ValueKey('food-save-action'));
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
  expectUntruncatedGuidance(tester);
  await tap(action);
  await tester.pumpAndSettle();
  expect(find.text('Expiration is required.'), findsOneWidget);
  expect(
    tester
        .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
        .state
        .active,
    isEmpty,
    reason: 'A blank manual Add cannot write an undated container',
  );
  await capture?.call('$name-required-date');
  await type(expiry, '2027-02-30');
  await Scrollable.ensureVisible(tester.element(expiry), alignment: 0.15);
  await tester.pumpAndSettle();
  expectUntruncatedGuidance(tester);
  await capture?.call('$name-add-focused');
  await tap(action);
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
  expect(
    find.descendant(of: action, matching: find.text('Review errors')),
    findsOneWidget,
  );
  await tap(action);
  await tester.pumpAndSettle();
  FoodInventoryPage page() => tester.widget(find.byType(FoodInventoryPage));
  expect(
    page().state.active,
    isEmpty,
    reason: 'Review cannot become Add after the date is corrected',
  );
  expect(
    find.descendant(of: action, matching: find.text('Add')),
    findsOneWidget,
  );
  await tap(action);
  await tester.pumpAndSettle();
  expect(page().state.active.single.details.expiry, '2027-06-01');
  final savedId = page().state.active.single.id;
  await tester.pumpAndSettle();
  await tap(find.text('Test beans'));
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
  await tap(find.text('Test beans'));
  await tester.pumpAndSettle();
  await type(expiry, '');
  await tap(action);
  await tester.pumpAndSettle();
  expect(find.text('Expiration is required.'), findsOneWidget);
  expect(page().state.active.single.details.expiry, '2027-06-01');
  expect(page().state.active.single.id, savedId);
  expect(tester.widget<TextField>(expiry).controller!.text, isEmpty);
  await capture?.call('$name-blank-edit-rejected');
  await type(expiry, '2027-07-09');
  expect(
    find.descendant(of: action, matching: find.text('Review errors')),
    findsOneWidget,
  );
  await tap(action);
  await tester.pumpAndSettle();
  expect(page().state.active.single.details.expiry, '2027-06-01');
  expect(page().state.active.single.id, savedId);
  expect(
    find.descendant(of: action, matching: find.text('Save')),
    findsOneWidget,
  );
  await tap(action);
  await tester.pumpAndSettle();
  expect(page().state.active.single.details.expiry, '2027-07-09');
  expect(page().state.active.single.id, savedId);
  expect(find.text('Test beans'), findsOneWidget);
  await capture?.call('$name-valid-edit-saved');
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
