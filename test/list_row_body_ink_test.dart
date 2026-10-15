import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/list_row_surface.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 720.0]) {
      for (final ripple in [false, true]) {
        testWidgets(
          'body ${ripple ? 'ripple' : 'highlight'} paints whole row ${brightness.name} $width',
          (tester) async {
            var body = 0, checkbox = 0, menu = 0, disclosure = 0;
            final theme = ThemeData(brightness: brightness);
            Widget scene() => RepaintBoundary(
              key: const ValueKey('scene'),
              child: MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListRowSurface(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              selected: true,
                              selectedTileColor:
                                  theme.colorScheme.primaryContainer,
                              leading: Checkbox(
                                value: false,
                                onChanged: (_) => checkbox++,
                              ),
                              title: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListRowBodyInkWell(
                                    key: const ValueKey('body'),
                                    canRequestFocus: false,
                                    onTap: () => body++,
                                    splashFactory: ripple
                                        ? InkRipple.splashFactory
                                        : NoSplash.splashFactory,
                                    highlightColor: ripple
                                        ? Colors.transparent
                                        : Colors.red.withValues(alpha: .3),
                                    splashColor: Colors.red.withValues(
                                      alpha: .5,
                                    ),
                                    child: const SizedBox(
                                      height: 64,
                                      width: double.infinity,
                                      child: Center(
                                        child: Text('Synthetic body'),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    key: const ValueKey('disclosure'),
                                    onTap: () => disclosure++,
                                    child: const SizedBox(
                                      height: 24,
                                      width: double.infinity,
                                      child: Text('Checklist'),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                tooltip: 'Synthetic menu',
                                onPressed: () => menu++,
                                icon: const Icon(Icons.more_vert),
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 48,
                            width: double.infinity,
                            child: Text('Separate expanded checklist panel'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpWidget(scene());
            await tester.pumpAndSettle();
            final row = tester.getRect(find.byType(ListTile));
            final points = [
              Offset(row.left + 3, row.center.dy),
              Offset(row.right - 3, row.center.dy),
              Offset(row.left + 3, row.bottom + 4),
            ];
            final baseline = await _pixels(tester, points);
            final press = await tester.startGesture(
              tester.getCenter(find.byKey(const ValueKey('body'))),
            );
            await tester.pump();
            await tester.pump(Duration(milliseconds: ripple ? 225 : 120));
            if (ripple) {
              await press.up();
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 225));
            }
            final feedback = await _pixels(tester, points);
            expect(
              feedback[0],
              isNot(baseline[0]),
              reason: 'Body ink reaches the leading row edge.',
            );
            expect(
              feedback[1],
              isNot(baseline[1]),
              reason: 'Body ink reaches the trailing row edge.',
            );
            expect(
              feedback[2],
              baseline[2],
              reason: 'The separate panel receives no body ink.',
            );
            if (!ripple) await press.up();
            await tester.pumpAndSettle();
            expect([body, checkbox, menu, disclosure], [1, 0, 0, 0]);
            for (final control in [
              find.byType(Checkbox),
              find.byTooltip('Synthetic menu'),
              find.byKey(const ValueKey('disclosure')),
            ]) {
              final before = await _pixels(tester, points);
              final held = await tester.startGesture(tester.getCenter(control));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 120));
              expect(
                await _pixels(tester, points),
                before,
                reason: 'Independent controls keep local feedback.',
              );
              await held.up();
              await tester.pumpAndSettle();
            }
            expect([body, checkbox, menu, disclosure], [1, 1, 1, 1]);
            //Rebuild a fresh ListTile while hover is active, as a drag host does.
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: const Offset(790, 590));
            await mouse.moveTo(
              tester.getCenter(find.byKey(const ValueKey('body'))),
            );
            await tester.pumpAndSettle();
            await tester.pumpWidget(scene());
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await mouse.removePointer();
          },
        );
      }
    }
  }

  testWidgets(
    'body paint callback follows current row and tolerates removed reference',
    (tester) async {
      final bodyKey = GlobalKey();
      Widget scene(double width, {bool surface = true, double scale = 1}) {
        Widget body = Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: ListRowBodyInkWell(
            key: bodyKey,
            onTap: () {},
            child: const SizedBox(width: 100, height: 48),
          ),
        );
        if (surface) {
          body = SizedBox(
            width: width,
            child: ListRowSurface(
              child: Row(children: [const SizedBox(width: 40), body]),
            ),
          );
        }
        return MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: const Offset(13, 7),
                child: body,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(scene(320));
      await tester.pumpAndSettle();
      final widget = tester.widget<ListRowBodyInkWell>(find.byKey(bodyKey));
      final reference = tester.renderObject<RenderBox>(find.byKey(bodyKey));
      final callback = widget.getRectCallback(reference);
      expect(callback(), const Rect.fromLTWH(-40, 0, 320, 48));
      await tester.pumpWidget(scene(600));
      await tester.pumpAndSettle();
      expect(callback(), const Rect.fromLTWH(-40, 0, 600, 48));
      await tester.pumpWidget(scene(320, scale: .5));
      await tester.pumpAndSettle();
      expect(callback(), const Rect.fromLTWH(-80, 0, 640, 96));
      await tester.pumpWidget(scene(320, scale: 0));
      await tester.pumpAndSettle();
      expect(callback(), Rect.zero);
      await tester.pumpWidget(scene(320, surface: false));
      await tester.pumpAndSettle();
      expect(callback(), const Rect.fromLTWH(0, 0, 100, 48));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(callback(), Rect.zero);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<List<int>> _pixels(WidgetTester tester, List<Offset> points) async {
  final scene = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('scene')),
  );
  return (await tester.runAsync(() async {
    final image = await scene.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return [
        for (final point in points)
          data.getUint32(
            (point.dy.floor() * image.width + point.dx.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}
