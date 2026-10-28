import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/tandemlog_theme.dart';
import 'package:tandemlog/presentation/civil_date_input.dart';
import 'support/ux_capture.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

const _monthButton = ValueKey('civil-month-button');
const _yearButton = ValueKey('civil-year-button');

void main() {
  setUpAll(() async {
    await loadSdkRoboto();
    await loadUxIcons();
  });
  for (final (scale, brightness) in [
    (1.0, Brightness.dark),
    (2.0, Brightness.dark),
    (1.0, Brightness.light),
    (2.0, Brightness.light),
  ]) {
    testWidgets(
      'fast month/year jump clamps leap day and cancellation is draft-only scale $scale ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TextEditingController(text: '2028-02-29');
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('ux-root'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: tandemlogTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: CivilDateInput(
                  controller: controller,
                  label: 'Expiration',
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Choose Expiration'));
        await tester.pumpAndSettle();
        await captureUx(tester, 'calendar-320-${brightness.name}-scale$scale');
        await tester.tap(find.byKey(_monthButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(CivilMonthGrid), findsOneWidget);
        expect(find.text('29'), findsNothing);
        await captureUx(
          tester,
          'month-grid-320-${brightness.name}-scale$scale',
        );
        await tester.tap(find.byKey(_yearButton));
        await tester.pumpAndSettle();
        expect(
          find
              .descendant(
                of: find.byType(CivilYearGrid),
                matching: find.text('2028'),
              )
              .hitTestable(),
          findsOneWidget,
        );
        final yearViewport = tester.getRect(find.byType(CivilYearGrid));
        for (final label
            in find
                .descendant(
                  of: find.byType(CivilYearGrid),
                  matching: find.byType(Text),
                )
                .evaluate()) {
          final rect = tester.getRect(find.byWidget(label.widget));
          if (rect.overlaps(yearViewport)) {
            expect(rect.top, greaterThanOrEqualTo(yearViewport.top - .1));
            expect(rect.bottom, lessThanOrEqualTo(yearViewport.bottom + .1));
          }
        }
        await tester.scrollUntilVisible(
          find.text('2029'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(CivilYearGrid),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(find.text('2029'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2029'));
        await tester.pumpAndSettle();
        // A picked year opens that year's months; the draft day waits.
        expect(find.byType(CivilYearGrid), findsNothing);
        expect(find.byType(CivilMonthGrid), findsOneWidget);
        await tester.tap(find.text('Feb'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CivilCalendarDatePicker>(
                find.byType(CivilCalendarDatePicker),
              )
              .initialDate,
          DateTime(2029, 2, 28),
        );
        expect(controller.text, '2028-02-29');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(controller.text, '2028-02-29');
        await tester.tap(find.byTooltip('Choose Expiration'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_monthButton));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Dec'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dec'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(controller.text, '2028-12-29');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets('escape and system back return to calendar before closing', (
    tester,
  ) async {
    final controller = TextEditingController(text: '2028-02-29');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CivilDateInput(controller: controller, label: 'Expiration'),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Choose Expiration'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_monthButton));
    await tester.pumpAndSettle();
    expect(find.byType(CivilMonthGrid), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CivilMonthGrid), findsNothing);
    expect(find.text('29'), findsOneWidget);
    await tester.tap(find.byKey(_yearButton));
    await tester.pumpAndSettle();
    expect(find.byType(CivilYearGrid), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CivilYearGrid), findsNothing);
    expect(find.text('29'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CivilDatePickerDialog), findsNothing);
    expect(controller.text, '2028-02-29');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'maximum supported year permits December without an invalid dialog',
    (tester) async {
      final controller = TextEditingController(text: '9999-01-31');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CivilDateInput(controller: controller, label: 'Expiration'),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Choose Expiration'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_monthButton));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dec'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dec'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(controller.text, '9999-12-31');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('month jump retains a newly selected pending day', (
    tester,
  ) async {
    final controller = TextEditingController(text: '2028-02-29');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CivilDateInput(controller: controller, label: 'Expiration'),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Choose Expiration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_monthButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jun'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CivilCalendarDatePicker>(find.byType(CivilCalendarDatePicker))
          .initialDate,
      DateTime(2028, 6, 15),
    );
    expect(controller.text, '2028-02-29');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller.text, '2028-06-15');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
