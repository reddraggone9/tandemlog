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
  double scale, {
  Finder? semanticTarget,
}) async {
  final finder = find.text(text);
  final paragraph = _paragraph(tester, text);
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.textScaler.scale(16), scale * 16);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'The complete text must wrap without a line cap or ellipsis.',
  );
  final viewport = RenderAbstractViewport.of(paragraph) as RenderBox;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty);
  expect(
    paragraph.getBoxesForSelection(
      TextSelection(baseOffset: text.length - 1, extentOffset: text.length),
    ),
    isNotEmpty,
    reason: 'The final character must be laid out and painted, not ellipsized.',
  );
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
  expect(tester.getSemantics(semanticTarget ?? finder).label, contains(text));
}

Future<void> _openFieldDialog(
  WidgetTester tester,
  Brightness brightness,
  List<WorkspaceUpgradeChoice?> choices,
) async {
  const scale = 2.0;
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
}

void main() {
  setUpAll(loadSdkRoboto);
  for (final brightness in Brightness.values) {
    for (final historical in [false, true]) {
      testWidgets(
        'upgrade oversized ID field keeps selection-start caret visible '
        '${historical ? 'historical' : 'other'} ${brightness.name}',
        (tester) async {
          final choices = <WorkspaceUpgradeChoice?>[];
          await _openFieldDialog(tester, brightness, choices);
          addTearDown(tester.view.resetViewInsets);
          if (historical) {
            final expansion = find.text('Historical installation IDs');
            await Scrollable.ensureVisible(tester.element(expansion));
            await tester.pumpAndSettle();
            await tester.tap(expansion);
            await tester.pumpAndSettle();
          }
          final input = find.byKey(
            ValueKey(
              historical
                  ? 'upgrade-known-owners'
                  : 'upgrade-extra-participants',
            ),
          );
          final label = historical
              ? 'Additional historical installation IDs'
              : 'Other participating installation IDs';
          final helper = historical
              ? 'These preserve ownership; they do not add participating devices.'
              : 'Optional. Find each full ID in Settings on that device.';
          await Scrollable.ensureVisible(tester.element(input), alignment: 1);
          await tester.pumpAndSettle();
          await tester.tap(input);
          await tester.pumpAndSettle();
          const ids =
              '33333333-3333-4333-8333-333333333333\n'
              '44444444-4444-4444-8444-444444444444';
          await tester.enterText(input, ids);
          final editableFinder = find.descendant(
            of: input,
            matching: find.byType(EditableText),
          );
          final editable = tester.widget<EditableText>(editableFinder);
          editable.controller.selection = const TextSelection.collapsed(
            offset: 0,
          );
          await tester.pumpAndSettle();
          expect(editable.focusNode.hasFocus, isTrue);
          expect(editable.controller.selection.extentOffset, 0);
          tester.view.viewInsets = const FakeViewPadding(bottom: 422);
          tester.view.padding = const FakeViewPadding(top: 36);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pumpAndSettle();
          final outer =
              RenderAbstractViewport.of(_paragraph(tester, label)) as RenderBox;
          expect(
            outer.size.height * tester.view.devicePixelRatio,
            closeTo(142, .001),
          );
          expect(
            tester.getRect(input).height,
            greaterThan(outer.size.height),
            reason:
                'This field must be taller than the IME viewport so aligning its bottom cannot substitute for revealing the current caret.',
          );
          final renderEditable = tester
              .state<EditableTextState>(editableFinder)
              .renderEditable;
          // EditableText's inner viewport is RenderEditable's own paint box,
          // not another RenderAbstractViewport ancestor.
          final outerClip = _paintedRect(outer);
          final visible = outerClip.intersect(_paintedRect(renderEditable));
          final caret = MatrixUtils.transformRect(
            renderEditable.getTransformTo(null),
            renderEditable.getLocalRectForCaret(const TextPosition(offset: 0)),
          );
          // The app must reveal the complete current caret in the dialog.
          // The SDK pixel-snaps that caret against its own fractional paint
          // box; full first-glyph visibility in both clips is checked below.
          expect(
            caret.top,
            greaterThanOrEqualTo(outerClip.top),
            reason:
                'Reveal the CURRENT selection-start caret, not the bottom of an oversized ID field.',
          );
          expect(
            caret.bottom,
            lessThanOrEqualTo(outerClip.bottom),
            reason:
                'Reveal the CURRENT selection-start caret, not the bottom of an oversized ID field.',
          );
          final firstGlyph = renderEditable
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 1),
              )
              .single;
          final glyph = MatrixUtils.transformRect(
            renderEditable.getTransformTo(null),
            firstGlyph.toRect(),
          );
          expect(glyph.top, greaterThanOrEqualTo(visible.top));
          expect(glyph.bottom, lessThanOrEqualTo(visible.bottom));
          expect(editable.controller.text, ids);
          expect(editable.controller.selection.extentOffset, 0);
          expect(tester.testTextInput.isVisible, isTrue);
          await _readEveryLine(tester, helper, 2);
          expect(editable.focusNode.hasFocus, isTrue);
          expect(editable.controller.text, ids);
          expect(editable.controller.selection.extentOffset, 0);
          expect(choices, isEmpty);
          final later = find.widgetWithText(TextButton, 'Later');
          expect(later.hitTestable(), findsOneWidget);
          await tester.tap(later);
          await tester.pumpAndSettle();
          expect(choices, [null]);
          expect(find.text('Prepare').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    for (final historical in [false, true]) {
      testWidgets(
        'upgrade empty ID caret remains visible after real IME inset settles '
        '${historical ? 'historical' : 'other'} ${brightness.name}',
        (tester) async {
          final choices = <WorkspaceUpgradeChoice?>[];
          await _openFieldDialog(tester, brightness, choices);
          addTearDown(tester.view.resetViewInsets);
          if (historical) {
            final expansion = find.text('Historical installation IDs');
            await Scrollable.ensureVisible(tester.element(expansion));
            await tester.pumpAndSettle();
            await tester.tap(expansion);
            await tester.pumpAndSettle();
          }
          final input = find.byKey(
            ValueKey(
              historical
                  ? 'upgrade-known-owners'
                  : 'upgrade-extra-participants',
            ),
          );
          final label = historical
              ? 'Additional historical installation IDs'
              : 'Other participating installation IDs';
          final helper = historical
              ? 'These preserve ownership; they do not add participating devices.'
              : 'Optional. Find each full ID in Settings on that device.';
          await Scrollable.ensureVisible(tester.element(input), alignment: 1);
          await tester.pumpAndSettle();
          expect(input.hitTestable(), findsOneWidget);
          final editableFinder = find.descendant(
            of: input,
            matching: find.byType(EditableText),
          );
          final editable = tester.widget<EditableText>(editableFinder);
          expect(editable.controller.text, isEmpty);
          // A05 genuine finger hit a visible EMPTY field before the keyboard.
          await tester.tap(input);
          // A native IME can deliver its first inset after the initial focus
          // caret animation. Let focus settle so that animation cannot mask
          // a missing reveal after the later dialog viewport shrink.
          await tester.pumpAndSettle();
          expect(editable.focusNode.hasFocus, isTrue);
          expect(tester.testTextInput.isVisible, isTrue);
          // Actual screen960px; IME starts538px, including72px navigation.
          // Dialog's default100ms inset animation must fully settle BEFORE any
          // text entry or additional scrolling/ensureVisible can mask the bug.
          tester.view.viewInsets = const FakeViewPadding(bottom: 422);
          tester.view.padding = const FakeViewPadding(top: 36);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pumpAndSettle();
          final paragraph = _paragraph(tester, label);
          final viewport = RenderAbstractViewport.of(paragraph) as RenderBox;
          expect(
            viewport.size.height * tester.view.devicePixelRatio,
            closeTo(142, .001),
            reason: 'Match the actual A05 142px IME scroll viewport.',
          );
          expect(editable.controller.text, isEmpty);
          expect(editable.focusNode.hasFocus, isTrue);
          final renderEditable = tester
              .state<EditableTextState>(editableFinder)
              .renderEditable;
          final caret = MatrixUtils.transformRect(
            renderEditable.getTransformTo(null),
            renderEditable.getLocalRectForCaret(const TextPosition(offset: 0)),
          );
          final visible = _paintedRect(viewport);
          expect(
            caret.top,
            greaterThanOrEqualTo(visible.top),
            reason:
                'The initially focused empty caret must be visible without typing.',
          );
          expect(
            caret.bottom,
            lessThanOrEqualTo(visible.bottom),
            reason:
                'The initially focused empty caret must be visible without typing.',
          );
          final line = _paintedRect(renderEditable);
          expect(line.top, greaterThanOrEqualTo(visible.top));
          expect(line.bottom, lessThanOrEqualTo(visible.bottom));
          expect(caret.left, greaterThanOrEqualTo(visible.left));
          expect(caret.right, lessThanOrEqualTo(visible.right));
          final later = find.widgetWithText(TextButton, 'Later');
          expect(later.hitTestable(), findsOneWidget);
          // Reading helper lines after focus must not trigger repeated caret
          // snapping: only viewport geometry/focus changes request a reveal.
          await _readEveryLine(tester, helper, 2);
          expect(editable.focusNode.hasFocus, isTrue);
          expect(editable.controller.text, isEmpty);
          expect(tester.testTextInput.isVisible, isTrue);
          expect(choices, isEmpty);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('begin-workspace-upgrade')),
                )
                .onPressed,
            isNull,
          );
          expect(later.hitTestable(), findsOneWidget);
          await tester.tap(later);
          await tester.pumpAndSettle();
          expect(choices, [null]);
          expect(find.text('Prepare').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    for (final field in [
      (
        key: 'upgrade-extra-participants',
        label: 'Other participating installation IDs',
        helper: 'Optional. Find each full ID in Settings on that device.',
        expanded: false,
      ),
      (
        key: 'upgrade-known-owners',
        label: 'Additional historical installation IDs',
        helper:
            'These preserve ownership; they do not add participating devices.',
        expanded: true,
      ),
    ]) {
      for (final checkLabel in [true, false]) {
        testWidgets(
          'upgrade installation ID ${checkLabel ? 'label' : 'helper'} '
          '${field.key} paints all text at 320x640 font2 ${brightness.name}',
          (tester) async {
            final choices = <WorkspaceUpgradeChoice?>[];
            await _openFieldDialog(tester, brightness, choices);
            if (field.expanded) {
              final expansion = find.text('Historical installation IDs');
              await Scrollable.ensureVisible(tester.element(expansion));
              await tester.pumpAndSettle();
              await tester.tap(expansion);
              await tester.pumpAndSettle();
            }
            final input = find.byKey(ValueKey(field.key));
            final text = checkLabel ? field.label : field.helper;
            await _readEveryLine(
              tester,
              text,
              2,
              semanticTarget: checkLabel ? input : null,
            );
            final label = _paragraph(tester, field.label);
            final help = _paragraph(tester, field.helper);
            expect(
              _paintedRect(label).bottom,
              lessThanOrEqualTo(tester.getRect(input).top),
            );
            expect(
              tester.getRect(input).bottom,
              lessThanOrEqualTo(_paintedRect(help).top),
            );
            expect(tester.getSemantics(input).label, contains(field.label));
            await tester.showKeyboard(input);
            await tester.enterText(
              input,
              '33333333-3333-4333-8333-333333333333',
            );
            await tester.pumpAndSettle();
            await _readEveryLine(
              tester,
              text,
              2,
              semanticTarget: checkLabel ? input : null,
            );
            expect(
              _paintedRect(label).bottom,
              lessThanOrEqualTo(tester.getRect(input).top),
            );
            expect(
              tester.getRect(input).bottom,
              lessThanOrEqualTo(_paintedRect(help).top),
            );
            expect(tester.getSemantics(input).label, contains(field.label));
            final editable = tester.widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            );
            expect(editable.focusNode.hasFocus, isTrue);
            expect(
              editable.controller.text,
              '33333333-3333-4333-8333-333333333333',
            );
            expect(
              choices,
              isEmpty,
              reason: 'Reading or editing IDs cannot consent to an upgrade.',
            );
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('begin-workspace-upgrade')),
                  )
                  .onPressed,
              isNull,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

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
