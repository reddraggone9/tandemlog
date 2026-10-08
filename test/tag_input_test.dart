import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/tag_filter_picker.dart';
import 'package:tandemlog/presentation/tag_input.dart';

void main() {
  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    testWidgets('hardware ${key.keyLabel} propagates active IME composition', (
      tester,
    ) async {
      final query = TextEditingController();
      addTearDown(query.dispose);
      var propagated = 0, submitted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent && event.logicalKey == key)
                  propagated++;
                return KeyEventResult.ignored;
              },
              child: TagInput(
                tags: const ['home'],
                selected: const {},
                queryController: query,
                allowCreate: true,
                onChanged: (_) {},
                onSubmitQuery: () {
                  submitted++;
                  return false;
                },
                onDropdownChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('tag-search')));
      query.value = const TextEditingValue(
        text: 'hom',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(
        propagated,
        1,
        reason: 'candidate confirmation belongs to the native IME',
      );
      expect(submitted, 0);
      expect(query.value.composing, const TextRange(start: 0, end: 3));
    });
  }

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter]) {
    testWidgets('hardware ArrowDown then ${key.keyLabel} selects existing option', (tester) async {
      final query = TextEditingController();
      addTearDown(query.dispose);
      var selected = <String>{};
      var created = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
        builder: (context, update) => TagInput(
          tags: const ['Planning'], selected: selected, queryController: query,
          clearQueryOnSelection: true, allowCreate: true,
          onChanged: (value) => update(() => selected = value),
          onSubmitQuery: () { created++; return true; },
          onDropdownChanged: (_) {},
        ),
      ))));
      await tester.enterText(find.byKey(const ValueKey('tag-search')), 'plan');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(selected, {'Planning'});
      expect(query.text, isEmpty);
      expect(created, 0);
      await tester.enterText(find.byKey(const ValueKey('tag-search')), 'Planning');
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(selected, {'Planning'}, reason: 'repeated Enter is idempotent');
      expect(created, 0);
    });
  }

  testWidgets(
    'opaque __create inventory tag and creation row keep separate identities',
    (tester) async {
      final controller = TextEditingController(text: 'create');
      addTearDown(controller.dispose);
      var selected = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => TagInput(
                tags: const ['__create'],
                selected: selected,
                queryController: controller,
                allowCreate: true,
                onChanged: (value) => update(() => selected = value),
                onSubmitQuery: () => true,
                onDropdownChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('tag-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-option-__create')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-create')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('tag-option-__create')));
      await tester.pumpAndSettle();
      expect(selected, {'__create'});
    },
  );

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
