import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

import '../tool/food_preview.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

Future<void> verifyFoodEditorKeyboardLayout(
  WidgetTester tester, {
  required Brightness brightness,
  required double textScale,
  required int editingCount,
  Future<void> Function(String)? capture,
  Future<void> Function(Finder)? input,
}) async {
  final mode = editingCount == 0 ? 'add' : 'edit-$editingCount';
  final prefix = '${brightness.name}-${textScale.toInt()}x-$mode';
  const foodName = 'Synthetic rice';
  final initial = editingCount == 0
      ? <FoodOperation>[]
      : [
          FoodOperation(
            id: '00000000-0000-4000-8000-000000000010:1',
            order: 1,
            action: FoodAction.add,
            targets: List.generate(
              editingCount,
              (i) =>
                  '00000000-0000-4000-8000-${(i + 1).toRadixString(16).padLeft(12, '0')}',
            ),
            details: const FoodDetails(
              name: foodName,
              expiry: '2027-06-01',
              brand: 'Sample Foods',
            ),
            contents: const Contents.fraction(1, 1),
            createdAt: '2026-10-10T00:00:00Z',
          ),
        ];

  FoodInventoryPage page() => tester.widget(find.byType(FoodInventoryPage));
  String state() => jsonEncode(
    page().state.active.map((container) => container.toJson()).toList(),
  );
  Future<void> tap(Finder target, {bool reveal = true}) async {
    if (reveal) await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    try {
      if (input == null) {
        await tester.tap(target);
      } else {
        await input(target);
      }
    } finally {
      WidgetController.hitTestWarningShouldBeFatal = previous;
    }
    await tester.pumpAndSettle();
  }

  Future<void> keyboard(bool open) async {
    // Captured Android: 320x640 logical pixels, Gboard starts around y=359.
    // Native GTK uses these simulated metrics, not an actual Android keyboard.
    tester.view.viewInsets = FakeViewPadding(bottom: open ? 280 : 0);
    tester.view.padding = FakeViewPadding(top: 24, bottom: open ? 0 : 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);
  Finder editable(Finder target) =>
      find.descendant(of: target, matching: find.byType(EditableText));
  Rect viewport(Finder target) => tester.getRect(
    find.ancestor(of: target, matching: find.byType(Scrollable)).first,
  );
  void expectFocusedLineVisible(String label) {
    final target = editable(field(label));
    expect(tester.widget<EditableText>(target).focusNode.hasFocus, isTrue);
    final rect = tester.getRect(target);
    expect(
      rect.intersect(viewport(field(label))).height,
      greaterThanOrEqualTo(rect.height - 0.5),
      reason: 'An already-focused input must stay visible when IME changes',
    );
  }

  void expectTextFragmentVisible(Finder text, String fragment) {
    final richText = find.descendant(of: text, matching: find.byType(RichText));
    final paragraph = tester.renderObject<RenderParagraph>(richText);
    expect(paragraph.didExceedMaxLines, isFalse);
    final value = tester.widget<Text>(text).data!;
    final start = value.indexOf(fragment);
    expect(start, greaterThanOrEqualTo(0));
    final origin = tester.getTopLeft(richText);
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + fragment.length),
    );
    expect(boxes, isNotEmpty, reason: '$fragment must have rendered glyphs');
    for (final box in boxes) {
      final rect = box.toRect().shift(origin);
      expect(
        rect.intersect(viewport(text)).height,
        greaterThanOrEqualTo(rect.height - 0.5),
        reason: '$fragment must be readable by scrolling with IME open',
      );
    }
  }

  void expectActions() {
    for (final target in [
      find.widgetWithText(TextButton, 'Cancel'),
      find.widgetWithText(FilledButton, editingCount == 0 ? 'Add' : 'Save'),
    ]) {
      expect(target.hitTestable(), findsOneWidget);
      final rect = tester.getRect(target);
      final availableBottom = 640 - tester.view.viewInsets.bottom;
      expect(rect.top, greaterThanOrEqualTo(24));
      expect(rect.bottom, lessThanOrEqualTo(availableBottom));
      final platform = Theme.of(tester.element(target)).platform;
      final minimumHeight = switch (platform) {
        TargetPlatform.android || TargetPlatform.iOS => 48.0,
        _ => 32.0,
      };
      expect(
        rect.height,
        greaterThanOrEqualTo(minimumHeight),
        reason: 'Preserve the platform action target size under IME',
      );
    }
  }

  Future<void> focus(String label, {bool dropdown = false}) async {
    final target = editable(field(label));
    final box = viewport(field(label));
    final line = tester.getRect(target);
    expect(
      box.height,
      greaterThanOrEqualTo(line.height),
      reason: 'The editor must have room for an entire editable line under IME',
    );
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    final visible = tester.getRect(target).intersect(viewport(field(label)));
    expect(visible.height, greaterThanOrEqualTo(line.height - 0.5));
    await tap(target, reveal: false);
    expect(tester.widget<EditableText>(target).focusNode.hasFocus, isTrue);
    if (dropdown) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    expectActions();
  }

  await keyboard(false);
  await tester.pumpWidget(
    FoodPreviewApp(
      key: ValueKey(prefix),
      initialOperations: initial,
      brightness: brightness,
      textScale: textScale,
    ),
  );
  await tester.pumpAndSettle();
  final before = state();
  if (editingCount == 0) {
    await tap(find.byTooltip('Add food'));
  } else {
    await tap(find.byTooltip('Inspect $foodName containers'));
    await tap(find.byTooltip('Actions for $foodName'));
    await tap(find.text('Edit group details'));
  }
  expectActions();
  await capture?.call('$prefix-open-no-ime');
  await keyboard(true);
  expectFocusedLineVisible('Food name');
  await focus('Food name');
  await capture?.call('$prefix-title-and-name-ime');
  if (editingCount == 0) {
    await tester.enterText(field('Food name'), foodName);
    await tester.pumpAndSettle();
  }
  for (final label in [
    'Brand (optional)',
    'Expiration',
    'Container size (optional)',
    'Location (optional)',
    if (editingCount == 0) 'Containers to add',
    'Retention reason',
  ]) {
    await focus(label, dropdown: label == 'Retention reason');
  }
  await tap(find.byType(DropdownButtonFormField<String>));
  expect(find.text('Estimated').hitTestable(), findsOneWidget);
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expectActions();
  await focus('Expiration');
  await tester.enterText(field('Expiration'), '2027-02-30');
  await tester.pumpAndSettle();
  final draft = tester.widget<TextField>(field('Expiration')).controller!;
  await capture?.call('$prefix-expiration-ime');
  final helper = find.text(
    'Use YYYY-MM-DD, or leave blank for the needs-expiration Inbox.',
  );
  await Scrollable.ensureVisible(tester.element(helper), alignment: 0);
  await tester.pumpAndSettle();
  expectTextFragmentVisible(helper, 'Use YYYY');
  expectActions();
  await capture?.call('$prefix-helper-start-ime');
  await Scrollable.ensureVisible(tester.element(helper), alignment: 1);
  await tester.pumpAndSettle();
  expectTextFragmentVisible(helper, 'Inbox.');
  expectActions();
  await capture?.call('$prefix-helper-end-ime');
  await keyboard(false);
  expect(draft.text, '2027-02-30');
  await capture?.call('$prefix-draft-no-ime');
  await keyboard(true);
  expectFocusedLineVisible('Expiration');
  await focus('Expiration');
  expect(draft.text, '2027-02-30');
  await tap(
    find.widgetWithText(FilledButton, editingCount == 0 ? 'Add' : 'Save'),
    reveal: false,
  );
  expect(state(), before, reason: 'Invalid calendar date must not mutate Food');
  expect(draft.text, '2027-02-30');
  final error = find.text('Invalid food expiration.');
  expect(error, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(error), alignment: 1);
  await tester.pumpAndSettle();
  expect(error.hitTestable(), findsOneWidget);
  expect(
    tester
        .renderObject<RenderParagraph>(
          find.descendant(of: error, matching: find.byType(RichText)),
        )
        .didExceedMaxLines,
    isFalse,
  );
  expectActions();
  await capture?.call('$prefix-error-ime');
  expect(tester.takeException(), isNull);
  await keyboard(false);
  expect(draft.text, '2027-02-30');
  await capture?.call('$prefix-error-no-ime');
  await keyboard(true);
  await tap(find.widgetWithText(TextButton, 'Cancel'), reveal: false);
  expect(find.text('Discard food changes?'), findsOneWidget);
  await capture?.call('$prefix-discard-ime');
  final explanation = find.text('Your unsaved changes will be lost.');
  await Scrollable.ensureVisible(tester.element(explanation), alignment: 1);
  await tester.pumpAndSettle();
  expectTextFragmentVisible(explanation, 'Your unsaved');
  expectTextFragmentVisible(explanation, 'lost.');
  await capture?.call('$prefix-discard-explanation-ime');
  await tap(find.text('Keep editing'));
  expect(tester.takeException(), isNull);
  expect(draft.text, '2027-02-30');
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.text('Discard food changes?'), findsOneWidget);
  await tap(find.text('Keep editing'));
  expect(draft.text, '2027-02-30');
  expect(tester.takeException(), isNull);
  await focus('Expiration');
  await tester.enterText(field('Expiration'), '2027-07-09');
  await tester.pumpAndSettle();
  await tap(
    find.widgetWithText(FilledButton, editingCount == 0 ? 'Add' : 'Save'),
    reveal: false,
  );
  expect(find.byType(AlertDialog), findsNothing);
  expect(page().state.active, hasLength(editingCount == 0 ? 1 : editingCount));
  expect(
    page().state.active.every((item) => item.details.expiry == '2027-07-09'),
    isTrue,
  );
  await keyboard(false);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadSdkRoboto);
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final count in [0, 1, 100]) {
        testWidgets(
          '320dp ${brightness.name} ${scale}x editor $count with IME/errors',
          (tester) async {
            tester.view.physicalSize = const Size(320, 640);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetViewInsets);
            addTearDown(tester.view.resetPadding);
            addTearDown(tester.view.resetViewPadding);
            await verifyFoodEditorKeyboardLayout(
              tester,
              brightness: brightness,
              textScale: scale,
              editingCount: count,
            );
          },
        );
      }
    }
  }
}
