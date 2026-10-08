import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/tag_input.dart';

void main() {
  testWidgets('many selected chips keep query and results reachable with IME', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final query = TextEditingController();
    addTearDown(query.dispose);
    final tags = List.generate(20, (i) => 'tag-$i-long-selected-name');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TagInput(
                tags: tags,
                selected: tags.toSet(),
                queryController: query,
                label: 'Tags',
                onChanged: (_) {},
                onDropdownChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    final field = find.byKey(const ValueKey('tag-search'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.enterText(field, 'tag');
    await tester.pumpAndSettle();
    final popup = find.byKey(const ValueKey('tag-results'));
    expect(popup, findsOneWidget);
    expect(tester.getRect(popup).height, greaterThanOrEqualTo(56));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    final keyboardTop = 820.0 - 260;
    final queryRect = tester.getRect(field);
    expect(queryRect.top, greaterThanOrEqualTo(0));
    expect(queryRect.bottom, lessThanOrEqualTo(keyboardTop));
    final popupRect = tester.getRect(popup);
    expect(popupRect.height, greaterThanOrEqualTo(56));
    expect(popupRect.top, greaterThanOrEqualTo(0));
    expect(popupRect.bottom, lessThanOrEqualTo(keyboardTop));
    expect(
      find
          .byKey(const ValueKey('tag-option-tag-0-long-selected-name'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
