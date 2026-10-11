import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/civil_date_input.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(loadSdkRoboto);
  registerCivilDatePickerLayoutTests();
}

void registerCivilDatePickerLayoutTests({
  Future<void> Function(WidgetTester, String)? capture,
  Future<void> Function(WidgetTester, Finder)? input,
}) {
  for (final tasks in [true, false]) {
    for (final brightness in Brightness.values) {
      for (final (size, scale) in [
        (const Size(320, 640), 1.0),
        (const Size(320, 640), 2.0),
        (const Size(390, 640), 2.0),
      ]) {
        testWidgets(
          '${tasks ? 'Tasks Due' : 'Food Expiration'} calendar days are readable at${size.width.toInt()}dp ${brightness.name} ${scale}x',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final controller = TextEditingController(text: '2026-10-15');
            final semantics = tester.ensureSemantics();
            try {
              await tester.pumpWidget(
                MaterialApp(
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                      padding: const EdgeInsets.only(top: 24, bottom: 48),
                    ),
                    child: child!,
                  ),
                  theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: const Color(0xff267461),
                      brightness: brightness,
                    ),
                  ),
                  home: Scaffold(
                    body: tasks
                        ? TaskEditor(
                            panel: true,
                            task: const {
                              'id': 'synthetic-calendar',
                              'title': 'Synthetic calendar',
                              'description': '',
                              'schedule': {'dueDate': '2026-10-15'},
                            },
                            save: (_, _, _) async {},
                          )
                        : Padding(
                            padding: const EdgeInsets.all(20),
                            child: CivilDateInput(
                              controller: controller,
                              label: 'Expiration',
                            ),
                          ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final open = find.byTooltip(
                tasks ? 'Choose Due date' : 'Choose Expiration',
              );
              await tester.ensureVisible(open);
              await tester.pumpAndSettle();
              if (input == null) {
                await tester.tap(open);
              } else {
                await input(tester, open);
              }
              await tester.pumpAndSettle();
              if (capture != null) {
                await capture(
                  tester,
                  '${tasks ? 'tasks' : 'food'}-${brightness.name}-${scale}x${size.width == 320 ? '' : '-390dp'}',
                );
              }
              for (final day in [
                for (var day = 10; day <= 31; day++) day,
                for (var day = 1; day <= 9; day++) day,
              ]) {
                final label = find.descendant(
                  of: find.byType(CalendarDatePicker),
                  matching: find.text('$day'),
                );
                expect(label, findsOneWidget);
                final rich = find.descendant(
                  of: label,
                  matching: find.byType(RichText),
                );
                final paragraph = tester.renderObject<RenderParagraph>(rich);
                final boxes = paragraph.getBoxesForSelection(
                  TextSelection(baseOffset: 0, extentOffset: '$day'.length),
                );
                if (day == 10 || day == 15) {
                  debugPrint(
                    'CALENDAR day=$day paragraph=${paragraph.size} boxes=$boxes',
                  );
                }
                expect(
                  boxes,
                  hasLength(1),
                  reason: 'Day $day must occupy one readable line.',
                );
                final box = boxes.single.toRect();
                // Permit subpixel glyph overhang, not another line or clipping.
                expect(box.left, greaterThanOrEqualTo(-1));
                expect(box.top, greaterThanOrEqualTo(-1));
                expect(box.right, lessThanOrEqualTo(paragraph.size.width + 1));
                expect(
                  box.bottom,
                  lessThanOrEqualTo(paragraph.size.height + 1),
                );
                expect(label.hitTestable(), findsOneWidget);
                expect(paragraph.didExceedMaxLines, isFalse);
                final dayTarget = find.ancestor(
                  of: label,
                  matching: find.byType(InkResponse),
                );
                final target = tester.getRect(dayTarget);
                expect(target.width, greaterThanOrEqualTo(36));
                expect(target.height, greaterThanOrEqualTo(36));
                final localization = MaterialLocalizations.of(
                  tester.element(label),
                );
                final spoken =
                    '${localization.formatDecimal(day)}, ${localization.formatFullDate(DateTime(2026, 10, day))}';
                final node = tester.getSemantics(
                  find.bySemanticsLabel(RegExp('^${RegExp.escape(spoken)}')),
                );
                final flags = node.getSemanticsData().flagsCollection;
                expect(flags.isButton, isTrue);
                expect(flags.isEnabled, ui.Tristate.isTrue);
                expect(
                  flags.isSelected,
                  day == 15 ? ui.Tristate.isTrue : ui.Tristate.isFalse,
                );
                final style = tester.widget<Text>(label).style!;
                final effective = paragraph.textScaler.scale(style.fontSize!);
                expect(paragraph.textScaler.scale(16), 16 * scale);
                if (scale == 2) {
                  expect(effective, greaterThan(16));
                } else {
                  expect(effective, 16);
                }
                if (day == 15) {
                  debugPrint(
                    'CALENDAR target=$target effectiveFont=$effective scaler=$scale',
                  );
                }
              }
              for (final target in [
                find.text('10'),
                find.text('17'),
                find.text('OK'),
              ]) {
                if (input == null) {
                  await tester.tap(target);
                } else {
                  await input(tester, target);
                }
                await tester.pumpAndSettle();
              }
              await tester.pumpAndSettle();
              if (tasks) {
                expect(
                  tester
                      .widget<TextField>(find.byKey(const ValueKey('dueDate')))
                      .controller!
                      .text,
                  '2026-10-17',
                );
              } else {
                expect(controller.text, '2026-10-17');
              }
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox());
              semantics.dispose();
              controller.dispose();
            }
          },
        );
      }
    }
  }
  for (final tasks in [true, false]) {
    testWidgets(
      '${tasks ? 'Tasks Due' : 'Food Expiration'} pending calendar date survives resizing and rotation; closed owner is untouched',
      (tester) async {
        final controller = TextEditingController(text: '2026-10-15');
        final visible = ValueNotifier(true);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff267461),
                  brightness: Brightness.dark,
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(2),
                  padding: const EdgeInsets.only(top: 24, bottom: 48),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (context, show, _) => !show
                      ? const SizedBox.shrink()
                      : tasks
                      ? TaskEditor(
                          panel: true,
                          task: const {
                            'id': 'synthetic-calendar',
                            'title': 'Synthetic calendar',
                            'description': '',
                            'schedule': {'dueDate': '2026-10-15'},
                          },
                          save: (_, _, _) async {},
                        )
                      : CivilDateInput(
                          controller: controller,
                          label: 'Expiration',
                        ),
                ),
              ),
            ),
          );
          final open = find.byTooltip(
            tasks ? 'Choose Due date' : 'Choose Expiration',
          );
          await tester.ensureVisible(open);
          await tester.pumpAndSettle();
          await tester.tap(open);
          await tester.pumpAndSettle();
          await tester.tap(find.text('17'));
          await tester.pumpAndSettle();
          if (capture != null) {
            await capture(
              tester,
              '${tasks ? 'tasks' : 'food'}-pending17-initial',
            );
          }
          for (final size in [
            const Size(390, 800),
            const Size(800, 390),
            const Size(320, 640),
          ]) {
            tester.view.physicalSize = size;
            await tester.binding.setSurfaceSize(size);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
                  .initialDate,
              DateTime(2026, 10, 17),
            );
            if (capture != null) {
              await capture(
                tester,
                '${tasks ? 'tasks' : 'food'}-pending17-${size.width.toInt()}x${size.height.toInt()}',
              );
            }
          }
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          final chosen = tasks
              ? tester
                    .widget<TextField>(find.byKey(const ValueKey('dueDate')))
                    .controller!
                    .text
              : controller.text;
          expect(chosen, '2026-10-17');
          final chosenController = tasks
              ? tester
                    .widget<TextField>(find.byKey(const ValueKey('dueDate')))
                    .controller!
              : controller;
          await tester.ensureVisible(open);
          await tester.tap(open);
          await tester.pumpAndSettle();
          await tester.tap(find.text('19'));
          await tester.pumpAndSettle();
          visible.value = false;
          await tester.pumpAndSettle();
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          expect(chosenController.text, '2026-10-17');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          visible.dispose();
          controller.dispose();
        }
      },
    );
  }
}
