import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/checklist_panel.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';
import 'package:tandemlog/presentation/title_line_formatter.dart';

final panelOrigin = Object();

const titleKey = Key('checklist-item-title');
const notesKey = Key('checklist-item-notes');
const saveKey = Key('checklist-item-save');
const cancelKey = Key('checklist-item-cancel');

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
  bool dark = false,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('checklist-visual'),
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: 'Roboto',
        ),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['CHECKLIST_VISUAL_DIR'];
  if (directory == null) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('checklist-visual')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

List<Map<String, dynamic>> dragItems() => [
  for (final id in ['0', '1', '2'])
    {'id': id, 'title': 'Item $id', 'completed': false},
];

ChecklistPanel dragPanel({
  List<Map<String, dynamic>>? items,
  bool enabled = true,
  Object revision = 'snapshot-1',
  FocusNode? addFocusNode,
  required void Function(Map<String, dynamic>, String?) onMove,
}) => ChecklistPanel(
  parentId: 'parent',
  origin: panelOrigin,
  revision: revision,
  items: items ?? dragItems(),
  enabled: enabled,
  addFocusNode: addFocusNode,
  onAdd: () {},
  onEdit: (_) {},
  onToggle: (_, _) {},
  onMove: onMove,
  onDelete: (_) {},
);

