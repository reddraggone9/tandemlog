import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/tag_filter_picker.dart';

void main() {
  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'shared B layout keeps chips above full-width query at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 820));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 440,
                  child: TagFilterPicker(
                    tags: const ['home', 'backlog'],
                    selected: const {'home'},
                    onChanged: (_) {},
                    onQueryChanged: () {},
                    onDropdownChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final chip = tester.getRect(
          find.byKey(const ValueKey('selected-tag-home')),
        );
        final query = tester.getRect(find.byKey(const ValueKey('tag-search')));
        final field = tester.getRect(
          find.byKey(const ValueKey('tag-autocomplete')),
        );
        expect(
          query.top,
          greaterThanOrEqualTo(chip.bottom),
          reason: 'selected tags occupy their own row above the query',
        );
        expect(query.left, closeTo(field.left, 1));
        expect(
          query.width,
          greaterThanOrEqualTo(field.width - 100),
          reason: 'query uses the full row except two 48px controls',
        );
      },
    );
  }
}
