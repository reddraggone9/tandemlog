import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/toolbar_action.dart';

class _Count {
  int paints = 0;
}

class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe(this.count, {required super.child});
  final _Count count;
  @override
  _RenderProbe createRenderObject(BuildContext context) => _RenderProbe(count);
  @override
  void updateRenderObject(BuildContext context, _RenderProbe object) {
    object.count = count;
  }
}

class _RenderProbe extends RenderProxyBox {
  _RenderProbe(this.count);
  _Count count;
  @override
  void paint(PaintingContext context, Offset offset) {
    count.paints++;
    super.paint(context, offset);
  }
}

class _Host {
  final page = _Count(), toolbar = _Count(), editor = _Count();
  int activations = 0;
  Widget build(Widget strip) => MaterialApp(
    home: Center(
      child: RepaintBoundary(
        child: SizedBox(
          width: 400,
          height: 300,
          child: _PaintProbe(
            page,
            child: Column(
              children: [
                _PaintProbe(
                  toolbar,
                  child: SizedBox(
                    height: 48,
                    child: Material(
                      child: TextButton(
                        onPressed: () => activations++,
                        child: const Text('Static toolbar'),
                      ),
                    ),
                  ),
                ),
                KeyedSubtree(
                  key: const ValueKey('reserved-strip'),
                  child: strip,
                ),
                Expanded(
                  child: _PaintProbe(
                    editor,
                    child: const ColoredBox(
                      color: Colors.white,
                      child: Text('Static editor'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<({int page, int toolbar, int editor})> _ticks(
  WidgetTester tester,
  _Host host,
  Widget strip,
) async {
  await tester.pumpWidget(host.build(strip));
  // Finish initial layout/compositing and a first animation tick. No settle:
  // an indeterminate indicator intentionally schedules frames continuously.
  await tester.pump(const Duration(milliseconds: 32));
  final initial = (
    page: host.page.paints,
    toolbar: host.toolbar.paints,
    editor: host.editor.paints,
  );
  final painter = find.descendant(
    of: find.byType(LinearProgressIndicator),
    matching: find.byType(CustomPaint),
  );
  expect(painter, findsOneWidget);
  final beforePainter = tester.widget<CustomPaint>(painter).painter;
  for (var tick = 0; tick < 4; tick++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    tester.widget<CustomPaint>(painter).painter,
    isNot(same(beforePainter)),
    reason: 'The existing progress animation must keep advancing.',
  );
  expect(tester.binding.hasScheduledFrame, isTrue);
  return (
    page: host.page.paints - initial.page,
    toolbar: host.toolbar.paints - initial.toolbar,
    editor: host.editor.paints - initial.editor,
  );
}

void main() {
  testWidgets('unbounded progress control repaints static siblings', (
    tester,
  ) async {
    final host = _Host();
    // Exact old reserved strip; independent control remains unbounded after fix.
    final delta = await _ticks(
      tester,
      host,
      const SizedBox(height: 2, child: LinearProgressIndicator(minHeight: 2)),
    );
    expect(delta.page, greaterThan(0));
    expect(delta.toolbar, greaterThan(0));
    expect(delta.editor, greaterThan(0));
    expect(
      tester.getSize(find.byKey(const ValueKey('reserved-strip'))),
      const Size(400, 2),
      reason: 'The legacy indeterminate strip fills bounded width.',
    );
    await tester.pumpWidget(host.build(const SizedBox(height: 2)));
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('reserved-strip'))),
      const Size(0, 2),
      reason: 'The legacy idle box has zero width in this loose Column.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('actual toolbar progress isolates tick paints and keeps geometry', (
    tester,
  ) async {
    final host = _Host();
    final delta = await _ticks(tester, host, toolbarProgress(busy: true));
    // Expected to FAIL before the proposed local RepaintBoundary and pass after.
    // No workload/pixel budget is altered, and the animation remains live.
    expect(delta.page, 0);
    expect(delta.toolbar, 0);
    expect(delta.editor, 0);
    expect(
      tester.getSize(find.byKey(const ValueKey('reserved-strip'))),
      const Size(400, 2),
    );
    await tester.pumpWidget(host.build(toolbarProgress(busy: false)));
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('reserved-strip'))),
      const Size(0, 2),
      reason:
          'The repaint boundary preserves the exact legacy idle constraints.',
    );
    await tester.tap(find.text('Static toolbar'));
    await tester.pump();
    expect(
      host.activations,
      1,
      reason: 'Isolating progress paint must not intercept sibling controls.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
