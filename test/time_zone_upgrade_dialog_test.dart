import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/time_zone_upgrade_dialog.dart';

import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

const _intro = 'Enable these additional time zones for this shared workspace:';
const _zones = 'CST6CDT\nEST5EDT\nMST7MDT\nPST8PDT';
const _minimum =
    'Use Tandemlog 2026.10.7-rc.3 (build 98) or later on every device. '
    'Update Tandemlog on every device before continuing.';
const _older = 'Older apps will stop opening this workspace.';
const _irreversible = 'This workspace upgrade cannot be undone.';

class _DraftPage extends StatefulWidget {
  const _DraftPage(this.answers);
  final List<bool> answers;
  @override
  State<_DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<_DraftPage> {
  final controller = TextEditingController(text: 'Keep my dirty editor draft');
  final focus = FocusNode();
  Future<void> open() async {
    final result = await confirmAdditionalTimeZones(context);
    widget.answers.add(result);
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Owned editor')),
    body: Column(
      children: [
        TextField(
          key: const ValueKey('owned-draft'),
          controller: controller,
          focusNode: focus,
          autofocus: true,
        ),
        TextButton(
          onPressed: () => unawaited(open()),
          child: const Text('Additional time zones'),
        ),
      ],
    ),
  );
}

Future<_DraftPageState> _start(
  WidgetTester tester,
  List<bool> answers, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        platform: TargetPlatform.android,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff267461),
          brightness: brightness,
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => _DraftPage(answers)),
            ),
            child: const Text('Home'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Home'));
  await tester.pumpAndSettle();
  final draft = tester.state<_DraftPageState>(find.byType(_DraftPage));
  draft.controller.selection = const TextSelection(
    baseOffset: 5,
    extentOffset: 13,
  );
  expect(draft.focus.hasFocus, isTrue);
  return draft;
}

Rect _rect(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

Future<void> _readEveryLine(WidgetTester tester, String text) async {
  final finder = find.text(text);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.textScaler.scale(16), 32);
  expect(paragraph.didExceedMaxLines, isFalse);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty);
  expect(
    paragraph.getBoxesForSelection(
      TextSelection(baseOffset: text.length - 1, extentOffset: text.length),
    ),
    isNotEmpty,
  );
  final viewport = RenderAbstractViewport.of(paragraph) as RenderBox;
  expect(
    viewport.size.height,
    greaterThanOrEqualTo(boxes.map((b) => b.bottom - b.top).reduce(math.max)),
    reason: 'A full scaled warning line must fit above the actions and IME.',
  );
  final scroll = tester
      .state<ScrollableState>(
        find.ancestor(of: finder, matching: find.byType(Scrollable)).first,
      )
      .position;
  for (final box in boxes) {
    final global = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
    scroll.jumpTo(
      (scroll.pixels + global.center.dy - _rect(viewport).center.dy).clamp(
        scroll.minScrollExtent,
        scroll.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
    final shown = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
    expect(shown.top, greaterThanOrEqualTo(_rect(viewport).top));
    expect(shown.bottom, lessThanOrEqualTo(_rect(viewport).bottom));
  }
  expect(tester.getSemantics(finder).label, contains(text));
}

void main() {
  setUpAll(loadSdkRoboto);
  for (final brightness in Brightness.values) {
    for (final keyboard in [false, true]) {
      testWidgets(
        'additional zone consent readable at 320x640 font2 ${brightness.name} IME=$keyboard',
        (tester) async {
          tester.view.devicePixelRatio = 1.5;
          tester.view.physicalSize = const Size(480, 960);
          tester.view.viewPadding = const FakeViewPadding(top: 36, bottom: 72);
          tester.view.padding = const FakeViewPadding(top: 36, bottom: 72);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(() {
            tester.view.resetDevicePixelRatio();
            tester.view.resetPhysicalSize();
            tester.view.resetViewPadding();
            tester.view.resetPadding();
            tester.view.resetViewInsets();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });
          final answers = <bool>[];
          final draft = await _start(tester, answers, brightness: brightness);
          final controller = draft.controller, focus = draft.focus;
          final selection = controller.selection;
          if (keyboard) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 422);
            tester.view.padding = const FakeViewPadding(top: 36);
            await tester.pumpAndSettle();
          }
          for (final enable in [false, true]) {
            unawaited(draft.open());
            await tester.pumpAndSettle();
            final later = find.widgetWithText(TextButton, 'Later');
            final accept = find.widgetWithText(FilledButton, 'Enable');
            expect(tester.widget<TextButton>(later).autofocus, isTrue);
            if (!enable) {
              for (final text in [
                'Enable additional time zones?',
                _intro,
                _zones,
                _minimum,
                _older,
                _irreversible,
              ]) {
                await _readEveryLine(tester, text);
              }
            }
            for (final action in [later, accept]) {
              expect(action.hitTestable(), findsOneWidget);
              final rect = tester.getRect(action);
              expect(rect.height, greaterThanOrEqualTo(48));
              expect(rect.top, greaterThanOrEqualTo(24));
              expect(
                rect.bottom,
                lessThanOrEqualTo(keyboard ? 640 - 422 / 1.5 : 592),
              );
            }
            expect(find.bySemanticsLabel('Later'), findsOneWidget);
            expect(find.bySemanticsLabel('Enable'), findsOneWidget);
            final lateLater = tester.widget<TextButton>(later).onPressed!;
            final lateEnable = tester.widget<FilledButton>(accept).onPressed!;
            if (enable) {
              await tester.tap(accept);
            } else {
              await tester.tap(later);
            }
            lateLater();
            lateEnable();
            await tester.pumpAndSettle();
            expect(answers, enable ? [false, true] : [false]);
            expect(find.byType(_DraftPage), findsOneWidget);
            expect(find.text('Home'), findsNothing);
            expect(identical(draft.controller, controller), isTrue);
            expect(identical(draft.focus, focus), isTrue);
            expect(controller.text, 'Keep my dirty editor draft');
            expect(controller.selection, selection);
            expect(focus.hasFocus, isTrue);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final dismiss in ['back', 'barrier']) {
    testWidgets(
      'additional zone $dismiss cancellation and stale answer are inert',
      (tester) async {
        final answers = <bool>[];
        final draft = await _start(tester, answers);
        final selection = draft.controller.selection;
        unawaited(draft.open());
        await tester.pumpAndSettle();
        final stale = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Enable'))
            .onPressed!;
        if (dismiss == 'back') {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tapAt(const Offset(2, 2));
        }
        await tester.pumpAndSettle();
        stale();
        await tester.pumpAndSettle();
        expect(answers, [false]);
        expect(find.byType(_DraftPage), findsOneWidget);
        expect(find.text('Home'), findsNothing);
        expect(draft.controller.text, 'Keep my dirty editor draft');
        expect(draft.controller.selection, selection);
        expect(draft.focus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
