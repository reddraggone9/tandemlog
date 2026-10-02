import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/sticky_task_group.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('native heading pins and pushes off at ${scale}x text', (
      tester,
    ) async {
      final controller = ScrollController();
      final first = GlobalKey();
      final next = GlobalKey();
      final someday = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 48, child: Text('Fixed toolbar')),
                  const SizedBox(height: 64, child: Text('Selection controls')),
                  Expanded(
                    child: CustomScrollView(
                      controller: controller,
                      slivers: [
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                        for (final (title, key, count) in [
                          ('Thursday · 2026-10-01', first, 24),
                          ('Friday · 2026-10-02', next, 1),
                          ('Someday', someday, 20),
                        ])
                          SliverMainAxisGroup(
                            slivers: [
                              StickyTaskGroupHeading(
                                title: title,
                                headingKey: key,
                              ),
                              SliverList.list(
                                children: [
                                  for (var i = 0; i < count; i++)
                                    SizedBox(
                                      height: 48,
                                      child: Text('$title $i'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      const top = 112.0;
      controller.jumpTo(300);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(first)).dy, top);
      expect(find.text('Thursday · 2026-10-01'), findsOneWidget);
      final height = tester.getSize(find.byKey(first)).height;
      final nextOffset = 100 + height + 24 * 48;
      controller.jumpTo(nextOffset - height / 2);
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(first)).dy,
        closeTo(top - height / 2, .01),
      );
      expect(
        tester.getTopLeft(find.byKey(next)).dy,
        closeTo(top + height / 2, .01),
      );
      controller.jumpTo(nextOffset + 20);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(next)).dy, top);
      // A one-row group pushes away its heading instead of retaining a stale
      // overlay over the next group.
      controller.jumpTo(nextOffset + height + 48 + 20);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(someday)).dy, top);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('heading wraps to its measured extent and has one header node', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final key = GlobalKey();
    const title = 'Wednesday · 2026-10-07';
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                child: CustomScrollView(
                  slivers: [
                    SliverMainAxisGroup(
                      slivers: [
                        StickyTaskGroupHeading(title: title, headingKey: key),
                        SliverList.list(
                          children: const [SizedBox(height: 1000)],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(key)).height, greaterThan(70));
    expect(find.bySemanticsLabel(title), findsOneWidget);
    expect(
      tester
          .getSemantics(find.text(title))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
