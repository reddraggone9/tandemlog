import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_editor.dart';

void main() => registerDateTimeLayoutTests();
void registerDateTimeLayoutTests({
  Future<void> Function(WidgetTester, String)? capture,
}) {
  testWidgets(
    'populated rows fit at measured boundary and retain composing drafts',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const source = {
        'id': 'test',
        'title': 'Original',
        'description': '',
        'schedule': {'dueDate': '2026-10-04', 'dueTime': '23:59'},
      };
      for (final bulk in [false, true]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          final key = GlobalKey();
          var viewportSize = const Size(1100, 1000);
          Widget host() => MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQueryData(
                size: viewportSize,
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            theme: ThemeData(
              inputDecorationTheme: const InputDecorationTheme(
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: viewportSize,
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: bulk
                    ? BulkTaskEditor(
                        key: key,
                        panel: true,
                        tasks: const [source, source],
                        onSave: (_) async {},
                      )
                    : TaskEditor(
                        key: key,
                        panel: true,
                        task: source,
                        save: (_, _, _) async {},
                      ),
              ),
            ),
          );
          await tester.binding.setSurfaceSize(const Size(1100, 1000));
          await tester.pumpWidget(host());
          await tester.pumpAndSettle();
          final date = find.byKey(const ValueKey('dueDate')),
              time = find.byKey(const ValueKey('dueTime'));
          final editable = tester.widget<EditableText>(
            find.descendant(of: time, matching: find.byType(EditableText)),
          );
          double measure(String text) {
            final p = TextPainter(
              text: TextSpan(text: text, style: editable.style),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout();
            final w = p.width;
            p.dispose();
            return w;
          }

          final timeWidth = (measure('23:59') + 60 > measure('HH:mm') + 10
              ? measure('23:59') + 60
              : measure('HH:mm') + 10);
          final dateWidth =
              (measure('2026-10-04') > measure('YYYY-MM-DD')
                  ? measure('2026-10-04')
                  : measure('YYYY-MM-DD')) +
              60;
          final boundary =
              (12 +
                      (bulk ? 96 : 0) +
                      (timeWidth * 8 / 3 > dateWidth * 8 / 5
                          ? timeWidth * 8 / 3
                          : dateWidth * 8 / 5))
                  .ceilToDouble();
          debugPrint('LAYOUT bulk=$bulk scale=$scale rowBoundary=$boundary');
          var focused = false;
          for (final delta in [1.0, -1.0, 1.0]) {
            viewportSize = Size(boundary + 40 + delta, 1000);
            await tester.binding.setSurfaceSize(viewportSize);
            await tester.pumpWidget(host());
            await tester.pumpAndSettle();
            if (focused) {
              expect(
                tester.widget<TextField>(time).focusNode!.hasFocus,
                isTrue,
              );
              expect(
                tester.widget<TextField>(time).controller!.value.composing,
                const TextRange(start: 0, end: 2),
              );
            }
            await tester.ensureVisible(time);
            await tester.pumpAndSettle();
            expect(
              tester.getTopLeft(time).dy,
              delta > 0
                  ? closeTo(tester.getTopLeft(date).dy, .5)
                  : greaterThan(tester.getTopLeft(date).dy),
            );
            if (delta > 0) {
              for (final f in [date, time]) {
                final e = find.descendant(
                  of: f,
                  matching: find.byType(EditableText),
                );
                final state = tester.state<EditableTextState>(e);
                final p = TextPainter(
                  text: TextSpan(
                    text: state.widget.controller.text,
                    style: state.widget.style,
                  ),
                  textDirection: TextDirection.ltr,
                  textScaler: TextScaler.linear(scale),
                )..layout();
                expect(
                  state.renderEditable.size.width,
                  greaterThanOrEqualTo(p.width + 1),
                );
                p.dispose();
              }
              expect(
                tester.getSize(date).width / tester.getSize(time).width,
                closeTo(5 / 3, .01),
              );
              expect(
                tester.getSize(find.byTooltip('Choose Due date')).shortestSide,
                greaterThanOrEqualTo(48),
              );
              if (bulk) {
                expect(
                  tester
                      .getSize(find.byKey(const ValueKey('dueTimeApply')))
                      .shortestSide,
                  greaterThanOrEqualTo(48),
                );
              }
              if (!focused) {
                final blankDate = find.byKey(const ValueKey('startDate'));
                await tester.ensureVisible(blankDate);
                await tester.tap(blankDate);
                await tester.pumpAndSettle();
                final blankEditable = find.descendant(
                  of: blankDate,
                  matching: find.byType(EditableText),
                );
                expect(
                  tester
                      .state<EditableTextState>(blankEditable)
                      .renderEditable
                      .size
                      .width,
                  greaterThanOrEqualTo(measure('YYYY-MM-DD') + 1),
                );
                await tester.ensureVisible(date);
                if (scale <= 1.3) {
                  await tester.tap(find.byTooltip('Choose Due date'));
                  await tester.pumpAndSettle();
                  expect(find.byType(DatePickerDialog), findsOneWidget);
                  await tester.tap(
                    find.descendant(
                      of: find.byType(DatePickerDialog),
                      matching: find.text('Cancel'),
                    ),
                  );
                  await tester.pumpAndSettle();
                }
              }
              expect(
                tester.getSize(find.byTooltip('Clear Due time')).shortestSide,
                greaterThanOrEqualTo(48),
              );
            }
            await capture?.call(
              tester,
              '${bulk ? 'bulk' : 'single'}-$scale-${delta > 0 ? 'above' : 'below'}',
            );
            await tester.tap(time);
            await tester.pumpAndSettle();
            tester
                .widget<TextField>(time)
                .controller!
                .value = const TextEditingValue(
              text: '23:59',
              selection: TextSelection.collapsed(offset: 3),
              composing: TextRange(start: 0, end: 2),
            );
            await tester.pump();
            focused = true;
          }
          expect(tester.widget<TextField>(time).focusNode!.hasFocus, isTrue);
          expect(
            tester.widget<TextField>(time).controller!.value.composing,
            const TextRange(start: 0, end: 2),
          );
          await tester.tap(find.byTooltip('Clear Due time'));
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(date).controller!.text, '2026-10-04');
          await tester.enterText(date, '');
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(time).controller!.text, isEmpty);
          await tester.enterText(date, '2026-10-04');
          await tester.pumpAndSettle();

          expect(tester.widget<TextField>(time).controller!.text, isEmpty);
          await tester.tap(time);
          await tester.enterText(time, '25:00');
          await tester.pumpAndSettle();
          expect(find.text('Due time must be HH:mm.'), findsOneWidget);
          viewportSize = Size(boundary + 39, 1000);
          await tester.binding.setSurfaceSize(viewportSize);
          await tester.pumpWidget(host());
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(time).focusNode!.hasFocus, isTrue);
          expect(tester.widget<TextField>(time).controller!.text, '25:00');
          await tester.enterText(time, '00:00');
          await tester.pumpAndSettle();
          expect(find.text('Due time must be HH:mm.'), findsNothing);
          expect(tester.widget<TextField>(date).controller!.text, '2026-10-04');

          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
}
