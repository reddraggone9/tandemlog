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

  Future<GlobalKey> pumpHeading(
    WidgetTester tester, {
    required String title,
    required double width,
    double inset = 0,
    double scale = 1,
  }) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: CustomScrollView(
                  slivers: [
                    SliverMainAxisGroup(
                      slivers: [
                        StickyTaskGroupHeading(
                          title: title,
                          headingKey: key,
                          inset: inset,
                        ),
                        SliverList.list(
                          children: const [SizedBox(height: 2000)],
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
    return key;
  }

  testWidgets('compact background spans the viewport; only the text is inset', (
    tester,
  ) async {
    const title = 'Someday';
    final key = await pumpHeading(tester, title: title, width: 390, inset: 16);
    expect(tester.getRect(find.byKey(key)).left, 0);
    expect(tester.getRect(find.byKey(key)).width, 390);
    expect(tester.getTopLeft(find.text(title)).dx, 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide layouts keep their zero text inset', (tester) async {
    const title = 'Someday';
    final key = await pumpHeading(tester, title: title, width: 700);
    expect(tester.getRect(find.byKey(key)).width, 700);
    expect(tester.getTopLeft(find.text(title)).dx, 0);
  });

  testWidgets('a wrapped inset title keeps its measured extent', (
    tester,
  ) async {
    const title = 'Wednesday · 2026-10-07';
    await pumpHeading(tester, title: title, width: 780);
    final painter = TextPainter(
      text: TextSpan(
        text: title,
        style: Theme.of(tester.element(find.text(title))).textTheme.titleSmall,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final singleLine = painter.height;
    final natural = painter.width;
    painter.dispose();
    // Fits the full width but wraps once the inset narrows it: an extent
    // measured over the full width would clip the second line.
    final width = natural + 16;
    final key = await pumpHeading(
      tester,
      title: title,
      width: width,
      inset: 16,
    );
    await tester.pump();
    final text = tester.getSize(find.text(title));
    expect(text.width, width - 32);
    expect(text.height, greaterThan(singleLine));
    expect(tester.getSize(find.byKey(key)).height, text.height + 20);
    expect(tester.takeException(), isNull);
  });

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
