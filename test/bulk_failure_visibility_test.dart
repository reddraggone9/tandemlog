import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/presentation/form_validation.dart';

const staleWarning =
    'Selected tasks changed. Close this editor and review them before retrying.';
const longWarning =
    'Folder save failed. Your draft is retained. '
    'The provider did not acknowledge the selected changes. '
    'Reconnect the folder and check its permissions before retrying. '
    'No successful save has been reported. '
    'A long provider explanation must remain readable without moving the form.';

void main() {
  for (final variant in const [
    (
      width: 390.0,
      height: 820.0,
      scale: 1.0,
      keyboard: 0.0,
      message: staleWarning,
    ),
    (
      width: 390.0,
      height: 820.0,
      scale: 2.0,
      keyboard: 280.0,
      message: staleWarning,
    ),
    (
      width: 360.0,
      height: 640.0,
      scale: 2.0,
      keyboard: 280.0,
      message: staleWarning,
    ),
    (
      width: 360.0,
      height: 640.0,
      scale: 2.0,
      keyboard: 280.0,
      message: longWarning,
    ),
  ]) {
    testWidgets('bulk failure remains visible after bottom scroll $variant', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(variant.width, variant.height);
      tester.view.viewInsets = FakeViewPadding(bottom: variant.keyboard);
      tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final pending = Completer<void>();
      var calls = 0, closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BulkTaskEditor(
              tasks: [
                for (final id in ['one', 'two'])
                  {
                    'id': id,
                    'title': id,
                    'schedule': <String, dynamic>{},
                    'tags': <String>[],
                    'tagRefs': <String, String>{},
                  },
              ],
              onClose: () => closed++,
              onDelete: () async {},
              onSave: (edit) {
                calls++;
                expect(edit.schedulePatch, {'dueMaxDays': 12});
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('dueMaxDays'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '12');
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
      );
      await tester.pump();
      final draft = controller.value;
      final formScroll = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(formScroll).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Edit 2 tasks').hitTestable(), findsNothing);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final beforeFailure = position.pixels;
      final focusBeforeFailure = FocusManager.instance.primaryFocus;
      pending.completeError(StateError(variant.message));
      await tester.pumpAndSettle();

      final warning = find.text(variant.message);
      expect(warning, findsOneWidget);
      expect(warning.hitTestable(at: const Alignment(0, -.99)), findsOneWidget);
      final notice = find.byKey(const ValueKey('bulk-save-failure'));
      final visible = Rect.fromLTWH(
        0,
        0,
        variant.width,
        variant.height - variant.keyboard,
      );
      expect(visible.contains(tester.getRect(notice).topLeft), isTrue);
      expect(visible.contains(tester.getRect(notice).bottomRight), isTrue);
      expect(
        tester.getRect(notice).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Save changes')).top),
      );
      expect(position.pixels, beforeFailure);
      expect(FocusManager.instance.primaryFocus, same(focusBeforeFailure));
      expect(controller.value, draft);
      final noticePosition = tester
          .state<ScrollableState>(
            find.descendant(of: notice, matching: find.byType(Scrollable)),
          )
          .position;
      noticePosition.jumpTo(noticePosition.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(warning.hitTestable(at: const Alignment(0, .99)), findsOneWidget);
      expect(position.pixels, beforeFailure);
      expect(controller.value, draft);
      expect(
        tester
            .getSemantics(warning)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(calls, 1);
      expect(closed, 0);
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(find.text('Save changes').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
  for (final panel in [false, true]) {
    testWidgets(
      'single modal and bulk panel pin a bounded failure notice $panel',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 900);
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        final original = {
          'id': 'one',
          'title': 'Original',
          'description': '',
          'schedule': <String, dynamic>{},
          'tags': <String>[],
          'tagRefs': <String, String>{},
        };
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: panel
                  ? BulkTaskEditor(
                      panel: true,
                      tasks: [
                        original,
                        {...original, 'id': 'two'},
                      ],
                      onClose: () {},
                      onSave: (_) async => throw StateError(staleWarning),
                    )
                  : TaskEditor(
                      task: original,
                      onClose: () {},
                      save: (_, added, removed) async =>
                          throw StateError(staleWarning),
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(ValueKey(panel ? 'dueMaxDays' : 'title'));
        await tester.ensureVisible(field);
        await tester.enterText(field, panel ? '12' : 'Retained title');
        await tester.pumpAndSettle();
        final controller = tester.widget<TextField>(field).controller!;
        final draft = controller.value;
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        final warning = find.text(staleWarning);
        expect(warning, findsOneWidget);
        expect(find.byKey(const ValueKey('bulk-save-failure')), findsNothing);
        final notice = find.byKey(const ValueKey('task-save-failure'));
        expect(notice, findsOneWidget);
        expect(
          find.descendant(of: notice, matching: find.byType(Scrollable)),
          findsOneWidget,
        );
        expect(warning.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(notice).bottom,
          lessThanOrEqualTo(tester.getRect(find.text('Save changes')).top),
        );
        expect(controller.value, draft);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final panel in [false, true]) {
    for (final size in [const Size(390, 820), const Size(360, 640)]) {
      testWidgets(
        'single ${panel ? 'panel' : 'modal'} long failure is bounded at $size with 200 percent text and keyboard',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            tester.platformDispatcher.textScaleFactorTestValue = 2;
            addTearDown(() {
              tester.view.resetDevicePixelRatio();
              tester.view.resetPhysicalSize();
              tester.view.resetViewInsets();
              tester.platformDispatcher.clearTextScaleFactorTestValue();
            });
            final pending = Completer<void>();
            final message = List.filled(3, longWarning).join(' ');
            var calls = 0, closed = 0;
            final original = <String, dynamic>{
              'id': 'synthetic-single',
              'title': 'Original',
              'description': 'Preserved notes',
              'schedule': <String, dynamic>{},
              'tags': <String>[],
              'tagRefs': <String, String>{},
            };
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: TaskEditor(
                    panel: panel,
                    task: original,
                    onClose: () => closed++,
                    save: (fields, added, removed) {
                      calls++;
                      expect(fields['title'], 'Retained title');
                      expect((fields['schedule'] as Map)['dueMaxDays'], 12);
                      expect(added, isEmpty);
                      expect(removed, isEmpty);
                      return pending.future;
                    },
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final title = find.byKey(const ValueKey('title'));
            final bound = find.byKey(const ValueKey('dueMaxDays'));
            await tester.ensureVisible(title);
            await tester.enterText(title, 'Retained title');
            await tester.ensureVisible(bound);
            await tester.enterText(bound, '12');
            await tester.pumpAndSettle();
            final controller = tester.widget<TextField>(bound).controller!;
            controller.selection = const TextSelection(
              baseOffset: 0,
              extentOffset: 1,
            );
            final action = find.descendant(
              of: find.byType(ValidationActionButton),
              matching: find.byType(FilledButton),
            );
            await tester.ensureVisible(action);
            await tester.tap(action);
            await tester.pumpAndSettle();
            expect(calls, 1);
            final draft = <String, TextEditingValue>{
              for (final field in tester.widgetList<TextField>(
                find.byType(TextField),
              ))
                if (field.key is ValueKey<String> && field.controller != null)
                  (field.key as ValueKey<String>).value:
                      field.controller!.value,
            };
            expect(draft['title']!.text, 'Retained title');
            expect(draft['description']!.text, 'Preserved notes');
            expect(draft['dueMaxDays']!.text, '12');
            final form = find
                .descendant(
                  of: find.byType(TaskEditor),
                  matching: find.byType(Scrollable),
                )
                .first;
            final formPosition = tester.state<ScrollableState>(form).position;
            final beforeFailure = formPosition.pixels;
            final focus = FocusManager.instance.primaryFocus;
            pending.completeError(StateError(message));
            await tester.pumpAndSettle();
            final notice = find.byKey(const ValueKey('task-save-failure'));
            final warning = find.text(message);
            expect(notice, findsOneWidget);
            expect(warning, findsOneWidget);
            final noticeRect = tester.getRect(notice);
            final actionRect = tester.getRect(action);

            expect(noticeRect.top, greaterThanOrEqualTo(0));
            expect(noticeRect.bottom, lessThanOrEqualTo(actionRect.top));
            expect(actionRect.bottom, lessThanOrEqualTo(size.height - 280));
            expect(actionRect.height, greaterThanOrEqualTo(32));
            expect(action.hitTestable(), findsOneWidget);
            expect(
              find.widgetWithText(TextButton, 'Cancel').hitTestable(),
              findsOneWidget,
            );
            expect(
              warning.hitTestable(at: const Alignment(0, -.99)),
              findsOneWidget,
            );
            final noticePosition = tester
                .state<ScrollableState>(
                  find.descendant(
                    of: notice,
                    matching: find.byType(Scrollable),
                  ),
                )
                .position;
            expect(
              noticePosition.maxScrollExtent,
              greaterThan(0),
              reason: 'Long provider text must scroll within a bounded notice',
            );
            noticePosition.jumpTo(noticePosition.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(
              warning.hitTestable(at: const Alignment(0, .99)),
              findsOneWidget,
            );
            expect(formPosition.pixels, beforeFailure);
            expect(FocusManager.instance.primaryFocus, same(focus));
            for (final field in tester.widgetList<TextField>(
              find.byType(TextField),
            )) {
              if (field.key is ValueKey<String> && field.controller != null) {
                expect(
                  field.controller!.value,
                  draft[(field.key as ValueKey<String>).value],
                  reason:
                      'Operational failure must preserve every visible draft controller',
                );
              }
            }
            expect(
              tester
                  .getSemantics(warning)
                  .getSemanticsData()
                  .flagsCollection
                  .isLiveRegion,
              isTrue,
            );
            expect(calls, 1);
            expect(closed, 0);
            expect(original['title'], 'Original');
            expect(original['schedule'], isEmpty);
          } finally {
            semantics.dispose();
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
