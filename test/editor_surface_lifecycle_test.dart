import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/editor_surface.dart';

class _Lifetime {
  int initialized = 0, disposed = 0, activated = 0, deactivated = 0;
}

class _Probe extends StatefulWidget {
  const _Probe(this.life, {super.key});
  final _Lifetime life;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final input = TextEditingController(text: 'kept search');
  @override
  void initState() {
    super.initState();
    widget.life.initialized++;
  }

  @override
  void activate() {
    super.activate();
    widget.life.activated++;
  }

  @override
  void deactivate() {
    widget.life.deactivated++;
    super.deactivate();
  }

  @override
  void dispose() {
    widget.life.disposed++;
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: input);
}

void main() {
  testWidgets(
    'resize keeps editor focus, composition and background viewport',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final side = ValueNotifier(true);
      addTearDown(side.dispose);
      final listLife = _Lifetime(), editorLife = _Lifetime();
      final listKey = GlobalKey<_ProbeState>(),
          editorKey = GlobalKey<_ProbeState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: side,
              builder: (context, panel, _) => EditorSurface(
                panel: panel,
                list: _Probe(listLife, key: listKey),
                editor: SizedBox(
                  width: 420,
                  height: 500,
                  child: _Probe(editorLife, key: editorKey),
                ),
              ),
            ),
          ),
        ),
      );
      final listState = listKey.currentState;
      final editorState = editorKey.currentState!;
      final edit = find.descendant(
        of: find.byKey(editorKey),
        matching: find.byType(EditableText),
      );
      tester.widget<EditableText>(edit).focusNode.requestFocus();
      await tester.pumpAndSettle();
      const composed = TextEditingValue(
        text: 'composition kept',
        selection: TextSelection(baseOffset: 2, extentOffset: 8),
        composing: TextRange(start: 1, end: 9),
      );
      editorState.input.value = composed;
      await tester.pump();
      for (final panel in [false, true]) {
        side.value = panel;
        await tester.pumpAndSettle();
        expect(listKey.currentState, same(listState));
        expect(listLife.deactivated, 0);
        expect(listLife.disposed, 0);
        expect(editorKey.currentState, same(editorState));
        expect(editorState.input.value, composed);
        expect(tester.widget<EditableText>(edit).focusNode.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      }
    },
  );
  for (final panel in [true, false]) {
    testWidgets(
      'open/close keeps controls and viewport without reparenting; panel=$panel',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final controls = _Lifetime(), viewport = _Lifetime();
        final viewportKey = GlobalKey<_ProbeState>();
        final open = ValueNotifier(false);
        addTearDown(open.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: open,
                builder: (context, shown, _) => EditorSurface(
                  panel: panel,
                  editor: shown
                      ? const SizedBox(
                          width: 400,
                          height: 500,
                          child: Text('Editor'),
                        )
                      : null,
                  list: Column(
                    children: [
                      _Probe(controls),
                      Expanded(child: _Probe(viewport, key: viewportKey)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField).first, 'unsent query');
        final original = viewportKey.currentState;
        open.value = true;
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'unsent query',
        );
        expect(controls.initialized, 1);
        expect(controls.disposed, 0);
        expect(viewportKey.currentState, same(original));
        expect(viewport.deactivated, 0);
        expect(viewport.activated, 0);
        expect(
          tester.getSize(find.byType(TextField).first).width,
          panel ? 779 : 1200,
        );
        final focus = tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode;
        expect(focus.canRequestFocus, panel);
        open.value = false;
        await tester.pumpAndSettle();
        expect(controls.initialized, 1);
        expect(controls.disposed, 0);
        expect(viewport.deactivated, 0);
        expect(viewportKey.currentState, same(original));
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'unsent query',
        );
        expect(focus.canRequestFocus, isTrue);
        expect(tester.getSize(find.byType(TextField).first).width, 1200);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
