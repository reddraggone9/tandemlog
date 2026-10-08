import 'dart:async';
import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_editor.dart';

const staleWarning =
    'Selected tasks changed. Close this editor and review them before retrying.';

void main() {
  for (final variant in const [
    (width: 390.0, height: 820.0, scale: 1.0, keyboard: 0.0),
    (width: 390.0, height: 820.0, scale: 2.0, keyboard: 280.0),
    (width: 360.0, height: 640.0, scale: 2.0, keyboard: 280.0),
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
        semantics.dispose();
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
      pending.completeError(StateError(staleWarning));
      await tester.pumpAndSettle();

      final warning = find.text(staleWarning);
      expect(warning, findsOneWidget);
      expect(warning.hitTestable(), findsOneWidget);
      final visible = Rect.fromLTWH(
        0,
        0,
        variant.width,
        variant.height - variant.keyboard,
      );
      expect(visible.contains(tester.getRect(warning).topLeft), isTrue);
      expect(visible.contains(tester.getRect(warning).bottomRight), isTrue);
      expect(
        tester.getRect(warning).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Save changes')).top),
      );
      expect(position.pixels, beforeFailure);
      expect(FocusManager.instance.primaryFocus, same(focusBeforeFailure));
      expect(controller.value, draft);
      expect(
        tester
            .getSemantics(warning)
            .getSemanticsData()
            .hasFlag(SemanticsFlag.isLiveRegion),
        isTrue,
      );
      expect(calls, 1);
      expect(closed, 0);
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(find.text('Save changes').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
