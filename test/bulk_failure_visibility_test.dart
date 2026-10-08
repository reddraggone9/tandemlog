import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_editor.dart';

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
      'single modal and bulk panel keep existing failure location $panel',
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
        expect(
          find.ancestor(
            of: warning,
            matching: find.byType(SingleChildScrollView),
          ),
          panel ? findsNothing : findsOneWidget,
        );
        if (panel) expect(warning.hitTestable(), findsOneWidget);
        expect(controller.value, draft);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
