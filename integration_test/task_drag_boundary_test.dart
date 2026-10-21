import 'profile_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';
import 'native_text_fixtures.dart';
import '../test/support/toolbar_button.dart';
import 'task_flow_test.dart' show waitForUi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTaskDragBoundaryTests();
}

void registerTaskDragBoundaryTests() {
  _registerDragBoundaryEdgeTests();
  for (final sample in [(false, 1.0), (false, 2.0), (true, 1.0)]) {
    final hidden = sample.$1, scale = sample.$2;
    testWidgets(
      'drag insertion boundary hidden:$hidden scale:$scale preserves actual destination',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'drag-boundary-synthetic-',
        );
        final data = await Directory('${root.path}/data').create();
        final profile = await Directory('${root.path}/profile').create();
        final user = const Uuid().v4();
        final ids = List.generate(4, (_) => const Uuid().v4());
        final hiddenId = const Uuid().v4();
        final initial = [ids[0], if (hidden) hiddenId, ...ids.skip(1)];
        final writer = await openNativeFixtureStore(
          LocalLogFolder(data.path),
          '${root.path}/seed',
        );
        try {
          await writer.command(user, 'user.created', {
            'name': 'Synthetic row household',
          });
          for (var i = 0; i < ids.length; i++) {
            await writer.createNativeFixtureTask(ids[i], {
              'title': [
                'Synthetic tall wrapped title for a varied row boundary',
                'Row B',
                'Row C',
                'Row S',
              ][i],
              'description': '',
              'assignee': user,
              'tags': ['qa'],
            });
          }
          if (hidden) {
            final otherUser = const Uuid().v4();
            await writer.command(otherUser, 'user.created', {
              'name': 'Synthetic other user',
            });
            await writer.createNativeFixtureTask(hiddenId, {
              'title': 'Synthetic hidden anchor',
              'description': '',
              'assignee': otherUser,
            });
          }
          for (final id in initial) {
            await writer.moveBefore(id, null);
          }
          await seedNativeProfile(profile.path, {
            'folder': data.path,
            'user': user,
            'appearance': 'dark',
          });
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 1000);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('drag-scene'),
              child: TandemlogApp(profilePath: profile.path),
            ),
          );
          await waitForUi(
            tester,
            () => find
                .byKey(ValueKey('task-row-${ids.last}'))
                .evaluate()
                .isNotEmpty,
          );
          await tester.pumpAndSettle();
          Finder row(String id) => find.byKey(ValueKey('task-drop-$id'));
          Future<List<String>> order() async {
            await writer.refresh();
            return writer.rows
                .where((r) => r['kind'] == 'task')
                .map((r) => r['id'] as String)
                .toList();
          }

          expect(await order(), initial);
          expect(
            tester.getSize(row(ids[0])).height,
            greaterThan(tester.getSize(row(ids[1])).height),
          );
          final lines = <double>[];
          final orders = <List<String>>[];
          for (final afterUpper in [true, false]) {
            final handle = find.descendant(
              of: row(ids.last),
              matching: find.byType(Draggable<String>),
            );
            final target = tester.getRect(row(ids[afterUpper ? 0 : 1]));
            final screen =
                Offset.zero &
                (tester.view.physicalSize / tester.view.devicePixelRatio);
            expect(
              screen.contains(tester.getCenter(handle)),
              isTrue,
              reason: 'The drag begins at a visible native handle.',
            );
            expect(
              screen.contains(
                Offset(
                  target.right - 8,
                  afterUpper ? target.bottom - 4 : target.top + 4,
                ),
              ),
              isTrue,
            );
            final gesture = await tester.startGesture(tester.getCenter(handle));
            await gesture.moveBy(const Offset(-24, 0));
            await tester.pump();
            await gesture.moveTo(
              Offset(
                target.right - 8,
                afterUpper ? target.bottom - 4 : target.top + 4,
              ),
            );
            await tester.pump(const Duration(milliseconds: 32));
            final primary = Theme.of(
              tester.element(row(ids[0])),
            ).colorScheme.primary;
            final viewport = tester.getRect(row(ids[0]));
            final firstY = viewport.top.floor();
            final lastY = tester.getRect(row(ids.last)).bottom.ceil();
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('drag-scene')),
            );
            final lineY = await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              try {
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                final argb = primary.toARGB32();
                final red = (argb >> 16) & 255,
                    green = (argb >> 8) & 255,
                    blue = argb & 255;
                final ys = <int>[];
                final left = viewport.left.ceil() + 4,
                    right = viewport.right.floor() - 12;
                for (
                  var y = firstY.clamp(0, image.height);
                  y < lastY.clamp(0, image.height);
                  y++
                ) {
                  var matching = 0;
                  for (var x = left; x < right; x++) {
                    final i = (y * image.width + x) * 4;
                    if (bytes.getUint8(i) == red &&
                        bytes.getUint8(i + 1) == green &&
                        bytes.getUint8(i + 2) == blue) {
                      matching++;
                    }
                  }
                  if (matching >= (right - left) * .9) ys.add(y);
                }
                expect(
                  ys,
                  isNotEmpty,
                  reason:
                      'A visible full-width insertion line must be painted.',
                );
                expect(
                  ys.last - ys.first,
                  lessThanOrEqualTo(2),
                  reason: 'Paint exactly one thin boundary.',
                );
                return ys.reduce((a, b) => a + b) / ys.length;
              } finally {
                image.dispose();
              }
            });
            lines.add(lineY!);
            await captureNativeFixtureUi(
              tester,
              'drag-gap-hidden-$hidden-scale-$scale-${afterUpper ? 'upper' : 'lower'}',
            );
            await gesture.up();
            await tester.pumpAndSettle();
            await waitForUi(
              tester,
              () =>
                  tester.getTopLeft(row(ids.last)).dy <
                  tester.getTopLeft(row(ids[1])).dy,
            );
            final current = await order();
            orders.add(current);
            expect(
              current,
              hidden
                  ? [ids[0], hiddenId, ids[3], ids[1], ids[2]]
                  : [ids[0], ids[3], ids[1], ids[2]],
            );
            await tester.tap(find.byKey(const ValueKey('undo-task-action')));
            await tester.pumpAndSettle();
            await waitForUi(
              tester,
              () =>
                  tester.getTopLeft(row(ids.last)).dy >
                  tester.getTopLeft(row(ids[2])).dy,
            );
            expect(await order(), initial);
          }
          debugPrint(
            'DRAG_BOUNDARY_REPRO=${jsonEncode({'lineY': lines, 'equivalentOrders': orders[0].toString() == orders[1].toString(), 'upperOrder': orders[0], 'lowerOrder': orders[1]})}',
          );
          if (hidden) {
            expect(
              orders[0],
              orders[1],
              reason: 'Both halves resolve before the same later visible task.',
            );
            expect(
              lines[0],
              closeTo(lines[1], 0.01),
              reason:
                  'One visible gap paints one boundary and saves one destination.',
            );
          } else {
            expect(orders[0], orders[1]);
            expect(
              lines[0],
              closeTo(lines[1], 0.01),
              reason:
                  'Equivalent actual destinations paint the same stable boundary.',
            );
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await writer.close();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await root.delete(recursive: true);
        }
      },
    );
  }
}

