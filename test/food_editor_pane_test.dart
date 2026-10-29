import 'package:tandemlog/presentation/civil_date_input.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_editor.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/editor_surface.dart';
import 'package:tandemlog/presentation/tandemlog_theme.dart';

const _writer = '00000000-0000-4000-8000-000000000093';
FoodState paneFoods() => projectFood([
  for (var i = 1; i <= 2; i++)
    FoodOperation(
      id: '$_writer:$i',
      order: i,
      action: FoodAction.add,
      targets: ['00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}'],
      details: FoodDetails(
        name: 'Pane beans $i',
        brand: 'Synthetic brand',
        expiry: '2026-10-20',
        size: '500 g',
        location: 'Pantry',
        estimated: true,
      ),
      contents: const Contents.fraction(1, 3),
      createdAt: '2026-10-15T00:00:00Z',
    ),
]);

Finder get foodAction => find.byKey(const ValueKey('food-save-action'));

Finder foodField(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
TextEditingController controller(WidgetTester tester, String label) =>
    tester.widget<TextField>(foodField(label)).controller!;

Future<GlobalKey<FoodInventoryPageState>> mountFoodPane(
  WidgetTester tester, {
  double width = 1200,
  double height = 900,
  double scale = 1,
  Brightness brightness = Brightness.light,
  FoodState? state,
  FutureOr<void> Function(FoodDetails, int)? onAdd,
  FutureOr<void> Function(
    List<FoodContainer>,
    FoodDetails,
    List<String>,
    FoodProductChange,
  )?
  onDetails,
  FutureOr<void> Function(List<String>)? onRemove,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final key = GlobalKey<FoodInventoryPageState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: tandemlogTheme(
        brightness,
      ).copyWith(platform: TargetPlatform.linux),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: FoodInventoryPage(
        key: key,
        state: state ?? paneFoods(),
        workspaceIdentity: 'synthetic-pane-workspace',
        now: () => DateTime(2026, 10, 15),
        onAdd: onAdd ?? (_, _) {},
        onRemove: onRemove ?? (_) {},
        onRestore: (_) {},
        onDetails: onDetails ?? (_, _, _, _) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

Future<void> openPaneAdd(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add food'));
  await tester.pumpAndSettle();
}

Future<void> discardPane(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  await tester.pumpAndSettle();
  if (find.text('Discard food changes?').evaluate().isNotEmpty) {
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
  }
}

Future<void> openPaneFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('food-filter')));
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .byWidgetPredicate(
          (w) => w is PopupMenuItem<FoodView> && w.onTap != null,
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() => registerFoodEditorPaneTests();

void registerFoodEditorPaneTests() {
  testWidgets('selection swaps keep the wide pane mounted in every frame', (
    tester,
  ) async {
    await mountFoodPane(tester);
    await tester.tap(find.text('Pane beans 1'));
    await tester.pumpAndSettle();
    final widths = <double>[];
    var observing = true;
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (observing &&
          find.byKey(const ValueKey('food-search')).evaluate().isNotEmpty) {
        widths.add(
          (find
                      .byKey(const ValueKey('food-search'))
                      .evaluate()
                      .single
                      .findRenderObject()!
                  as RenderBox)
              .size
              .width,
        );
      }
    });
    final width = tester
        .getSize(find.byKey(const ValueKey('food-search')))
        .width;
    await tester.tap(find.text('Pane beans 2').first);
    await tester.pumpAndSettle();
    observing = false;
    expect(controller(tester, 'Food name').text, 'Pane beans 2');
    expect(
      widths,
      everyElement(width),
      reason: 'No intervening frame may close the pane.',
    );
    final editor = tester.element(find.byType(FoodEditor));
    await tester.tap(find.text('Pane beans 2').first);
    await tester.pumpAndSettle();
    expect(
      tester.element(find.byType(FoodEditor)),
      same(editor),
      reason: 'Plain sole-row click is a no-op.',
    );
  });

  testWidgets(
    'dirty replacement keeps its draft and does not acknowledge a concurrent close',
    (tester) async {
      final key = await mountFoodPane(tester);
      await tester.tap(find.text('Pane beans 1').first);
      await tester.pumpAndSettle();
      await tester.enterText(foodField('Food name'), 'Unsaved beans');
      await tester.tap(find.text('Pane beans 2').first);
      await tester.pumpAndSettle();
      expect(find.text('Discard food changes?'), findsOneWidget);
      expect(await key.currentState!.requestCloseEditor(), isFalse);
      await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
      await tester.pumpAndSettle();
      expect(controller(tester, 'Food name').text, 'Unsaved beans');
      await tester.tap(find.text('Pane beans 2').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(controller(tester, 'Food name').text, 'Pane beans 2');
    },
  );

  testWidgets('Space toggles off a plain opened sole Food row', (tester) async {
    await mountFoodPane(tester);
    final row = find.text('Pane beans 1').first;
    await tester.tap(row);
    await tester.pumpAndSettle();
    Focus.of(tester.element(row)).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byType(FoodEditor), findsNothing);
  });

  testWidgets(
    'narrow editor stays above keyboard after Review and after field focus ends',
    (tester) async {
      var writes = 0;
      await mountFoodPane(
        tester,
        width: 320,
        height: 640,
        onAdd: (_, _) => writes++,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpAndSettle();
      await openPaneAdd(tester);
      await tester.enterText(foodField('Food name'), 'Synthetic beans');
      await tester.ensureVisible(foodField('Expiration'));
      await tester.enterText(foodField('Expiration'), '2027-02-30');
      await tester.pumpAndSettle();
      final add = foodAction;
      final actionElement = tester.element(add);
      await tester.tap(add, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.text('Invalid food expiration.'), findsOneWidget);
      expect(writes, 0);
      expect(controller(tester, 'Food name').text, 'Synthetic beans');
      expect(controller(tester, 'Expiration').text, '2027-02-30');
      expect(identical(tester.element(foodAction), actionElement), isTrue);
      expect(
        find.descendant(of: foodAction, matching: find.text('Review errors')),
        findsOneWidget,
      );
      // Review focuses the first invalid input. Independently exercise the
      // original unfocused-field/still-open-IME geometry boundary as well.
      final expiry = tester.widget<EditableText>(
        find.descendant(
          of: foodField('Expiration'),
          matching: find.byType(EditableText),
        ),
      );
      expect(expiry.focusNode.hasFocus, isTrue);
      expiry.focusNode.unfocus();
      await tester.pumpAndSettle();
      expect(expiry.focusNode.hasFocus, isFalse);
      expect(tester.view.viewInsets.bottom, 280);
      final error = find.text('Invalid food expiration.');
      await Scrollable.ensureVisible(tester.element(error), alignment: 1);
      await tester.pumpAndSettle();
      expect(error.hitTestable(), findsOneWidget);
      expect(tester.getRect(error).bottom, lessThanOrEqualTo(360));
      for (final action in [find.widgetWithText(TextButton, 'Cancel'), add]) {
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(360));
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'wide Edit and Add share Tasks pane geometry without moving outer edges',
    (tester) async {
      await mountFoodPane(tester, width: 1800);
      final search = find.byKey(const ValueKey('food-search'));
      final before = tester.getRect(search);
      await tester.tap(find.text('Pane beans 1'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller(tester, 'Food name').text, 'Pane beans 1');
      expect(find.text('Retention reason'), findsWidgets);
      final after = tester.getRect(search);
      expect(after.left, before.left);
      expect(before.right - after.right, EditorSurface.panelWidth + 1);
      expect(tester.getSize(find.byType(VerticalDivider)).width, 1);
      await discardPane(tester);
      expect(tester.getRect(search), before);
      await openPaneAdd(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller(tester, 'Food name').text, isEmpty);
      expect(find.text('Retention reason'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resize preserves dirty values, caret, composition, focus and pending calendar date',
    (tester) async {
      await mountFoodPane(tester);
      await openPaneAdd(tester);
      await tester.tap(foodField('Food name'));
      final name = controller(tester, 'Food name');
      const draft = TextEditingValue(
        text: 'Synthetic beans',
        selection: TextSelection(baseOffset: 2, extentOffset: 8),
        composing: TextRange(start: 1, end: 9),
      );
      name.value = draft;
      for (final width in [650.0, 1200.0, 899.0, 900.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(controller(tester, 'Food name'), same(name));
        expect(name.value, draft);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: foodField('Food name'),
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(
          find.byType(AlertDialog),
          width < 900 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      name.value = draft.copyWith(composing: TextRange.empty);
      await tester.tap(find.byTooltip('Choose Expiration'));
      await tester.pumpAndSettle();
      expect(find.byType(CivilDatePickerDialog), findsOneWidget);
      final calendarDraft = name.value;
      expect(calendarDraft, draft.copyWith(composing: TextRange.empty));
      tester.view.physicalSize = const Size(650, 900);
      await tester.pumpAndSettle();
      expect(find.byType(CivilDatePickerDialog), findsOneWidget);
      expect(controller(tester, 'Food name'), same(name));
      expect(name.value, calendarDraft);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(controller(tester, 'Expiration').text, isNotEmpty);
      expect(controller(tester, 'Food name'), same(name));
      final field = tester.widget<EditableText>(
        find.descendant(
          of: foodField('Food name'),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.focusNode.hasFocus, isTrue);
      // Calendar pop restores focus. Flutter's existing desktop/web policy
      // selects all on that focus transition; resizing itself preserves the
      // exact value above, including while the calendar remains open.
      final selectsAllOnFocus =
          kIsWeb ||
          switch (defaultTargetPlatform) {
            TargetPlatform.linux ||
            TargetPlatform.macOS ||
            TargetPlatform.windows => true,
            TargetPlatform.android ||
            TargetPlatform.iOS ||
            TargetPlatform.fuchsia => false,
          };
      expect(field.selectAllOnFocus, selectsAllOnFocus);
      expect(
        name.value,
        calendarDraft.copyWith(
          selection: selectsAllOnFocus
              ? TextSelection(
                  baseOffset: 0,
                  extentOffset: calendarDraft.text.length,
                )
              : calendarDraft.selection,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'row switch and Add another serialize discard decisions and preserve template defaults',
    (tester) async {
      var writes = 0;
      final state = paneFoods();
      final before = jsonEncode(
        state.containers.map((e) => e.toJson()).toList(),
      );
      final key = await mountFoodPane(
        tester,
        state: state,
        onAdd: (_, _) => writes++,
        onDetails: (_, _, _, _) => writes++,
      );
      await tester.tap(find.text('Pane beans 1'));
      await tester.pumpAndSettle();
      await tester.enterText(foodField('Food name'), 'Unsaved beans');
      await tester.tap(find.text('Pane beans 2').first);
      await tester.pumpAndSettle();
      expect(find.text('Discard food changes?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
      await tester.pumpAndSettle();
      expect(controller(tester, 'Food name').text, 'Unsaved beans');
      await tester.tap(find.byTooltip('Actions for Pane beans 2'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String> && w.value == 'add-another',
        ),
      );
      await tester.pumpAndSettle();
      final firstClose = key.currentState!.requestCloseEditor();
      final secondClose = key.currentState!.requestCloseEditor();
      final discard = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Discard'))
          .onPressed!;
      discard();
      discard();
      await tester.pumpAndSettle();
      expect(
        await firstClose,
        isFalse,
        reason: 'A replacement decision is not a close acknowledgement.',
      );
      expect(await secondClose, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller(tester, 'Food name').text, 'Pane beans 2');
      for (final value in [
        ('Brand', 'Synthetic brand'),
        ('Container size', '500 g'),
        ('Location', 'Pantry'),
        ('Expiration', ''),
        ('Containers to add', '1'),
      ]) {
        expect(controller(tester, value.$1).text, value.$2);
      }
      expect(
        tester.widget<TextField>(foodField('Expiration')).focusNode!.hasFocus,
        isTrue,
      );
      expect(find.text('Retention reason'), findsNothing);
      expect(writes, 0);
      expect(
        jsonEncode(state.containers.map((e) => e.toJson()).toList()),
        before,
      );
    },
  );

  testWidgets(
    'duplicate captured Save cannot reenter or release a held command',
    (tester) async {
      final held = Completer<void>();
      var calls = 0;
      final key = await mountFoodPane(
        tester,
        onAdd: (_, _) {
          calls++;
          return held.future;
        },
      );
      await openPaneAdd(tester);
      await tester.enterText(foodField('Food name'), 'Held beans');
      await tester.enterText(foodField('Expiration'), '2026-10-20');
      final save = tester.widget<FilledButton>(foodAction).onPressed!;
      save();
      save();
      await tester.pump();
      expect(calls, 1);
      expect(key.currentState!.closeBusy, isTrue);
      expect(await key.currentState!.requestCloseEditor(), isFalse);
      expect(tester.widget<TextField>(foodField('Food name')).enabled, isFalse);
      expect(tester.widget<FilledButton>(foodAction).onPressed, isNull);
      held.complete();
      await tester.pumpAndSettle();
      save();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Add food'), findsNothing);
      expect(key.currentState!.editorDone, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calendar defers host close and page disposal completes editor readiness',
    (tester) async {
      final key = await mountFoodPane(tester);
      await openPaneAdd(tester);
      final done = key.currentState!.editorDone!;
      await tester.tap(find.byTooltip('Choose Expiration'));
      await tester.pumpAndSettle();
      expect(key.currentState!.closeBusy, isTrue);
      expect(await key.currentState!.requestCloseEditor(), isFalse);
      expect(find.byType(CivilDatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(key.currentState!.closeBusy, isFalse);
      var disposed = false;
      unawaited(done.then((_) => disposed = true));
      await tester.pumpWidget(const MaterialApp(home: Text('Other page')));
      await tester.pumpAndSettle();
      expect(disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page disposal completes an editor request before its first frame mounts',
    (tester) async {
      final key = await mountFoodPane(tester);
      tester
          .widget<FoodInventoryToolbar>(find.byType(FoodInventoryToolbar))
          .onAdd!();
      final done = key.currentState!.editorDone!;
      expect(find.byType(FoodEditor), findsNothing);
      var completed = false;
      unawaited(done.then((_) => completed = true));
      await tester.pumpWidget(
        const MaterialApp(home: Text('Replacement page')),
      );
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale Save under filters is ignored and accepted save waits for its overlay to finish',
    (tester) async {
      var calls = 0;
      final held = Completer<void>();
      final key = await mountFoodPane(
        tester,
        onAdd: (_, _) {
          calls++;
          return held.future;
        },
      );
      await openPaneAdd(tester);
      await tester.enterText(foodField('Food name'), 'Overlay save beans');
      await tester.enterText(foodField('Expiration'), '2026-10-20');
      final save = tester.widget<FilledButton>(foodAction).onPressed!;
      await openPaneFilters(tester);
      save();
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      save();
      await tester.pump();
      expect(calls, 1);
      await openPaneFilters(tester);
      held.complete();
      await tester.pumpAndSettle();
      expect(key.currentState!.editorDone, isNotNull);
      expect(key.currentState!.closeBusy, isTrue);
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(key.currentState!.editorDone, isNull);
      expect(find.text('Add food'), findsNothing);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'autocomplete suggestions retain field ownership and dismiss safely after resizing',
    (tester) async {
      await mountFoodPane(tester);
      await openPaneAdd(tester);
      await tester.enterText(foodField('Brand'), 'Syn');
      await tester.pumpAndSettle();
      final brand = controller(tester, 'Brand');
      expect(find.text('Synthetic brand'), findsWidgets);
      tester.view.physicalSize = const Size(650, 900);
      await tester.pumpAndSettle();
      expect(controller(tester, 'Brand'), same(brand));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(brand.text, 'Syn');
      expect(find.text('Discard food changes?'), findsNothing);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: foodField('Brand'),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow modal traps background focus and guards Back and Escape',
    (tester) async {
      await mountFoodPane(tester, width: 650);
      await openPaneAdd(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(foodField('Food name'), 'Narrow draft');
      for (var i = 0; i < 15; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context;
        expect(
          focused?.findAncestorWidgetOfExactType<AlertDialog>(),
          isNotNull,
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard food changes?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
      await tester.pumpAndSettle();
      await tester.tap(foodField('Food name'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Discard food changes?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('food-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide row remove stays separate from the unsaved edit draft', (
    tester,
  ) async {
    final removes = <List<String>>[];
    var edits = 0;
    await mountFoodPane(
      tester,
      onRemove: removes.add,
      onDetails: (_, _, _, _) => edits++,
    );
    await tester.tap(find.text('Pane beans 1'));
    await tester.pumpAndSettle();
    await tester.enterText(foodField('Food name'), 'Draft only');
    await tester.tap(find.byTooltip('Remove one Pane beans 2 container'));
    await tester.pumpAndSettle();
    expect(removes, hasLength(1));
    expect(removes.single, ['00000000-0000-4000-8000-000000000002']);
    expect(controller(tester, 'Food name').text, 'Draft only');
    expect(edits, 0);
    expect(find.text('Discard food changes?'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('food-search')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('food-search')),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Discard food changes?'), findsOneWidget);
  });

  testWidgets(
    'wide pane allows Tab to return to inventory and joins an existing close decision',
    (tester) async {
      final key = await mountFoodPane(tester);
      await openPaneAdd(tester);
      var reachedInventory = false;
      for (var i = 0; i < 30; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused != null &&
            focused.findAncestorWidgetOfExactType<FoodEditor>() == null) {
          reachedInventory = true;
          break;
        }
      }
      expect(reachedInventory, isTrue);
      await tester.enterText(foodField('Food name'), 'Shared close draft');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(
        key.currentState!.closeBusy,
        isFalse,
        reason: 'An owned close decision can accept another host close request',
      );
      final close = key.currentState!.requestCloseEditor();
      await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
      await tester.pumpAndSettle();
      expect(await close, isFalse);
      expect(find.text('Discard food changes?'), findsNothing);
      expect(controller(tester, 'Food name').text, 'Shared close draft');
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'short 200 percent ${brightness.name} pane keeps errors and actions reachable',
      (tester) async {
        var writes = 0;
        await mountFoodPane(
          tester,
          onAdd: (_, _) => writes++,
          width: 1000,
          height: 480,
          scale: 2,
          brightness: brightness,
        );
        await openPaneAdd(tester);
        await tester.tap(foodAction);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Expiration is required.'));
        await tester.pumpAndSettle();
        expect(find.text('Expiration is required.'), findsOneWidget);
        expect(writes, 0);
        expect(
          find.descendant(of: foodAction, matching: find.text('Review errors')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: foodField('Food name'),
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(
          tester.getRect(find.widgetWithText(TextButton, 'Cancel')).bottom,
          lessThanOrEqualTo(480),
        );
        expect(tester.getRect(foodAction).bottom, lessThanOrEqualTo(480));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
