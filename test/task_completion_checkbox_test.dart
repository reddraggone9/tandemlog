import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_completion_checkbox.dart';

void main() {
  testWidgets(
    'disabled repeat perimeter has uniform opacity at overlapping tips',
    (tester) async {
      for (final brightness in Brightness.values) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Material(
              color: Colors.transparent,
              child: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: const TaskCompletionCheckbox(
                    value: false,
                    repeating: true,
                    onChanged: null,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pixels = await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 4);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        });
        var maximumAlpha = 0;
        for (var i = 3; i < pixels!.length; i += 4) {
          if (pixels[i] > maximumAlpha) maximumAlpha = pixels[i];
        }
        expect(
          maximumAlpha,
          greaterThan(90),
          reason: 'Perimeter remains visible',
        );
        expect(
          maximumAlpha,
          lessThanOrEqualTo(99),
          reason:
              '${brightness.name}: whole disabled vector uses 38% opacity; '
              'overlapping stroke/tip must not double-blend',
        );
      }
    },
  );
  testWidgets('repeat geometry retains padded touch and checked semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var checked = false, changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => TaskCompletionCheckbox(
                repeating: true,
                value: checked,
                onChanged: (value) => setState(() {
                  checked = value!;
                  changes++;
                }),
              ),
            ),
          ),
        ),
      ),
    );
    final checkbox = find.byType(Checkbox);
    final nativePaint = find
        .descendant(of: checkbox, matching: find.byType(CustomPaint))
        .first;
    final focus = Focus.of(tester.element(nativePaint));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(tester.getSize(checkbox), const Size(48, 48));
    final vector = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.size == const Size(18, 26),
    );
    expect(vector, findsOneWidget);
    expect(tester.getCenter(vector), tester.getCenter(checkbox));
    expect(
      tester.getSemantics(checkbox),
      matchesSemantics(
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    // Near the edge of the existing hit target, outside the 18px drawing.
    await tester.tapAt(tester.getCenter(checkbox) + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(changes, 1);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(vector, findsNothing);
    expect(tester.widget<Checkbox>(checkbox).side, isNull);
    expect(tester.getSize(checkbox), const Size(48, 48));
    expect(
      tester.getSemantics(checkbox),
      matchesSemantics(
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, 2);
    expect(checked, isFalse);
    expect(vector, findsOneWidget);
    expect(tester.getCenter(vector), tester.getCenter(checkbox));
    semantics.dispose();
  });

  testWidgets('disabled repeat target cannot complete at enlarged text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: TaskCompletionCheckbox(
              repeating: true,
              value: false,
              onChanged: null,
            ),
          ),
        ),
      ),
    );
    final checkbox = find.byType(Checkbox);
    expect(tester.getSize(checkbox), const Size(48, 48));
    expect(
      tester.getSemantics(checkbox),
      matchesSemantics(hasCheckedState: true, hasEnabledState: true),
    );
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('completed controls share native appearance in both themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Row(
                children: [
                  for (final repeating in [false, true])
                    TaskCompletionCheckbox(
                      value: true,
                      repeating: repeating,
                      onChanged: repeating ? null : (_) {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final controls = find.byType(Checkbox);
      expect(controls, findsNWidgets(2));
      for (final element in controls.evaluate()) {
        final checkbox = element.widget as Checkbox;
        expect(checkbox.value, true);
        expect(checkbox.side, isNull);
        expect(tester.getSize(find.byWidget(checkbox)), const Size(48, 48));
      }
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.size == const Size(18, 26),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