void main() {
  test(
    'title normalization respects composition and selection-only history',
    () {
      final formatter = TitleLineFormatter();
      const historical = TextEditingValue(
        text: 'Old\nTitle',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(
        formatter
            .formatEditUpdate(
              historical,
              historical.copyWith(
                selection: const TextSelection.collapsed(offset: 1),
              ),
            )
            .text,
        historical.text,
      );
      const composing = TextEditingValue(
        text: 'A\r\nB\u2028C',
        composing: TextRange(start: 0, end: 4),
        selection: TextSelection.collapsed(offset: 6),
      );
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, composing),
        composing,
      );
      final committed = formatter.formatEditUpdate(
        composing,
        composing.copyWith(composing: TextRange.empty),
      );
      expect(committed.text, 'A B C');
      expect(committed.selection.extentOffset, 5);
    },
  );

  testWidgets(
    'panel exposes check/edit/add, relative moves and edge restrictions',
    (tester) async {
      final items = [
        for (var i = 0; i < 3; i++)
          {
            'id': '$i',
            'title': 'Item $i',
            'description': i == 1 ? 'Read these notes' : '',
            'completed': i == 2,
          },
      ];
      final calls = <String>[];
      await mount(
        tester,
        ChecklistPanel(
          parentId: 'parent',
          origin: panelOrigin,
          revision: 'snapshot-1',
          items: items,
          onAdd: () => calls.add('add'),
          onEdit: (i) => calls.add('edit:${i['id']}'),
          onToggle: (i, value) => calls.add('check:${i['id']}:$value'),
          onMove: (i, before) => calls.add('move:${i['id']}:$before'),
          onDelete: (i) => calls.add('delete:${i['id']}'),
        ),
      );
      expect(find.text('Checklist'), findsNothing);
      expect(find.text('1/3'), findsNothing);
      expect(find.text('Items save separately.'), findsNothing);
      expect(find.text('Read these notes'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Read these notes')).maxLines, 1);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('checklist-add'))).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const Key('checklist-edit-2'))).bottom,
        ),
      );
      await tester.tap(find.byKey(const Key('checklist-add')));
      await tester.tap(find.byKey(const Key('checklist-check-0')));
      await tester.tap(find.byKey(const Key('checklist-edit-1')));
      await tester.tap(find.byKey(const Key('checklist-delete-1')));
      expect(calls, ['add', 'check:0:true', 'edit:1', 'delete:1']);
    },
  );

  testWidgets('panel disabled controls and 200 percent narrow semantics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    await mount(
      tester,
      ChecklistPanel(
        parentId: 'parent',
        origin: panelOrigin,
        revision: 'snapshot-1',
        items: [
          {
            'id': 'one',
            'title': 'Long item title for enlarged text',
            'description': 'Optional notes remain readable',
            'completed': false,
          },
        ],
        enabled: false,
        onAdd: () => fail('disabled add'),
        onEdit: (_) => fail('disabled edit'),
        onToggle: (_, _) => fail('disabled check'),
        onMove: (_, _) => fail('disabled move'),
        onDelete: (_) => fail('disabled delete'),
      ),
      scale: 2,
    );
    expect(
      find.bySemanticsLabel(
        'Complete checklist item: Long item title for enlarged text',
      ),
      findsOneWidget,
    );
    for (final key in [
      'checklist-check-one',
      'checklist-delete-one',
      'checklist-drag-one',
      'checklist-edit-one',
      'checklist-add',
    ]) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byKey(const Key('checklist-check-one')));
    final checkData = tester
        .getSemantics(
          find.bySemanticsLabel(
            'Complete checklist item: Long item title for enlarged text',
          ),
        )
        .getSemanticsData();
    expect(checkData.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(checkData.hasAction(ui.SemanticsAction.tap), isFalse);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('checklist-check-one')))
          .onChanged,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('busy checkbox keeps child focus and guards repeat Space', (
    tester,
  ) async {
    var enabled = true;
    var toggles = 0;
    late StateSetter update;
    await mount(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return ChecklistPanel(
            parentId: 'parent',
            origin: panelOrigin,
            revision: 'snapshot-1',
            items: const [
              {'id': 'one', 'title': 'One', 'completed': false},
            ],
            enabled: enabled,
            onAdd: () {},
            onEdit: (_) {},
            onMove: (_, _) {},
            onDelete: (_) {},
            onToggle: (_, _) {
              toggles++;
              update(() => enabled = false);
            },
          );
        },
      ),
    );
    final checkbox = find.byKey(const Key('checklist-check-one'));
    final focus = Focus.of(
      tester.element(
        find.descendant(of: checkbox, matching: find.byType(CustomPaint)).first,
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(toggles, 1);
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(toggles, 1);
    update(() => enabled = true);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('child handle supports scoped typed drag and relative movement', (
    tester,
  ) async {
    final calls = <String>[];
    var parentSelections = 0;
    var parentDrags = 0;
    await mount(
      tester,
      GestureDetector(
        onTap: () => parentSelections++,
        child: Draggable<String>(
          data: 'parent',
          onDragStarted: () => parentDrags++,
          feedback: const Material(child: Text('Parent task')),
          child: dragPanel(
            onMove: (item, before) => calls.add('${item['id']}:$before'),
          ),
        ),
      ),
    );
    for (final key in [
      'checklist-check-0',
      'checklist-edit-0',
      'checklist-delete-0',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }
    expect(parentSelections, 0);
    expect(parentDrags, 0);
    final handle = find.byKey(const Key('checklist-drag-0'));
    final draggable = tester.widget<Draggable<ChecklistItemDrag>>(
      find
          .ancestor(
            of: handle,
            matching: find.byType(Draggable<ChecklistItemDrag>),
          )
          .first,
    );
    expect(draggable.data!.parentId, 'parent');
    expect(identical(draggable.data!.origin, panelOrigin), isTrue);
    expect(draggable.data!.observedOrder, ['0', '1', '2']);
    expect(
      () => draggable.data!.observedOrder.add('forged'),
      throwsUnsupportedError,
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('checklist-drop-before-2'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, ['0:2']);
    expect(parentSelections, 0);
    expect(parentDrags, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'drop rejects wrong scope stale snapshot and disabled late acceptance',
    (tester) async {
      final calls = <String>[];
      void move(Map<String, dynamic> item, String? before) =>
          calls.add('${item['id']}:$before');
      await mount(tester, dragPanel(onMove: move));
      DragTarget<ChecklistItemDrag> target() =>
          tester.widget(find.byKey(const Key('checklist-drop-before-2')));
      ChecklistItemDrag payload({
        String parent = 'parent',
        Object? origin,
        Object revision = 'snapshot-1',
        String item = '0',
        List<String> order = const ['0', '1', '2'],
      }) => ChecklistItemDrag(
        parentId: parent,
        origin: origin ?? panelOrigin,
        revision: revision,
        itemId: item,
        observedOrder: order,
      );
      DragTargetDetails<ChecklistItemDrag> details(ChecklistItemDrag data) =>
          DragTargetDetails(data: data, offset: Offset.zero);
      for (final invalid in [
        payload(parent: 'other'),
        payload(origin: Object()),
        payload(revision: 'old'),
        payload(order: ['1', '0', '2']),
        payload(item: 'missing'),
        payload(item: '2'),
      ]) {
        expect(target().onWillAcceptWithDetails!(details(invalid)), isFalse);
        target().onAcceptWithDetails!(details(invalid));
        expect(calls, isEmpty);
      }
      final valid = details(payload());
      expect(target().onWillAcceptWithDetails!(valid), isTrue);
      final acceptedBeforeUpdate = target().onAcceptWithDetails!;
      await mount(tester, dragPanel(enabled: false, onMove: move));
      acceptedBeforeUpdate(valid);
      expect(calls, isEmpty);
      expect(target().onWillAcceptWithDetails!(valid), isFalse);
      await mount(tester, dragPanel(revision: 'snapshot-2', onMove: move));
      expect(target().onWillAcceptWithDetails!(valid), isFalse);
      acceptedBeforeUpdate(valid);
      expect(calls, isEmpty);
      await mount(
        tester,
        dragPanel(
          items: [dragItems()[1], dragItems()[0], dragItems()[2]],
          onMove: move,
        ),
      );
      expect(target().onWillAcceptWithDetails!(valid), isFalse);
      acceptedBeforeUpdate(valid);
      expect(calls, isEmpty);
      final ending = tester.widget<DragTarget<ChecklistItemDrag>>(
        find.byKey(const Key('checklist-drop-end')),
      );
      expect(
        ending.onWillAcceptWithDetails!(
          details(payload(order: ['1', '0', '2'], item: '2')),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'move semantics keyboard edges and Add focus hook stay child scoped',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final calls = <String>[];
      final addFocus = FocusNode();
      addTearDown(addFocus.dispose);
      await mount(
        tester,
        dragPanel(
          addFocusNode: addFocus,
          onMove: (item, before) => calls.add('${item['id']}:$before'),
        ),
      );
      Map<String, int> actions(String id) {
        final data = tester
            .getSemantics(find.byKey(Key('checklist-drag-$id')))
            .getSemanticsData();
        return {
          for (final action in data.customSemanticsActionIds ?? <int>[])
            CustomSemanticsAction.getAction(action)!.label!: action,
        };
      }

      expect(actions('0').keys, ['Move down']);
      expect(actions('2').keys, ['Move up']);
      final node = tester.getSemantics(
        find.byKey(const Key('checklist-drag-0')),
      );
      node.owner!.performAction(
        node.id,
        ui.SemanticsAction.customAction,
        actions('0')['Move down'],
      );
      await tester.pumpAndSettle();
      final handle = find.byKey(const Key('checklist-drag-1'));
      final focus = Focus.of(
        tester.element(
          find.descendant(of: handle, matching: find.byType(Icon)).first,
        ),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(calls, ['0:2', '1:0', '1:null']);
      await mount(
        tester,
        dragPanel(
          enabled: false,
          addFocusNode: addFocus,
          onMove: (_, _) => fail('disabled move'),
        ),
      );
      expect(actions('1'), isEmpty);
      expect(
        tester
            .getSemantics(find.byKey(const Key('checklist-drag-1')))
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isFalse,
      );
      await mount(
        tester,
        dragPanel(items: [], addFocusNode: addFocus, onMove: (_, _) {}),
      );
      addFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(addFocus.hasFocus, isTrue);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('checklist-add')))
            .focusNode,
        addFocus,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'new item saves normalized title and multiline notes independently',
    (tester) async {
      final saved = <List<String>>[];
      var closed = 0;
      await mount(
        tester,
        ChecklistItemEditor(
          save: (title, notes) async => saved.add([title, notes]),
          onClose: () => closed++,
        ),
      );
      expect(find.text('Add checklist item'), findsOneWidget);
      await tester.enterText(find.byKey(titleKey), '  Pack\nmy bag  ');
      await tester.enterText(find.byKey(notesKey), 'First\nSecond 😀');
      await tester.tap(find.byKey(saveKey));
      await tester.pumpAndSettle();
      expect(saved, [
        ['Pack my bag', 'First\nSecond 😀'],
      ]);
      expect(closed, 1);
    },
  );

  testWidgets(
    'dirty close can be cancelled, dismissed and asked repeatedly without popping',
    (tester) async {
      final key = GlobalKey<ChecklistItemEditorState>();
      var closed = 0;
      await mount(
        tester,
        ChecklistItemEditor(
          key: key,
          item: {'title': 'Old', 'description': ''},
          save: (_, _) async {},
          onClose: () => closed++,
        ),
      );
      expect(await key.currentState!.canClose(), isTrue);
      await tester.enterText(find.byKey(notesKey), 'private');
      final cancelled = key.currentState!.canClose();
      final same = key.currentState!.canClose();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(await cancelled, isFalse);
      expect(await same, isFalse);
      final dismissed = key.currentState!.canClose();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Unsaved changes'))).pop();
      await tester.pumpAndSettle();
      expect(await dismissed, isFalse);
      final discard = key.currentState!.canClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(await discard, isTrue);
      expect(closed, 0);
      expect(
        tester.widget<TextField>(find.byKey(notesKey)).controller!.text,
        'private',
      );
    },
  );

  testWidgets(
    'save through close guard renews dirty baseline; reopening starts clean',
    (tester) async {
      final key = GlobalKey<ChecklistItemEditorState>();
      var saves = 0;
      await mount(
        tester,
        ChecklistItemEditor(
          key: key,
          item: {'title': 'Old'},
          save: (_, _) async {
            saves++;
          },
        ),
      );
      await tester.enterText(find.byKey(titleKey), 'New');
      final request = key.currentState!.canClose();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(await request, isTrue);
      expect(await key.currentState!.canClose(), isTrue);
      expect(saves, 1);
      await mount(tester, const SizedBox());
      final reopened = GlobalKey<ChecklistItemEditorState>();
      await mount(
        tester,
        ChecklistItemEditor(
          key: reopened,
          item: {'title': 'New'},
          save: (_, _) async {},
        ),
      );
      expect(await reopened.currentState!.canClose(), isTrue);
    },
  );

  testWidgets(
    'failed save retains draft; pending receipt freezes fields and close but permits exact retry',
    (tester) async {
      var pending = false;
      var attempts = 0;
      final saved = <List<String>>[];
      final key = GlobalKey<ChecklistItemEditorState>();
      await mount(
        tester,
        ChecklistItemEditor(
          key: key,
          hasPendingReceipt: () => pending,
          save: (title, notes) async {
            saved.add([title, notes]);
            attempts++;
            if (attempts == 1) {
              pending = true;
              throw StateError('Disk full');
            }
            pending = false;
          },
          onClose: () {},
        ),
      );
      await tester.enterText(find.byKey(titleKey), 'Private');
      await tester.enterText(find.byKey(notesKey), 'Keep me');
      await tester.tap(find.byKey(saveKey));
      await tester.pumpAndSettle();
      expect(find.text('Disk full'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(titleKey)).enabled, isFalse);
      expect(
        tester.widget<TextField>(find.byKey(notesKey)).controller!.text,
        'Keep me',
      );
      expect(await key.currentState!.canClose(), isFalse);
      expect(
        tester.widget<TextButton>(find.byKey(cancelKey)).onPressed,
        isNull,
      );
      expect(find.text('Retry Save'), findsOneWidget);
      await tester.tap(find.byKey(saveKey));
      await tester.pumpAndSettle();
      expect(saved, [
        ['Private', 'Keep me'],
        ['Private', 'Keep me'],
      ]);
    },
  );

  testWidgets('IME composition cannot save; length errors retain fields', (
    tester,
  ) async {
    var saves = 0;
    await mount(
      tester,
      ChecklistItemEditor(
        save: (_, _) async {
          saves++;
        },
        onClose: () {},
      ),
    );
    await tester.tap(find.byKey(titleKey));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Composing',
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 0, end: 9),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(saveKey));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.textContaining('Finish entering'), findsOneWidget);
    await tester.enterText(find.byKey(titleKey), 'a' * 501);
    await tester.tap(find.byKey(saveKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('500'), findsOneWidget);
    await tester.enterText(find.byKey(titleKey), 'Good');
    await tester.enterText(find.byKey(notesKey), 'b' * 10001);
    await tester.tap(find.byKey(saveKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('10000'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets(
    'narrow enlarged editor and keyboard keep multiline input and actions reachable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();

      await mount(
        tester,
        ChecklistItemEditor(
          item: {
            'title': 'Long title',
            'description': List.generate(40, (i) => 'Line $i').join('\n'),
          },
          save: (_, _) async {},
          onClose: () {},
        ),
        scale: 2,
      );
      expect(find.bySemanticsLabel('Checklist item title'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Checklist item notes (optional)'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(notesKey));
      tester.view.viewInsets = FakeViewPadding(
        bottom: 220 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(saveKey));
      expect(
        tester.getRect(find.byKey(saveKey)).bottom,
        lessThanOrEqualTo(420),
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('busy Save admits one command and freezes draft until success', (
    tester,
  ) async {
    final completer = Completer<void>();
    final key = GlobalKey<ChecklistItemEditorState>();
    var saves = 0;
    await mount(
      tester,
      ChecklistItemEditor(
        key: key,
        save: (_, _) {
          saves++;
          return completer.future;
        },
        onClose: () {},
      ),
    );
    await tester.enterText(find.byKey(titleKey), 'One command');
    await tester.tap(find.byKey(saveKey));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(saveKey)).onPressed, isNull);
    expect(tester.widget<TextField>(find.byKey(titleKey)).enabled, isFalse);
    expect(await key.currentState!.canClose(), isFalse);
    await tester.tap(find.byKey(saveKey));
    expect(saves, 1);
    completer.complete();
    await tester.pumpAndSettle();
    expect(await key.currentState!.canClose(), isTrue);
  });

  testWidgets('Cancel and route back resolve dirty item before closing host', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ChecklistItemEditor(
                  item: {'title': 'Initial'},
                  save: (_, _) async {},
                ),
              ),
              child: const Text('Open item'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(titleKey), 'Dirty');
    await tester.tap(find.byKey(cancelKey));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(find.byKey(titleKey), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byKey(titleKey), findsNothing);
    await tester.tap(find.text('Open item'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(titleKey)).controller!.text,
      'Initial',
    );
    await tester.tap(find.byKey(cancelKey));
    await tester.pumpAndSettle();
    expect(find.byKey(titleKey), findsNothing);
  });

  testWidgets('render dark desktop and narrow enlarged components', (
    tester,
  ) async {
    final fontDir = Platform.environment['CHECKLIST_FONT_DIR'];
    if (fontDir != null) {
      await tester.runAsync(() async {
        for (final font in {
          'Roboto': 'Roboto-Regular.ttf',
          'MaterialIcons': 'MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(font.key)
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  await File('$fontDir/${font.value}').readAsBytes(),
                ),
              ),
            );
          await loader.load();
        }
      });
    }
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(
      tester,
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 560,
          child: dragPanel(
            items: [
              {
                'id': 'boots',
                'title': 'Check hiking boots',
                'description': 'Make sure the laces and soles are sound.',
                'completed': true,
              },
              {
                'id': 'water',
                'title': 'Fill the water bottles',
                'description': 'Two litres for each person.',
                'completed': false,
              },
            ],
            onMove: (_, _) {},
          ),
        ),
      ),
      dark: true,
    );
    await capture(tester, 'dark-desktop-inline-panel');
    expect(tester.takeException(), isNull);
    await mount(
      tester,
      ChecklistItemEditor(
        item: {
          'title': 'Pack the hiking bag',
          'description':
              'Water and warm layers\nBring lunch and a spare battery.',
        },
        save: (_, _) async {},
        onClose: () {},
      ),
      dark: true,
    );
    await capture(tester, 'dark-desktop-editor');
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await mount(
      tester,
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ChecklistPanel(
            parentId: 'parent',
            origin: panelOrigin,
            revision: 'snapshot-1',
            items: [
              {
                'id': 'boots',
                'title': 'Check hiking boots',
                'description': 'Make sure the laces and soles are sound.',
                'completed': true,
              },
              {
                'id': 'water',
                'title': 'Fill the water bottles',
                'description': 'Two litres for each person.',
                'completed': false,
              },
            ],
            onAdd: () {},
            onEdit: (_) {},
            onToggle: (_, _) {},
            onMove: (_, _) {},
            onDelete: (_) {},
          ),
        ),
      ),
      scale: 2,
      dark: true,
    );
    await capture(tester, 'dark-narrow-enlarged-panel');
    expect(tester.takeException(), isNull);
    await mount(
      tester,
      ChecklistItemEditor(
        item: {
          'title': 'Pack the hiking bag',
          'description': List.generate(30, (i) => 'Line $i').join('\n'),
        },
        save: (_, _) async {},
        onClose: () {},
      ),
      scale: 2,
      dark: true,
    );
    await capture(tester, 'dark-narrow-enlarged-editor');
    await tester.tap(find.byKey(notesKey));
    tester.view.viewInsets = FakeViewPadding(
      bottom: 220 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(saveKey));
    await capture(tester, 'dark-narrow-enlarged-keyboard');
    expect(tester.takeException(), isNull);
  });
}