/// Scan rendered pixels rather than inspecting the painter's implementation.
Future<List<int>> _visibleInsertionPixels(
  WidgetTester tester,
  Color color,
) async {
  final scene = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('edge-scene')),
  );
  return (await tester.runAsync(() async {
    final image = await scene.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final argb = color.toARGB32();
      final ys = <int>[];
      for (var y = 0; y < image.height; y++) {
        var count = 0;
        for (var x = 20; x < image.width - 24; x++) {
          final offset = (y * image.width + x) * 4;
          if (data.getUint8(offset) == ((argb >> 16) & 255) &&
              data.getUint8(offset + 1) == ((argb >> 8) & 255) &&
              data.getUint8(offset + 2) == (argb & 255)) {
            count++;
          }
        }
        if (count >= (image.width - 44) * .9) ys.add(y);
      }
      return ys;
    } finally {
      image.dispose();
    }
  }))!;
}

void _registerDragBoundaryEdgeTests() {
  for (final cached in [false, true]) {
    testWidgets(
      'drag insertion boundary ${cached ? 'cached offscreen anchor' : 'group boundary rejects foreign bucket'}',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'drag-edge-synthetic-',
        );
        final data = await Directory('${root.path}/data').create();
        final profile = await Directory('${root.path}/profile').create();
        final user = const Uuid().v4(),
            upper = const Uuid().v4(),
            lower = const Uuid().v4(),
            source = const Uuid().v4();
        // Source starts before upper so this is a real visible move. With
        // [upper, foreign lower, source], dropping after upper is now a no-op.
        final initial = [source, upper, lower];
        final peer = await openNativeFixtureStore(
          LocalLogFolder(data.path),
          '${root.path}/peer',
        );
        try {
          await peer.command(user, 'user.created', {
            'name': 'Synthetic boundary household',
          });
          for (final id in [upper, lower, source]) {
            await peer.createNativeFixtureTask(id, {
              'title': id == upper
                  ? 'Synthetic wrapped upper row with a varied height'
                  : id == source
                  ? 'Row S'
                  : 'Row B',
              'description': '',
              'assignee': user,
              if (!cached && id == lower) 'schedule': {'dueDate': '2026-10-01'},
            });
          }
          if (cached) {
            for (var i = 0; i < 6; i++) {
              await peer.addChecklistItem(upper, 'Synthetic checklist $i');
            }
          }
          for (final id in initial) {
            await peer.moveBefore(id, null);
          }
          await seedNativeProfile(profile.path, {
            'folder': data.path,
            'user': user,
            'appearance': 'dark',
          });
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 850);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('edge-scene'),
              child: TandemlogApp(profilePath: profile.path),
            ),
          );
          Finder row(String id) =>
              find.byKey(ValueKey('task-drop-$id'), skipOffstage: false);
          await waitForUi(tester, () => row(source).evaluate().isNotEmpty);
          await tester.pumpAndSettle();
          if (cached) {
            await tester.tap(
              find.byKey(ValueKey('checklist-disclosure-$upper')),
            );
            await waitForUi(
              tester,
              () => find
                  .byKey(ValueKey('inline-checklist-$upper'))
                  .evaluate()
                  .isNotEmpty,
            );
            await tester.pumpAndSettle();
            // Place the materialized next row just40px below the viewport:
            // attached within the real cache extent, with target/handle visible.
            final height = tester.getTopLeft(row(lower)).dy - 40;
            expect(height, inInclusiveRange(400, 1000));
            tester.view.physicalSize = Size(390, height);
            await tester.pumpAndSettle();
            final box = tester.renderObject<RenderBox>(row(lower));
            expect(
              box.attached && box.hasSize,
              isTrue,
              reason: 'Exercise an attached cached row, not a missing anchor.',
            );
            expect(
              tester.getTopLeft(row(lower)).dy,
              greaterThan(tester.view.physicalSize.height),
            );
          }
          final target = tester.getRect(row(upper));
          final handle = find.descendant(
            of: row(source),
            matching: find.byType(Draggable<String>),
          );
          final viewport = Offset.zero & tester.view.physicalSize;
          expect(viewport.contains(tester.getCenter(handle)), isTrue);
          final destination = Offset(target.right - 8, target.bottom - 4);
          expect(viewport.contains(destination), isTrue);
          final color = Theme.of(
            tester.element(row(upper)),
          ).colorScheme.primary;
          Future<TestGesture> start(Offset destination) async {
            await waitForUi(
              tester,
              () =>
                  tester
                      .widget<Draggable<String>>(handle)
                      .maxSimultaneousDrags !=
                  0,
            );
            final gesture = await tester.startGesture(tester.getCenter(handle));
            await gesture.moveBy(const Offset(-24, 0));
            await tester.pump();
            await gesture.moveTo(destination);
            await tester.pump(const Duration(milliseconds: 32));
            expect(
              find.text('Row S'),
              findsNWidgets(2),
              reason: 'The native handle must start a real active drag.',
            );
            return gesture;
          }

          final gesture = await start(destination);
          if (cached) {
            final box = tester.renderObject<RenderBox>(row(lower));
            expect(box.attached && box.hasSize, isTrue);
            expect(
              tester.getTopLeft(row(lower)).dy,
              greaterThan(tester.view.physicalSize.height),
              reason:
                  'The next anchor remains cached offscreen during the actual drag frame.',
            );
          }
          final line = await _visibleInsertionPixels(tester, color);
          expect(
            line,
            isNotEmpty,
            reason: 'A valid visible target keeps a visible insertion line.',
          );
          expect(line.last - line.first, lessThanOrEqualTo(2));
          expect(
            line.first.toDouble(),
            closeTo(target.bottom - 2, 1),
            reason:
                'Neither a foreign group nor an offscreen cached anchor can own this visible line.',
          );
          await captureNativeFixtureUi(
            tester,
            'drag-edge-${cached ? 'cached' : 'group'}',
          );
          if (!cached) {
            await gesture.moveTo(
              tester.getCenter(find.text('Thursday · 2026-10-01')),
            );
            await tester.pump(const Duration(milliseconds: 32));
            expect(
              await _visibleInsertionPixels(tester, color),
              isEmpty,
              reason: 'A group heading is not an insertion destination.',
            );
            await gesture.moveTo(destination);
            await tester.pump(const Duration(milliseconds: 32));
            expect(await _visibleInsertionPixels(tester, color), line);
          }
          await gesture.up();
          await tester.pumpAndSettle();
          await waitForUi(
            tester,
            () =>
                toolbarButton(
                  tester,
                  find.byKey(const ValueKey('undo-task-action')),
                ).onPressed !=
                null,
          );
          await peer.refresh();
          expect(
            peer.rows
                .where((r) => r['kind'] == 'task')
                .map((r) => r['id'])
                .toList(),
            [upper, source, lower],
          );
          expect(
            await _visibleInsertionPixels(tester, color),
            isEmpty,
            reason: 'Release clears the insertion line.',
          );
          await tester.tap(find.byKey(const ValueKey('undo-task-action')));
          await tester.pumpAndSettle();
          await waitForUi(
            tester,
            () =>
                toolbarButton(
                  tester,
                  find.byKey(const ValueKey('undo-task-action')),
                ).onPressed ==
                null,
          );
          await peer.refresh();
          expect(
            peer.rows
                .where((r) => r['kind'] == 'task')
                .map((r) => r['id'])
                .toList(),
            initial,
          );
          if (!cached) {
            // Dismiss the existing10-second Undo notice before checking the next notice.
            await tester.drag(find.byType(SnackBar), const Offset(0, 150));
            await tester.pumpAndSettle();
            expect(find.textContaining('Undid moving'), findsNothing);
            final before = {
              await for (final file in data.list())
                if (file is File)
                  file.path: base64Encode(await file.readAsBytes()),
            };
            final invalid = await start(
              tester.getTopRight(row(lower)) + const Offset(-8, 4),
            );
            expect(
              await _visibleInsertionPixels(tester, color),
              isEmpty,
              reason: 'A different order bucket cannot advertise insertion.',
            );
            await invalid.up();
            await tester.pumpAndSettle();
            await captureNativeFixtureUi(tester, 'invalid-drop-rejected');
            expect(find.textContaining('Reorder canceled.'), findsOneWidget);
            expect({
              await for (final file in data.list())
                if (file is File)
                  file.path: base64Encode(await file.readAsBytes()),
            }, before);
          } else {
            final canceled = await start(destination);
            await canceled.cancel();
            await tester.pumpAndSettle();
            expect(
              await _visibleInsertionPixels(tester, color),
              isEmpty,
              reason: 'Pointer cancellation clears cached feedback.',
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await peer.close();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
