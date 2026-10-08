import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/tag_filter_picker.dart';

void main() {
  for (final width in [260.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'query underline gap stays stable with chips at $width/$scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });
          var selected = <String>{};
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                inputDecorationTheme: const InputDecorationTheme(
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return TagFilterPicker(
                      tags: const ['backlog', 'a-long-selected-tag-name'],
                      selected: selected,
                      onChanged: (value) => setState(() => selected = value),
                      onQueryChanged: () {},
                      onDropdownChanged: (_) {},
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final search = find.byKey(const ValueKey('tag-search'));
          final underline = find.byKey(const ValueKey('tag-autocomplete'));
          final gaps = <double>[];
          for (final tags in [
            <String>{},
            {'backlog'},
            {'backlog', 'a-long-selected-tag-name'},
          ]) {
            update(() => selected = tags);
            await tester.pumpAndSettle();
            await tester.tap(search);
            await tester.enterText(search, '');
            await tester.pumpAndSettle();
            final editable = tester.state<EditableTextState>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            );
            final render = editable.renderEditable;
            final caret = render
                .getLocalRectForCaret(const TextPosition(offset: 0))
                .shift(render.localToGlobal(Offset.zero));
            final bottom = tester.getRect(underline).bottom;
            final gap = bottom - caret.bottom;
            gaps.add(gap);
            expect(
              gap,
              inInclusiveRange(0, 16),
              reason: 'caret near its underline with $tags',
            );
            expect(tester.getRect(search).bottom, closeTo(bottom, 1));
            expect(
              tester
                  .getRect(
                    find.ancestor(
                      of: find.byTooltip('Clear tag filters'),
                      matching: find.byType(IconButton),
                    ),
                  )
                  .bottom,
              closeTo(bottom, 1),
              reason: 'clear control follows the last query row',
            );
            expect(tester.takeException(), isNull);
          }
          expect(
            gaps.reduce((a, b) => a > b ? a : b) -
                gaps.reduce((a, b) => a < b ? a : b),
            lessThanOrEqualTo(1),
            reason:
                'selection must not shift query baseline relative to underline',
          );
        },
      );
    }
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets('initial suggestions survive IME relayout at $scale text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      final changes = <bool>[];
      final selections = <Set<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 580),
                  TagFilterPicker(
                    tags: const ['home'],
                    selected: const {},
                    onChanged: selections.add,
                    onQueryChanged: () {},
                    onDropdownChanged: changes.add,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      );
      final search = find.byKey(const ValueKey('tag-search'));
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand tag options'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-results')), findsOneWidget);
      // No typing/reopening/explicit ensureVisible after the IME begins. The
      // first metrics frame can clip the old anchor before EditableText scrolls.
      tester.view.viewInsets = const FakeViewPadding(bottom: 380);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-results')), findsOneWidget);
      expect(changes, [
        true,
      ], reason: 'No silent collapse/reopen during resize.');
      final option = find.byKey(const ValueKey('tag-option-home'));
      expect(option.hitTestable(), findsOneWidget);
      expect(tester.getRect(option).bottom, lessThanOrEqualTo(420));
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(selections, [
        {'home'},
      ]);
      await tester.tap(find.byTooltip('Expand tag options'));
      await tester.pumpAndSettle();
      // Deliberate user scrolling away still dismisses an orphaned popup.
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-results')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }
  testWidgets(
    'below-first dialog overlay uses content size and stays stable through queries and metrics',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      final semanticsHandle = tester.ensureSemantics();

      final selections = <Set<String>>[];
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
                          onChanged: selections.add,
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
      final option = tester.getSemantics(
        find.byKey(const ValueKey('tag-option-home')),
      );
      final optionData = option.getSemanticsData();
      expect(optionData.label, '#home');
      expect(optionData.hasAction(SemanticsAction.tap), isTrue);
      // The result paints outside the dialog scroll viewport: its semantics
      // must not remain beneath that clipping ancestor on Android.
      final ancestors = <SemanticsNode>[];
      SemanticsNode? parent = option.parent;
      while (parent != null) {
        ancestors.add(parent);
        parent = parent.parent;
      }
      expect(
        ancestors
            .where((node) => node.flagsCollection.hasImplicitScrolling)
            .length,
        1,
      );
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
      // Accessibility activation uses the same exact selection callback.
      await tester.enterText(search, 'home');
      await tester.pumpAndSettle();
      final activeOption = tester.getSemantics(
        find.byKey(const ValueKey('tag-option-home')),
      );
      activeOption.owner!.performAction(activeOption.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(selections, [
        {'home'},
      ]);
      expect(find.byKey(const ValueKey('tag-results')), findsNothing);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      // Removing an open picker removes its overlay and semantic actions too.
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-results')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-results')), findsNothing);
      expect(tester.takeException(), isNull);
      semanticsHandle.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
