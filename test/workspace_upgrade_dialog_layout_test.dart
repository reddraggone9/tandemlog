import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/workspace_upgrade.dart';
import 'package:tandemlog/storage/workspace_upgrade.dart';

import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

const _title = 'Upgrade shared workspace';
const _intro =
    'Use one Tasks and Food history per device. Tandemlog keeps '
    'the original logs and a verified recovery snapshot. Editing '
    'pauses on participating devices until the upgrade finishes.';
const _devices =
    'Update every device that will keep editing to this version '
    'or newer. Let folder sync finish. Stop older apps and devices '
    'you will not include. An offline or unseen device cannot be '
    'verified by Tandemlog.';
const _history =
    'History below identifies past writers, not currently active '
    'devices. Select every installation that will keep writing. '
    'Leave retired installations unselected; their history stays.';
const _confirmation =
    'I checked all my devices: every device that will keep '
    'editing is included, and other or older apps are stopped.';
const _forward =
    'Once conversion is staged, resume this upgrade after an '
    'interruption. Do not reopen the upgraded workspace in an '
    'older app. This app also upgrades its local profile; stable '
    '2026.10.6 and RC.1 cannot reopen that profile.';

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );

Rect _paintedRect(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

Future<void> _readEveryLine(
  WidgetTester tester,
  String text,
  double scale,
) async {
  final finder = find.text(text);
  final paragraph = _paragraph(tester, text);
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.textScaler.scale(16), scale * 16);
  expect(paragraph.didExceedMaxLines, isFalse);
  final viewport = RenderAbstractViewport.of(paragraph) as RenderBox;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty);
  final lineHeight = boxes.map((box) => box.bottom - box.top).reduce(math.max);
  expect(
    viewport.size.height,
    greaterThanOrEqualTo(lineHeight),
    reason: 'A scroll viewport shorter than one scaled line cannot reveal it.',
  );
  final scrollable = tester.state<ScrollableState>(
    find.ancestor(of: finder, matching: find.byType(Scrollable)).first,
  );
  for (final box in boxes) {
    final clip = _paintedRect(viewport);
    final before = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
    final position = scrollable.position;
    position.jumpTo(
      (position.pixels + before.center.dy - clip.center.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
    final shown = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
    final visible = _paintedRect(viewport);
    expect(shown.top, greaterThanOrEqualTo(visible.top));
    expect(shown.bottom, lessThanOrEqualTo(visible.bottom));
  }
  expect(tester.getSemantics(finder).label, contains(text));
}

void main() {
  setUpAll(loadSdkRoboto);
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'upgrade dialog warning lines and guarded actions at API30 320x640 ${brightness.name} $scale',
        (tester) async {
          // Actual owner94 Android capture:480x960px/dpi240,24dp status,
          // 48dp navigation and full system font2. Keep these logical metrics.
          tester.view.devicePixelRatio = 1.5;
          tester.view.physicalSize = const Size(480, 960);
          tester.view.viewPadding = const FakeViewPadding(top: 36, bottom: 72);
          tester.view.padding = const FakeViewPadding(top: 36, bottom: 72);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(() {
            tester.view.resetDevicePixelRatio();
            tester.view.resetPhysicalSize();
            tester.view.resetViewPadding();
            tester.view.resetPadding();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });
          const writer = '11111111-1111-4111-8111-111111111111';
          const peer = '22222222-2222-4222-8222-222222222222';
          final inventory = WorkspaceUpgradeInventory(
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            {writer, peer},
            [],
            [],
          );
          final choices = <WorkspaceUpgradeChoice?>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                platform: TargetPlatform.android,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff267461),
                  brightness: brightness,
                ),
                inputDecorationTheme: const InputDecorationTheme(
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      choices.add(
                        await showDialog<WorkspaceUpgradeChoice>(
                          context: context,
                          builder: (_) => WorkspaceUpgradeDialog(
                            writer: writer,
                            inventory: inventory,
                            inspect: (_) async => inventory,
                          ),
                        ),
                      );
                    },
                    child: const Text('Prepare'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Prepare'));
          await tester.pumpAndSettle();
          final title = _paragraph(tester, _title);
          expect(title.textScaler.scale(16), scale * 16);
          final titleBefore = _paintedRect(title);
          final begin = find.byKey(const ValueKey('begin-workspace-upgrade'));
          expect(tester.widget<FilledButton>(begin).onPressed, isNull);
          for (final text in [
            _intro,
            _devices,
            _history,
            _confirmation,
            _forward,
          ]) {
            await _readEveryLine(tester, text, scale);
          }
          if (scale == 2) {
            final viewport =
                RenderAbstractViewport.of(_paragraph(tester, _forward))
                    as RenderBox;
            expect(
              _paintedRect(title).bottom,
              lessThanOrEqualTo(_paintedRect(viewport).top),
              reason: 'The large title must scroll away with the warnings.',
            );
            expect(_paintedRect(title).top, lessThan(titleBefore.top));
          }

          Future<void> confirm() async {
            final confirmation = find.byKey(
              const ValueKey('upgrade-coordination-confirmation'),
            );
            final checkbox = find.descendant(
              of: confirmation,
              matching: find.byType(Checkbox),
            );
            await Scrollable.ensureVisible(
              tester.element(checkbox),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            expect(checkbox.hitTestable(), findsOneWidget);
            await tester.tap(checkbox);
            await tester.pumpAndSettle();
            expect(tester.widget<FilledButton>(begin).onPressed, isNotNull);
          }

          void expectActionsReachable() {
            for (final button in [
              find.widgetWithText(TextButton, 'Later'),
              begin,
            ]) {
              expect(button.hitTestable(), findsOneWidget);
              final rect = tester.getRect(button);
              expect(rect.top, greaterThanOrEqualTo(24));
              expect(rect.bottom, lessThanOrEqualTo(592));
              expect(rect.height, greaterThanOrEqualTo(48));
            }
          }

          await confirm();
          expectActionsReachable();
          final later = find.widgetWithText(TextButton, 'Later');
          final lateLater = tester.widget<TextButton>(later).onPressed!;
          await tester.tap(later);
          lateLater(); // An already-queued answer must not pop the page.
          await tester.pumpAndSettle();
          expect(choices, [null]);
          expect(find.text('Prepare').hitTestable(), findsOneWidget);

          await tester.tap(find.text('Prepare'));
          await tester.pumpAndSettle();
          await confirm();
          expectActionsReachable();
          final lateBegin = tester.widget<FilledButton>(begin).onPressed!;
          await tester.tap(begin);
          lateBegin();
          await tester.pumpAndSettle();
          expect(choices.length, 2);
          expect(choices.last?.participants, {writer});
          expect(choices.last?.knownOwners, isEmpty);
          expect(find.byType(WorkspaceUpgradeDialog), findsNothing);
          expect(find.text('Prepare').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
