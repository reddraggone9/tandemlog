import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/civil_date_input.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

const _monthButton = ValueKey('civil-month-button');
const _yearButton = ValueKey('civil-year-button');

Future<TextEditingController> _open(
  WidgetTester tester,
  String text, {
  Size size = const Size(1280, 1000),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TextEditingController(text: text);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: CivilDateInput(controller: controller, label: 'Expiration'),
      ),
    ),
  );
  await tester.tap(find.byTooltip('Choose Expiration'));
  await tester.pumpAndSettle();
  return controller;
}

Finder _inDialog(Finder finder) =>
    find.descendant(of: find.byType(Dialog), matching: finder);

Text _label(WidgetTester tester, Key key) => tester.widget<Text>(
  find.descendant(of: find.byKey(key), matching: find.byType(Text)),
);

Future<void> _ok(WidgetTester tester) async {
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadSdkRoboto);

  testWidgets('header is month and year menus beside paging, without modes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, '2026-10-15');
    expect(_label(tester, _monthButton).data, 'October');
    expect(_label(tester, _yearButton).data, '2026');
    expect(find.byIcon(Icons.arrow_drop_down), findsNWidgets(2));
    expect(find.byTooltip('Previous month'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsOneWidget);
    // Typing belongs to the date field itself; the dialog has no input mode.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byTooltip('Switch to input'), findsNothing);
    expect(find.byType(InputDatePickerFormField), findsNothing);
    expect(find.text('Month / year'), findsNothing);
    final month = tester.getSemantics(find.byKey(_monthButton));
    expect(month.label, 'Select month');
    expect(month.value, 'October 2026');
    expect(month.flagsCollection.isButton, isTrue);
    final year = tester.getSemantics(find.byKey(_yearButton));
    expect(year.label, 'Select year');
    expect(year.value, '2026');
    semantics.dispose();
  });

  testWidgets('month menu opens the month grid and returns to the day grid', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = await _open(tester, '2026-10-31');
    await tester.tap(find.byKey(_monthButton));
    await tester.pumpAndSettle();
    expect(_inDialog(find.text('31')), findsNothing);
    expect(find.byType(CivilYearGrid), findsNothing);
    for (final short in ['Jan', 'Jun', 'Dec']) {
      expect(_inDialog(find.text(short)), findsOneWidget);
    }
    expect(find.bySemanticsLabel('February 2026'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsNothing);
    await tester.tap(find.text('Feb'));
    await tester.pumpAndSettle();
    expect(_label(tester, _monthButton).data, 'February');
    expect(_inDialog(find.text('28')), findsOneWidget);
    expect(_inDialog(find.text('Feb')), findsNothing);
    // Only OK changes the caller's draft; the tentative day was clamped.
    expect(controller.text, '2026-10-31');
    await _ok(tester);
    expect(controller.text, '2026-02-28');
    semantics.dispose();
  });

  testWidgets('year menu lists years; a year opens its months, then days', (
    tester,
  ) async {
    final controller = await _open(tester, '2026-10-15');
    await tester.tap(find.byKey(_yearButton));
    await tester.pumpAndSettle();
    expect(find.byType(CivilYearGrid), findsOneWidget);
    final year2029 = find.descendant(
      of: find.byType(CivilYearGrid),
      matching: find.text('2029'),
    );
    await tester.scrollUntilVisible(
      year2029,
      100,
      scrollable: find
          .descendant(
            of: find.byType(CivilYearGrid),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(year2029);
    await tester.pumpAndSettle();
    expect(find.byType(CivilYearGrid), findsNothing);
    expect(_label(tester, _yearButton).data, '2029');
    expect(_inDialog(find.text('Mar')), findsOneWidget);
    expect(controller.text, '2026-10-15');
    await tester.tap(find.text('Mar'));
    await tester.pumpAndSettle();
    expect(_label(tester, _monthButton).data, 'March');
    expect(_label(tester, _yearButton).data, '2029');
    expect(_inDialog(find.text('31')), findsOneWidget);
    await _ok(tester);
    expect(controller.text, '2029-03-15');
  });

  testWidgets('previous and next page months without changing selection', (
    tester,
  ) async {
    final controller = await _open(tester, '2026-10-15');
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(_label(tester, _monthButton).data, 'November');
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(_label(tester, _monthButton).data, 'September');
    await _ok(tester);
    expect(controller.text, '2026-10-15');
  });

  testWidgets('keyboard reaches the month menu and a month', (tester) async {
    final controller = await _open(tester, '2026-10-15');
    bool focusedIn(Finder finder) {
      final focused = FocusManager.instance.primaryFocus?.context;
      return focused != null &&
          finder.evaluate().any(
            (element) =>
                element == focused ||
                find
                    .descendant(
                      of: find.byWidget(element.widget),
                      matching: find.byElementPredicate((e) => e == focused),
                    )
                    .evaluate()
                    .isNotEmpty,
          );
    }

    for (
      var step = 0;
      step < 12 && !focusedIn(find.byKey(_monthButton));
      step++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(focusedIn(find.byKey(_monthButton)), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_inDialog(find.text('Mar')), findsOneWidget);
    final march = find.ancestor(
      of: find.text('Mar'),
      matching: find.byType(TextButton),
    );
    for (var step = 0; step < 16 && !focusedIn(march); step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(focusedIn(march), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_label(tester, _monthButton).data, 'March');
    await _ok(tester);
    expect(controller.text, '2026-03-15');
  });

  for (final (size, scale, date, month) in [
    (const Size(1280, 1000), 1.0, '2026-09-15', 'September'),
    (const Size(1280, 1000), 2.0, '2026-09-15', 'September'),
    (const Size(320, 900), 1.0, '2026-09-15', 'Sep'),
    (const Size(320, 900), 2.0, '2026-09-15', 'Sep'),
    (const Size(320, 900), 3.0, '9999-12-31', 'Dec'),
  ]) {
    testWidgets(
      'month, year and paging all fit at ${size.width.toInt()}dp ${scale}x',
      (tester) async {
        await _open(tester, date, size: size, scale: scale);
        expect(_label(tester, _monthButton).data, month);
        final previous = tester.getRect(find.byIcon(Icons.chevron_left));
        for (final key in [_monthButton, _yearButton]) {
          final text = find.descendant(
            of: find.descendant(
              of: find.byKey(key),
              matching: find.byType(Text),
            ),
            matching: find.byType(RichText),
          );
          final paragraph = tester.renderObject<RenderParagraph>(text);
          final label = paragraph.text.toPlainText();
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(
            paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            ),
            hasLength(1),
            reason: '$label stays on one unclipped line',
          );
          expect(
            paragraph.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(paragraph.size.width + .5),
            reason: '$label is not ellipsized',
          );
          // Header labels never drop below 100%.
          expect(paragraph.textScaler.scale(14), greaterThanOrEqualTo(14));
          expect(
            tester.getRect(find.byKey(key)).right,
            lessThanOrEqualTo(previous.left),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (size, scale) in [
    (const Size(1280, 1000), 1.0),
    (const Size(320, 900), 2.0),
  ]) {
    testWidgets(
      'dialog height fits its content at ${size.width.toInt()}dp ${scale}x',
      (tester) async {
        await _open(tester, '2026-10-15', size: size, scale: scale);
        final dialog = tester.getRect(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first,
        );
        final lastDay = tester.getRect(_inDialog(find.text('31')));
        final ok = tester.getRect(find.text('OK'));
        // October 2026 needs five week rows; the grid keeps room for six.
        // Anything beyond one spare row plus the action bar is dead space.
        final rowHeight = scale > 1.3 ? 48 + (scale - 1) * 30 : 48.0;
        expect(ok.top - lastDay.bottom, lessThan(rowHeight * 1.5 + 32));
        expect(dialog.bottom - ok.bottom, lessThan(24));
        expect(
          dialog.height,
          lessThan(568 * scale - 64),
          reason: 'The former fixed 568dp-per-scale height left a large gap.',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
