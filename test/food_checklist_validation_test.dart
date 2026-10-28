import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_editor.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';
import 'package:tandemlog/presentation/form_validation.dart';

import 'food_editor_pane_test.dart' as pane;

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Finder get _action => find.descendant(
  of: find.byType(ValidationActionButton),
  matching: find.byType(FilledButton),
);
ValidationActionButton _actionWidget(WidgetTester tester) =>
    tester.widget<ValidationActionButton>(find.byType(ValidationActionButton));
Future<void> _activate(WidgetTester tester) async {
  await tester.ensureVisible(_action);
  await tester.tap(_action);
  await tester.pumpAndSettle();
}

Future<GlobalKey<FoodEditorState>> _food(
  WidgetTester tester, {
  List<FoodContainer>? targets,
  bool Function()? pending,
  FutureOr<void> Function(FoodDetails, int)? add,
  FutureOr<void> Function(List<FoodContainer>, FoodDetails, List<String>)?
  details,
  VoidCallback? closed,
  double scale = 1,
}) async {
  final key = GlobalKey<FoodEditorState>();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: FoodEditor(
          key: key,
          panel: true,
          state: pane.paneFoods(),
          targets: targets,
          onAdd: add ?? (_, _) {},
          onDetails: details ?? (_, _, _) {},
          pending: pending ?? () => false,
          isOriginCurrent: () => true,
          areTargetsVisible: () => true,
          onBulkApplied: () {},
          onClosed: (_) => closed?.call(),
          onDisposed: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

Future<void> _checklist(
  WidgetTester tester, {
  required Future<void> Function(String, String) save,
  bool Function()? pending,
  VoidCallback? close,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: ChecklistItemEditor(
          save: save,
          hasPendingReceipt: pending,
          onClose: close ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Food modal opens vertically centered and keeps its actions through review',
    (tester) async {
      // Tall enough that the narrow modal is shorter than the window: RC.5
      // anchored it to the bottom edge instead (Lee, 10-27).
      await pane.mountFoodPane(tester, width: 420, height: 1600);
      await pane.openPaneAdd(tester);
      final dialog = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first;
      final opened = tester.getRect(dialog);
      expect(opened.height, lessThan(1600 - 64));
      expect(
        (opened.top - (1600 - opened.bottom)).abs(),
        lessThanOrEqualTo(1),
        reason: 'The editor must open centered vertically',
      );
      final initialAction = tester.getRect(_action);
      await _activate(tester);
      expect(
        find.descendant(of: _action, matching: find.text('Review errors')),
        findsOneWidget,
      );
      expect(tester.getRect(dialog).height, greaterThan(opened.height));
      expect(tester.getRect(dialog).bottom, opened.bottom);
      expect(
        tester.getRect(_action),
        initialAction,
        reason: 'Validation text grows upward without moving the actions',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final food in [true, false]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '${food ? 'Food' : 'Checklist'} modal keeps whole action rect through review and correction at ${scale}x',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(420, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var writes = 0;
          if (food) {
            await pane.mountFoodPane(
              tester,
              width: 420,
              height: 900,
              scale: scale,
              onAdd: (_, _) => writes++,
            );
            await pane.openPaneAdd(tester);
          } else {
            await _checklist(
              tester,
              scale: scale,
              save: (_, _) async {
                writes++;
              },
            );
          }
          final actionElement = tester.element(_action);
          final initialRect = tester.getRect(_action);
          expect(_action.hitTestable(), findsOneWidget);
          expect(_actionWidget(tester).validation.reviewRequired, isFalse);
          await _activate(tester);
          expect(writes, 0);
          expect(identical(tester.element(_action), actionElement), isTrue);
          expect(
            tester.getRect(_action),
            initialRect,
            reason: 'Showing local errors must not move or resize the action',
          );
          expect(
            find.descendant(of: _action, matching: find.text('Review errors')),
            findsOneWidget,
          );
          final title = food
              ? _field('Food name')
              : find.byKey(const Key('checklist-item-title'));
          expect(
            tester.widget<TextField>(title).decoration!.errorText,
            isNotNull,
          );
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: title,
                    matching: find.byType(EditableText),
                  ),
                )
                .focusNode
                .hasFocus,
            isTrue,
          );
          await tester.enterText(title, 'Synthetic corrected title');
          if (food) {
            await tester.ensureVisible(_field('Expiration'));
            await tester.enterText(_field('Expiration'), '2026-10-20');
          }
          await tester.pumpAndSettle();
          expect(writes, 0);
          expect(
            tester.getRect(_action),
            initialRect,
            reason:
                'Correcting revealed errors must keep the same action bounds',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(title).decoration!.errorText, isNull);
          expect(
            find.descendant(
              of: _action,
              matching: find.text(food ? 'Add' : 'Save item'),
            ),
            findsOneWidget,
          );
          expect(tester.getRect(_action), initialRect);
          expect(_action.hitTestable(), findsOneWidget);
          expect(writes, 0);
          await _activate(tester);
          expect(writes, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Food pristine Add is enabled; review reveals/focuses first field without writing',
    (tester) async {
      var writes = 0;
      await _food(tester, add: (_, _) => writes++);
      expect(tester.widget<FilledButton>(_action).onPressed, isNotNull);
      expect(_actionWidget(tester).validation.reviewRequired, isFalse);
      expect(
        tester.widget<TextField>(_field('Food name')).decoration!.errorText,
        isNull,
      );
      expect(
        tester.widget<TextField>(_field('Expiration')).decoration!.errorText,
        isNull,
      );
      await _activate(tester);
      expect(writes, 0);
      expect(_actionWidget(tester).validation.reviewRequired, isTrue);
      final name = tester.widget<TextField>(_field('Food name'));
      expect(name.decoration!.errorText, 'Enter a food name.');
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: _field('Food name'),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(
        tester.widget<TextField>(_field('Expiration')).decoration!.errorText,
        'Expiration is required.',
      );
      await _activate(tester);
      expect(writes, 0, reason: 'Review never becomes Save while activated');
    },
  );

  testWidgets(
    'Food invalid partial date stays quiet until blur; correction permits one Add',
    (tester) async {
      var writes = 0;
      final key = await _food(tester, add: (_, _) => writes++);
      await tester.enterText(_field('Food name'), 'Synthetic food');
      await tester.enterText(_field('Expiration'), '2026-02-30');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_field('Expiration')).decoration!.errorText,
        isNull,
      );
      expect(_actionWidget(tester).validation.reviewRequired, isFalse);
      await tester.tap(_field('Container size'));
      await tester.pumpAndSettle();
      expect(_actionWidget(tester).validation.reviewRequired, isTrue);
      expect(
        tester.widget<TextField>(_field('Expiration')).decoration!.errorText,
        'Invalid food expiration.',
      );
      await _activate(tester);
      expect(key.currentState!.expiryFocus.hasFocus, isTrue);
      expect(writes, 0);
      await tester.enterText(_field('Expiration'), '2026-10-20');
      await tester.tap(_field('Container size'));
      await tester.pumpAndSettle();
      expect(_actionWidget(tester).validation.reviewRequired, isFalse);
      await _activate(tester);
      expect(writes, 1);
    },
  );

  testWidgets(
    'Food bulk validates only applied fields and an applied blank clears',
    (tester) async {
      final state = pane.paneFoods();
      final calls =
          <({List<String> ids, FoodDetails details, List<String> fields})>[];
      final key = await _food(
        tester,
        targets: state.containers,
        details: (items, details, fields) {
          calls.add((
            ids: items.map((item) => item.id).toList(),
            details: details,
            fields: List.of(fields),
          ));
        },
      );
      expect(_actionWidget(tester).validation.reviewRequired, isFalse);
      // An applied blank Food name is the one rejected clear.
      await tester.tap(find.byKey(const ValueKey('nameApply')));
      key.currentState!.name.clear();
      await tester.pumpAndSettle();
      await _activate(tester);
      expect(calls, isEmpty);
      expect(
        tester.widget<TextField>(_field('Food name')).decoration!.errorText,
        'Enter a food name.',
      );
      await tester.tap(find.byKey(const ValueKey('nameApply')));
      key.currentState!.brand.clear();
      if (!key.currentState!.applied.contains('brand')) {
        await tester.tap(find.byKey(const ValueKey('brandApply')));
      }
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(_actionWidget(tester).validation.reviewRequired, isFalse);
      expect(
        tester.widget<TextField>(_field('Brand')).decoration!.errorText,
        isNull,
      );
      await _activate(tester);
      expect(calls, hasLength(1));
      expect(
        calls.single.ids,
        state.containers.map((item) => item.id).toList(),
      );
      expect(calls.single.fields, ['brand']);
      expect(calls.single.details.brand, '');
      expect(
        calls.single.details.location,
        state.containers.first.details.location,
      );
    },
  );

  testWidgets(
    'Food retry reuses immutable details/count even after controller changes',
    (tester) async {
      var pending = false, closed = 0;
      final calls = <(FoodDetails, int)>[];
      final key = await _food(
        tester,
        pending: () => pending,
        closed: () => closed++,
        add: (details, count) {
          calls.add((details, count));
          if (calls.length == 1) {
            pending = true;
            throw StateError('Synthetic uncertain save');
          }
          pending = false;
        },
      );
      await tester.enterText(_field('Food name'), 'Synthetic captured food');
      await tester.enterText(_field('Expiration'), '2026-10-20');
      await tester.enterText(_field('Containers to add'), '2');
      await _activate(tester);
      expect(calls, hasLength(1));
      expect(_actionWidget(tester).retry, isTrue);
      expect(closed, 0);
      key.currentState!.name.text = '';
      key.currentState!.expiry.text = 'not a date';
      key.currentState!.count.text = '0';
      await tester.pumpAndSettle();
      await _activate(tester);
      expect(calls, hasLength(2));
      expect(identical(calls.first.$1, calls.last.$1), isTrue);
      expect(calls.last.$2, 2);
      expect(closed, 1);
    },
  );

  testWidgets('Food held Save admits only one callback', (tester) async {
    final completion = Completer<void>();
    var calls = 0;
    await _food(
      tester,
      add: (_, _) {
        calls++;
        return completion.future;
      },
    );
    await tester.enterText(_field('Food name'), 'Synthetic held food');
    await tester.enterText(_field('Expiration'), '2026-10-20');
    final press = tester.widget<FilledButton>(_action).onPressed!;
    press();
    press();
    await tester.pump();
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<FilledButton>(_action).onPressed, isNull);
    completion.complete();
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets(
    'Checklist pristine and partial title review inline without callback',
    (tester) async {
      final calls = <(String, String)>[];
      await _checklist(
        tester,
        save: (title, notes) async => calls.add((title, notes)),
      );
      final title = find.byKey(const Key('checklist-item-title'));
      final notes = find.byKey(const Key('checklist-item-notes'));
      expect(tester.widget<FilledButton>(_action).onPressed, isNotNull);
      expect(tester.widget<TextField>(title).decoration!.errorText, isNull);
      await tester.enterText(title, ' ');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(title).decoration!.errorText, isNull);
      await tester.tap(notes);
      await tester.pumpAndSettle();
      expect(_actionWidget(tester).validation.reviewRequired, isTrue);
      await _activate(tester);
      expect(calls, isEmpty);
      expect(tester.widget<TextField>(title).focusNode!.hasFocus, isTrue);
      expect(
        tester.widget<TextField>(title).decoration!.errorText,
        'Enter a checklist item title.',
      );
      await tester.enterText(title, 'Synthetic item');
      await tester.tap(notes);
      await tester.enterText(notes, 'Synthetic notes');
      await tester.pumpAndSettle();
      expect(_actionWidget(tester).validation.reviewRequired, isFalse);
      await _activate(tester);
      expect(calls, [('Synthetic item', 'Synthetic notes')]);
    },
  );

  testWidgets(
    'Checklist composition review never submits and pending retry keeps first intent',
    (tester) async {
      var pending = false, closed = 0;
      final calls = <(String, String)>[];
      await _checklist(
        tester,
        pending: () => pending,
        close: () => closed++,
        save: (title, notes) async {
          calls.add((title, notes));
          if (calls.length == 1) {
            pending = true;
            throw StateError('Synthetic uncertain item');
          }
          pending = false;
        },
      );
      final title = tester
          .widget<TextField>(find.byKey(const Key('checklist-item-title')))
          .controller!;
      final notes = tester
          .widget<TextField>(find.byKey(const Key('checklist-item-notes')))
          .controller!;
      await tester.tap(find.byKey(const Key('checklist-item-title')));
      await tester.pumpAndSettle();
      title.value = const TextEditingValue(
        text: 'Synthetic item',
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 0, end: 9),
      );
      expect(title.value.composing, const TextRange(start: 0, end: 9));
      tester.widget<FilledButton>(_action).onPressed!();
      await tester.pumpAndSettle();
      expect(title.value.composing, const TextRange(start: 0, end: 9));
      expect(calls, isEmpty);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('checklist-item-title')))
            .decoration!
            .errorText,
        'Finish entering text before saving.',
      );
      title.value = const TextEditingValue(text: 'Synthetic item');
      notes.text = 'Captured notes';
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _activate(tester);
      expect(calls, [('Synthetic item', 'Captured notes')]);
      expect(_actionWidget(tester).retry, isTrue);
      title.text = '';
      notes.text = 'Changed after captured save';
      await tester.pumpAndSettle();
      await _activate(tester);
      expect(calls, [
        ('Synthetic item', 'Captured notes'),
        ('Synthetic item', 'Captured notes'),
      ]);
      expect(closed, 1);
    },
  );

  testWidgets(
    'Checklist review with 200 percent text and keyboard keeps actions visible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 720);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      var calls = 0;
      await _checklist(
        tester,
        scale: 2,
        save: (_, _) async {
          calls++;
        },
      );
      await _activate(tester);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(_action).bottom, lessThanOrEqualTo(440));
      expect(tester.getRect(_action).height, greaterThanOrEqualTo(48));
    },
  );
  testWidgets(
    'Food autocomplete limits and count composition reveal only their own fields',
    (tester) async {
      var calls = 0;
      final key = await _food(tester, add: (_, _) => calls++);
      await tester.enterText(_field('Food name'), 'Synthetic food');
      await tester.enterText(_field('Expiration'), '2026-10-20');
      await tester.enterText(_field('Brand'), List.filled(201, 'x').join());
      await tester.tap(_field('Container size'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_field('Brand')).decoration!.errorText,
        'Brand must be 200 characters or fewer.',
      );
      await _activate(tester);
      expect(calls, 0);
      key.currentState!.brand.text = 'Synthetic brand';
      key.currentState!.count.value = const TextEditingValue(
        text: '2',
        composing: TextRange(start: 0, end: 1),
      );
      await _activate(tester);
      expect(calls, 0);
      expect(
        tester
            .widget<TextField>(_field('Containers to add'))
            .decoration!
            .errorText,
        'Finish composing text before saving.',
      );
      expect(
        tester.widget<TextField>(_field('Expiration')).decoration!.errorText,
        isNull,
      );
    },
  );

  testWidgets(
    'Checklist notes limit reviews the actual notes input without saving',
    (tester) async {
      var calls = 0;
      await _checklist(
        tester,
        save: (_, _) async {
          calls++;
        },
      );
      await tester.enterText(
        find.byKey(const Key('checklist-item-title')),
        'Synthetic item',
      );
      final notes = tester
          .widget<TextField>(find.byKey(const Key('checklist-item-notes')))
          .controller!;
      notes.text = List.filled(10001, 'x').join();
      await _activate(tester);
      expect(calls, 0);
      final field = tester.widget<TextField>(
        find.byKey(const Key('checklist-item-notes')),
      );
      expect(
        field.decoration!.errorText,
        'Notes must be 10000 characters or fewer.',
      );
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('checklist-item-title')))
            .decoration!
            .errorText,
        isNull,
      );
    },
  );
  for (final food in [true, false]) {
    testWidgets(
      '${food ? 'Food' : 'Checklist'} long operational failure stays beside accessible actions with keyboard and enlarged text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 720);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final message = List.filled(
          12,
          'Synthetic provider failure with recovery detail.',
        ).join(' ');
        var calls = 0;
        var pending = false;
        if (food) {
          await _food(
            tester,
            scale: 2,
            pending: () => pending,
            add: (_, _) {
              calls++;
              pending = true;
              throw StateError(message);
            },
          );
          await tester.enterText(_field('Food name'), 'Synthetic food');
          await tester.enterText(_field('Expiration'), '2026-10-20');
        } else {
          await _checklist(
            tester,
            scale: 2,
            pending: () => pending,
            save: (_, _) async {
              calls++;
              pending = true;
              throw StateError(message);
            },
          );
          await tester.enterText(
            find.byKey(const Key('checklist-item-title')),
            'Synthetic item',
          );
        }
        await _activate(tester);
        expect(calls, 1);
        expect(tester.takeException(), isNull);
        expect(tester.getRect(_action).bottom, lessThanOrEqualTo(440));
        expect(tester.getRect(_action).height, greaterThanOrEqualTo(48));
        expect(
          find.textContaining('Synthetic provider failure'),
          findsOneWidget,
        );
        final notice = find.ancestor(
          of: find.textContaining('Synthetic provider failure'),
          matching: find.byType(Semantics),
        );
        expect(
          tester
              .widgetList<Semantics>(notice)
              .any((widget) => widget.properties.liveRegion == true),
          isTrue,
        );
      },
    );
  }
  testWidgets(
    'Food unapplied invalid bulk draft cannot block a different applied field',
    (tester) async {
      final state = pane.paneFoods();
      final calls = <(FoodDetails, List<String>)>[];
      final key = await _food(
        tester,
        targets: state.containers,
        details: (_, details, fields) {
          calls.add((details, List.of(fields)));
        },
      );
      // Editing applies a field; unchecking Apply keeps the draft unapplied.
      await tester.enterText(_field('Brand'), List.filled(201, 'x').join());
      await tester.pumpAndSettle();
      expect(key.currentState!.applied, contains('brand'));
      await tester.tap(find.byKey(const ValueKey('brandApply')));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Location'), 'Synthetic shelf');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(_actionWidget(tester).validation.reviewRequired, isFalse);
      expect(
        tester.widget<TextField>(_field('Brand')).decoration!.errorText,
        isNull,
      );
      await _activate(tester);
      expect(calls, hasLength(1));
      expect(calls.single.$2, ['location']);
      expect(calls.single.$1.location, 'Synthetic shelf');
      expect(calls.single.$1.brand, state.containers.first.details.brand);
      expect(
        key.currentState!.brand.text.length,
        201,
        reason: 'Unapplied draft text is preserved, not silently repaired',
      );
    },
  );
  for (final food in [true, false]) {
    testWidgets(
      '${food ? 'Food' : 'Checklist'} stale action cannot review behind a newer auxiliary route',
      (tester) async {
        var calls = 0;
        if (food) {
          await _food(tester, add: (_, _) => calls++);
        } else {
          await _checklist(
            tester,
            save: (_, _) async {
              calls++;
            },
          );
        }
        final stale = tester.widget<FilledButton>(_action).onPressed!;
        final owner = tester.element(
          find.byType(food ? FoodEditor : ChecklistItemEditor),
        );
        unawaited(
          Navigator.of(owner).push<void>(
            DialogRoute<void>(
              context: owner,
              builder: (context) => AlertDialog(
                title: const Text('Synthetic auxiliary route'),
                content: const TextField(
                  key: Key('auxiliary-input'),
                  autofocus: true,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close auxiliary'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final auxiliary = tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const Key('auxiliary-input')),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode;
        expect(auxiliary.hasFocus, isTrue);
        expect(tester.widget<FilledButton>(_action).onPressed, isNull);
        stale();
        await tester.pumpAndSettle();
        expect(calls, 0);
        expect(auxiliary.hasFocus, isTrue);
        expect(find.text('Synthetic auxiliary route'), findsOneWidget);
        await tester.tap(find.text('Close auxiliary'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
