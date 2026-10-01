import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/tag_filter_picker.dart';

void main() {
  testWidgets(
    'below-first dialog overlay uses content size and stays stable through queries and metrics',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      final tags = ['home', ...List.generate(30, (i) => 'label-$i')];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Filter'),
                    content: SizedBox(
                      width: 400,
                      child: SingleChildScrollView(
                        child: TagFilterPicker(
                          tags: tags,
                          selected: const {},
                          onChanged: (_) {},
                          onQueryChanged: () {},
                          onDropdownChanged: (_) {},
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final dialog = tester.getRect(find.byType(AlertDialog));
      final search = find.byKey(const ValueKey('tag-search')),
          popup = find.byKey(const ValueKey('tag-results')),
          anchor = find.byKey(const ValueKey('tag-autocomplete'));
      await tester.tap(search);
      await tester.pumpAndSettle();
      for (final query in ['', 'home', 'not-a-tag']) {
        await tester.enterText(search, query);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(popup).top,
          greaterThanOrEqualTo(tester.getRect(anchor).bottom),
        );
        expect(tester.getRect(popup).bottom, lessThanOrEqualTo(892));
        expect(tester.getSize(popup).height, greaterThanOrEqualTo(48));
        expect(tester.getRect(find.byType(AlertDialog)), dialog);
        if (query.isNotEmpty) {
          expect(tester.getSize(popup).height, lessThan(100));
        }
      }
      // Keyboard appears without another query. The overlay uses the new usable
      // viewport rather than the old dialog footer or the side with most space.
      tester.view.viewInsets = const FakeViewPadding(bottom: 380);
      await tester.pumpAndSettle();
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      await tester.tap(search);
      await tester.pumpAndSettle();
      for (final query in ['', 'home', 'not-a-tag']) {
        await tester.enterText(search, query);
        await tester.pumpAndSettle();
        expect(tester.getRect(popup).bottom, lessThanOrEqualTo(512));
        expect(tester.getRect(popup).top, greaterThanOrEqualTo(8));
        expect(tester.getSize(popup).height, greaterThanOrEqualTo(48));
        expect(tester.widget<TextField>(search).focusNode!.hasFocus, true);
      }
      tester.view.resetViewInsets();
      tester.view.physicalSize = const Size(600, 650);
      await tester.pumpAndSettle();
      await tester.tap(search);
      await tester.enterText(search, 'home');
      await tester.pumpAndSettle();
      expect(
        tester.getRect(popup).top,
        greaterThanOrEqualTo(tester.getRect(anchor).bottom),
      );
      expect(tester.takeException(), isNull);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
