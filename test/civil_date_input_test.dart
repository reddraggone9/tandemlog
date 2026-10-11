import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/civil_date_input.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(loadSdkRoboto);
  for (final scale in [1.0, 2.0]) {
    testWidgets('blank focused date fits at 320 dp and scale $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = TextEditingController();
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: CivilDateInput(
                  controller: controller,
                  focusNode: focus,
                  fieldKey: const ValueKey('expiration'),
                  label: 'Expiration',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('expiration')));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(find.text('YYYY-MM-DD'), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip('Choose Expiration')).shortestSide,
        greaterThanOrEqualTo(48),
      );
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final painter = TextPainter(
        text: TextSpan(text: 'YYYY-MM-DD', style: editable.widget.style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(scale),
      )..layout();
      expect(
        editable.renderEditable.size.width,
        greaterThanOrEqualTo(painter.width + 1),
      );
      painter.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      controller.dispose();
    });
  }

  testWidgets('picker preserves civil date and accepts manual date typing', (
    tester,
  ) async {
    final controller = TextEditingController(text: '2026-10-04');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CivilDateInput(controller: controller, label: 'Expiration'),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Choose Expiration'));
    await tester.pumpAndSettle();
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, DateTime(2026, 10, 4));
    expect(picker.firstDate, DateTime(1900));
    expect(picker.lastDate, DateTime(9999));
    await tester.tap(find.text('12'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller.text, '2026-10-12');
    await tester.enterText(find.byType(TextField), '2026-11-03');
    await tester.pump();
    expect(controller.text, '2026-11-03');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('validation stays caller-owned and disabled dates cannot pick', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CivilDateInput(
            controller: controller,
            label: 'Expiration',
            enabled: false,
            hint: 'Mixed — unchanged unless applied',
            errorText: 'Expiration is required.',
          ),
        ),
      ),
    );
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.enabled, isFalse);
    expect(input.decoration!.hintText, 'Mixed — unchanged unless applied');
    expect(find.text('Expiration is required.'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(controller.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final text in ['1899-12-31', 'not-a-date']) {
    testWidgets('picker falls back safely without changing draft $text', (
      tester,
    ) async {
      final controller = TextEditingController(text: text);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CivilDateInput(controller: controller, label: 'Expiration'),
          ),
        ),
      );
      final before = DateTime.now();
      await tester.tap(find.byTooltip('Choose Expiration'));
      await tester.pumpAndSettle();
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      final after = DateTime.now();
      expect(
        picker.initialDate,
        anyOf(
          DateTime(before.year, before.month, before.day),
          DateTime(after.year, after.month, after.day),
        ),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.text, text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('picker result safely ignores a disposed input controller', (
    tester,
  ) async {
    final controller = TextEditingController(text: '2026-10-04');
    final showInput = ValueNotifier(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: showInput,
            builder: (_, shown, _) => shown
                ? CivilDateInput(controller: controller, label: 'Expiration')
                : const SizedBox(),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Choose Expiration'));
    await tester.pumpAndSettle();
    showInput.value = false;
    await tester.pump();
    controller.dispose();
    await tester.tap(find.text('12'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    showInput.dispose();
  });
}
