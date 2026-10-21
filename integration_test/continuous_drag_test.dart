import 'profile_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' show waitForUi, filterChoice;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerContinuousDragTests();
}

void registerContinuousDragTests() {
  for (final hiddenKind in ['none', 'assignee', 'completed', 'tag']) {
    final hidden = hiddenKind != 'none';
    testWidgets(
      'continuous same-gap drag follows short viewport scrolling and sticky heading hidden:$hiddenKind',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'continuous-drag-synthetic-',
        );
        final data = await Directory('${root.path}/data').create();
        final profile = await Directory('${root.path}/profile').create();
        final peer = await openNativeFixtureStore(
          LocalLogFolder(data.path),
          '${root.path}/peer',
        );
        final user = const Uuid().v4();
        final ids = List.generate(18, (_) => const Uuid().v4());
        final hiddenId = const Uuid().v4();
        final initial = [ids[0], ids[1], if (hidden) hiddenId, ...ids.skip(2)];
        try {
          await peer.command(user, 'user.created', {
            'name': 'Synthetic scrolling household',
          });
          final today = DateTime.now().toIso8601String().substring(0, 10);
          for (var i = 0; i < ids.length; i++) {
            await peer.createNativeFixtureTask(ids[i], {
              'title': [
                'Synthetic source',
                'Synthetic upper row',
                'Synthetic lower row',
                ...List.generate(15, (j) => 'Synthetic following row $j'),
              ][i],
              'description': '',
              'assignee': user,
              'tags': ['Visible'],
              'schedule': {'dueDate': today},
            });
          }
          if (hidden) {
            final otherUser = const Uuid().v4();
            await peer.command(otherUser, 'user.created', {
              'name': 'Synthetic hidden household member',
            });
            await peer.createNativeFixtureTask(hiddenId, {
              'title': 'Synthetic hidden anchor',
              'description': '',
              'assignee': hiddenKind == 'assignee' ? otherUser : user,
              'tags': [hiddenKind == 'tag' ? 'Other' : 'Visible'],
              'schedule': {'dueDate': today},
            });
          }
          if (hiddenKind == 'completed') {
            await peer.complete(hiddenId, completionDay: DateTime.now());
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
          //620x415 including the31px desktop decoration in the supplied report.
          tester.view.physicalSize = const Size(620, 384);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('continuous-scene'),
              child: TandemlogApp(profilePath: profile.path),
            ),
          );
          Finder row(int index) => find.byKey(
            ValueKey('task-drop-${ids[index]}'),
            skipOffstage: false,
          );
          await waitForUi(tester, () => row(2).evaluate().isNotEmpty);
          await tester.pumpAndSettle();
          if (hiddenKind == 'tag') {
            await filterChoice(tester, '#Visible');
            await tester.pumpAndSettle();
            expect(find.byKey(ValueKey('task-drop-$hiddenId')), findsNothing);
          }
          final scrollable = find
              .ancestor(of: row(1), matching: find.byType(Scrollable))
              .first;
          final scroll = tester.state<ScrollableState>(scrollable).position;
          final viewport = tester.getRect(
            find
                .ancestor(of: row(1), matching: find.byType(CustomScrollView))
                .first,
          );
          final color = Theme.of(tester.element(row(1))).colorScheme.primary;
          final measurements = <Map<String, Object?>>[];
          Future<List<String>> order() async {
            await peer.refresh();
            return peer.rows
                .where((r) => r['kind'] == 'task')
                .map((r) => r['id'] as String)
                .toList();
          }

          Future<void> measure(String phase, bool afterUpper) async {
            await tester.pump();
            final upper = tester.getRect(row(1)),
                lower = tester.getRect(row(2));
            final scene = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('continuous-scene')),
            );
            final ys = (await tester.runAsync(() async {
              final image = await scene.toImage(pixelRatio: 1);
              try {
                final pixels = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                final argb = color.toARGB32();
                //The real mouse tooltip composites above the right part of the line.
                //Measure its unobscured96px leading span; the separate boundary
                //suite still checks full-width paint in unobscured touch scenes.
                final result = <int>[];
                for (
                  var y = viewport.top.ceil();
                  y < viewport.bottom.floor();
                  y++
                ) {
                  var count = 0;
                  for (
                    var x = upper.left.ceil() + 4;
                    x < upper.left.floor() + 100;
                    x++
                  ) {
                    final offset = (y * image.width + x) * 4;
                    if (pixels.getUint8(offset) == ((argb >> 16) & 255) &&
                        pixels.getUint8(offset + 1) == ((argb >> 8) & 255) &&
                        pixels.getUint8(offset + 2) == (argb & 255)) {
                      count++;
                    }
                  }
                  if (count > 96 * .9) result.add(y);
                }
                return result;
              } finally {
                image.dispose();
              }
            }))!;
            final sample = <String, Object?>{
              'phase': phase,
              'hidden': hidden,
              'hiddenKind': hiddenKind,
              'expectedBeforeId': ids[2],
              'scroll': scroll.pixels,
              'upperTop': upper.top,
              'upperBottom': upper.bottom,
              'lowerTop': lower.top,
              'lineYs': ys,
              'sourceTop': tester.getTopLeft(row(0)).dy,
            };
            measurements.add(sample);
            debugPrint('CONTINUOUS_DRAG=${jsonEncode(sample)}');
            await _captureContinuousFrame(
              tester,
              'continuous-hidden-$hiddenKind-${phase.replaceAll(RegExp('[^a-zA-Z0-9-]'), '-')}',
            );
            expect(
              ys,
              isNotEmpty,
              reason: 'A visible valid gap keeps a painted line: $sample',
            );
            expect(ys.last - ys.first, lessThanOrEqualTo(2));
            expect(
              ys.first.toDouble(),
              closeTo(lower.top, 1),
              reason:
                  'The marker remains on the same adjacent-row boundary while scrolling: $sample',
            );
            expect(
              await order(),
              initial,
              reason: 'A held drag must not append a reorder.',
            );
          }

          for (final dropAfterUpper in [true, false]) {
            scroll.jumpTo(0);
            await tester.pumpAndSettle();
            final handle = find.descendant(
              of: row(0),
              matching: find.byType(Draggable<String>),
            );
            await waitForUi(
              tester,
              () =>
                  tester
                      .widget<Draggable<String>>(handle)
                      .maxSimultaneousDrags !=
                  0,
            );
            final gesture = await tester.startGesture(
              tester.getCenter(handle),
              kind: PointerDeviceKind.mouse,
            );
            await gesture.moveBy(const Offset(-24, 0));
            await tester.pump();
            expect(
              find.text('Synthetic source'),
              findsNWidgets(2),
              reason: 'A real handle drag has started.',
            );
            for (var step = 0; step < 8; step++) {
              //One unbroken gesture alternates between both halves of the same gap.
              if (step == 2) {
                //Enter the actual lower edge autoscroll zone without releasing.
                await gesture.moveTo(
                  Offset(viewport.right - 48, viewport.bottom - 24),
                );
                for (var tick = 0; tick < 2; tick++) {
                  await tester.pump(const Duration(milliseconds: 16));
                }
              }
              final afterUpper = step.isEven;
              final target = tester.getRect(row(afterUpper ? 1 : 2));
              await gesture.moveTo(
                Offset(
                  target.right - 48,
                  afterUpper ? target.bottom - 4 : target.top + 4,
                ),
              );
              await tester.pump(const Duration(milliseconds: 16));
              await measure(
                'dropAfterUpper:$dropAfterUpper step:$step afterUpper:$afterUpper',
                afterUpper,
              );
              if (step == 0 || step == 7) {
                await _captureContinuousFrame(
                  tester,
                  'continuous-hidden-$hiddenKind-${dropAfterUpper ? 'upper' : 'lower'}-$step',
                );
              }
            }
            expect(
              scroll.pixels,
              greaterThan(20),
              reason: 'Exercise actual autoscroll, not a fixed viewport.',
            );
            expect(
              tester.getTopLeft(row(0)).dy,
              lessThan(viewport.top + 28),
              reason: 'The source crosses under the sticky date heading.',
            );
            final last = tester.getRect(row(dropAfterUpper ? 1 : 2));
            await gesture.moveTo(
              Offset(
                last.right - 48,
                dropAfterUpper ? last.bottom - 4 : last.top + 4,
              ),
            );
            await tester.pump(const Duration(milliseconds: 16));
            await measure('releaseAfterUpper:$dropAfterUpper', dropAfterUpper);
            await gesture.up();
            await tester.pumpAndSettle();
            await waitForUi(
              tester,
              () => find
                  .byKey(const ValueKey('undo-task-action'))
                  .evaluate()
                  .isNotEmpty,
            );
            final saved = await order();
            debugPrint(
              'CONTINUOUS_SAVED=${jsonEncode({'hidden': hidden, 'hiddenKind': hiddenKind, 'afterUpper': dropAfterUpper, 'source': ids[0], 'order': saved, 'beforeId': saved[saved.indexOf(ids[0]) + 1]})}',
            );
            expect(saved, [
              ids[1],
              if (hidden) hiddenId,
              ids[0],
              ...ids.skip(2),
            ]);
            await tester.tap(find.byKey(const ValueKey('undo-task-action')));
            await tester.pumpAndSettle();
            expect(await order(), initial);
          }
          debugPrint('CONTINUOUS_DRAG_COMPLETE=${jsonEncode(measurements)}');
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

Future<void> _captureContinuousFrame(WidgetTester tester, String name) async {
  final directory = Platform.environment['TANDEMLOG_NATIVE_QA_SCREENSHOTS'];
  if (directory == null) return;
  final scene = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('continuous-scene')),
  );
  await tester.runAsync(() async {
    final image = await scene.toImage(pixelRatio: 1);
    try {
      await Directory(directory).create(recursive: true);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
