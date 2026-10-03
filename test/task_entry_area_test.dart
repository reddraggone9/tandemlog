import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_entry_area.dart';

void main() {
  testWidgets('selection swaps preserve slot geometry, draft and semantics', (
    tester,
  ) async {
    for (final width in [320.0, 390.0, 899.0]) {
      for (final scale in [1.0, 2.0, 2.5]) {
        for (final completed in [false, true]) {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          final controller = TextEditingController(
            text: 'First draft\nSecond draft\nThird draft\nFourth draft',
          );
          controller.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 11,
          );
          final focus = FocusNode();
          final state = ValueNotifier(false);
          var clear = 0, edit = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: state,
                        builder: (_, selecting, _) => Column(
                          children: [
                            TaskEntryArea(
                              selecting: selecting,
                              captureVisible: !completed,
                              selectionCount: 10000,
                              maximumSelectionCount: 10000,
                              onClear: () => clear++,
                              onEdit: () => edit++,
                              capture: TextField(
                                controller: controller,
                                focusNode: focus,
                                minLines: 1,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText: 'Capture',
                                  helperText: 'Keyboard hint',
                                ),
                              ),
                            ),
                            const SizedBox(
                              key: ValueKey('list-marker'),
                              height: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final area = tester.getRect(find.byType(TaskEntryArea));
          final marker = tester.getRect(
            find.byKey(const ValueKey('list-marker')),
          );
          final value = controller.value;
          if (!completed) {
            focus.requestFocus();
            await tester.pumpAndSettle();
          }
          state.value = true;
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(TaskEntryArea)), area);
          expect(
            tester.getRect(find.byKey(const ValueKey('list-marker'))),
            marker,
          );
          expect(controller.value, value);
          expect(focus.hasFocus, false);
          expect(find.byType(TextField).hitTestable(), findsNothing);
          final semantics = tester.ensureSemantics();
          expect(find.semantics.byLabel('Capture'), findsNothing);
          semantics.dispose();
          for (final key in ['clear-selected-tasks', 'edit-selected-tasks']) {
            final button = find.byKey(ValueKey(key));
            expect(tester.getRect(button).height, greaterThanOrEqualTo(48));
            expect(
              tester.getRect(button).bottom,
              lessThanOrEqualTo(area.bottom),
            );
            await tester.tap(button);
          }
          expect(clear, 1);
          expect(edit, 1);
          state.value = false;
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(TaskEntryArea)), area);
          expect(controller.value, value);
          expect(
            tester.takeException(),
            isNull,
            reason: '$width x$scale completed=$completed',
          );
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          focus.dispose();
          state.dispose();
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
