import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/civil_date_input.dart';

Future<void> verifyDateInputAlignment(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  Future<void> Function(String)? capture,
}) async {
  final normal = TextEditingController(text: '2026-10-15');
  final date = TextEditingController(text: '2026-10-15');
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('date-align-${brightness.name}-$textScale'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff267461),
          brightness: brightness,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                key: const ValueKey('normal-value'),
                controller: normal,
                decoration: const InputDecoration(labelText: 'Ordinary value'),
              ),
              const SizedBox(height: 12),
              CivilDateInput(
                fieldKey: const ValueKey('date-value'),
                controller: date,
                label: 'Expiration',
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  Finder editable(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(EditableText),
  );
  expect(
    tester.getTopLeft(editable('date-value')).dx,
    tester.getTopLeft(editable('normal-value')).dx,
    reason: 'same value inset',
  );
  expect(
    tester.getTopLeft(find.text('Expiration')).dx,
    tester.getTopLeft(find.text('Ordinary value')).dx,
    reason: 'same floating-label inset',
  );
  expect(
    tester.getSize(find.byTooltip('Choose Expiration')).shortestSide,
    greaterThanOrEqualTo(48),
  );
  await capture?.call('populated');
  await tester.enterText(find.byKey(const ValueKey('date-value')), '');
  await tester.pumpAndSettle();
  expect(find.text('YYYY-MM-DD'), findsOneWidget);
  expect(
    tester.getTopLeft(find.text('YYYY-MM-DD')).dx,
    tester.getTopLeft(editable('normal-value')).dx,
  );
  await capture?.call('focused-blank');
  await tester.tap(find.byTooltip('Choose Expiration'));
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsOneWidget);
  await tester.tap(find.text('Cancel'));
  await tester.pumpAndSettle();
  expect(date.text, isEmpty);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  normal.dispose();
  date.dispose();
}

void main() {
  for (final sample in [(900.0, 1.0), (320.0, 2.0)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'shared date inset ${sample.$1} ${sample.$2}x ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(sample.$1, 1000);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await verifyDateInputAlignment(
            tester,
            brightness: brightness,
            textScale: sample.$2,
          );
        },
      );
    }
  }
}
