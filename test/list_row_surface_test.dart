import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/list_row_surface.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'selected row paints hover and press without stealing child controls ${brightness.name}',
      (tester) async {
        var body = 0, checkbox = 0, menu = 0;
        final theme = ThemeData(brightness: brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('scene'),
                child: Column(
                  children: [
                    ListRowSurface(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        selected: true,
                        selectedTileColor: theme.colorScheme.primaryContainer,
                        leading: Checkbox(
                          value: false,
                          onChanged: (_) => checkbox++,
                        ),
                        title: InkWell(
                          key: const ValueKey('body'),
                          canRequestFocus: false,
                          overlayColor: listRowInkOverlay(theme.colorScheme),
                          splashFactory: InkRipple.splashFactory,
                          onTap: () => body++,
                          child: const SizedBox(
                            height: 64,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Synthetic row'),
                            ),
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Synthetic menu',
                          onPressed: () => menu++,
                          icon: const Icon(Icons.more_vert),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final point = tester.getCenter(find.byKey(const ValueKey('body')));
        Future<int> pixel() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('scene')),
          );
          return (await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final i = (point.dy.floor() * image.width + point.dx.floor()) * 4;
              return bytes.getUint32(i);
            } finally {
              image.dispose();
            }
          }))!;
        }

        final baseline = await pixel();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(790, 590));
        await mouse.moveTo(point);
        await tester.pumpAndSettle();
        final hover = await pixel();
        expect(
          hover,
          isNot(baseline),
          reason: 'Hover must remain visible above painted selected tile ink.',
        );
        await mouse.down(point);
        // Start the ticker, then advance a rendered press frame.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          await pixel(),
          isNot(hover),
          reason:
              'Held press/ripple must be visible rather than hidden by a row surface.',
        );
        await mouse.up();
        await tester.pumpAndSettle();
        expect([body, checkbox, menu], [1, 0, 0]);
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        expect([body, checkbox, menu], [1, 1, 0]);
        await tester.tap(find.byTooltip('Synthetic menu'));
        await tester.pumpAndSettle();
        expect([body, checkbox, menu], [1, 1, 1]);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final brightness in Brightness.values) {
    testWidgets('popup item retains hover ${brightness.name}', (tester) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('popup-scene'),
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: ListRowSurface(
                child: PopupMenuButton<String>(
                  tooltip: 'Open synthetic popup',
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'action',
                      child: Text('Synthetic menu action'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Open synthetic popup'));
      await tester.pumpAndSettle();
      final item = find.byType(PopupMenuItem<String>);
      final rect = tester.getRect(item);
      final point = Offset(rect.left + 4, rect.center.dy);
      Future<int> pixel() async {
        final scene = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('popup-scene')),
        );
        return (await tester.runAsync(() async {
          final image = await scene.toImage(pixelRatio: 1);
          try {
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            return data.getUint32(
              (point.dy.floor() * image.width + point.dx.floor()) * 4,
            );
          } finally {
            image.dispose();
          }
        }))!;
      }

      final before = await pixel();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(790, 590));
      await mouse.moveTo(point);
      await tester.pumpAndSettle();
      expect(
        await pixel(),
        isNot(before),
        reason:
            'Row styling must not suppress popup-item hover through captured themes.',
      );
      await mouse.removePointer();
    });
  }
}
