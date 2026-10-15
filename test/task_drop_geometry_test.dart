import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_drop_indicator.dart';

class _LookupPainter extends CustomPainter {
  _LookupPainter({required this.lookup, required Listenable repaint})
    : super(repaint: repaint);
  final VoidCallback lookup;

  @override
  void paint(Canvas canvas, Size size) => lookup();

  @override
  bool shouldRepaint(_LookupPainter oldDelegate) => false;
}

void main() {
  testWidgets(
    'inactive keyed geometry is skipped during the same frame paint',
    (tester) async {
      final key = GlobalKey();
      final visible = ValueNotifier(true);
      RenderBox? initialBox;
      RenderBox? removedBox;
      BuildContext? contextDuringRemoval;
      var removalWasMounted = false;
      var removalWasDetached = false;
      final painter = _LookupPainter(
        repaint: visible,
        lookup: () {
          final context = key.currentContext;
          if (visible.value) {
            initialBox = attachedTaskDropBox(context);
          } else {
            contextDuringRemoval = context;
            removalWasMounted = context?.mounted ?? false;
            if (context is Element && context.mounted) {
              removalWasDetached = context.renderObject?.attached == false;
            }
            removedBox = attachedTaskDropBox(context);
          }
        },
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        visible.dispose();
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, show, _) => CustomPaint(
                  foregroundPainter: painter,
                  child: Stack(
                    children: [
                      if (show) SizedBox(key: key, width: 48, height: 48),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final originalContext = key.currentContext!;
      expect(initialBox, isNotNull);
      expect(initialBox!.attached, isTrue);
      expect(initialBox!.size, const Size(48, 48));

      visible.value = false;
      await tester.pump();
      expect(contextDuringRemoval, same(originalContext));
      expect(removalWasMounted, isTrue);
      expect(removalWasDetached, isTrue);
      expect(removedBox, isNull);
      expect(tester.takeException(), isNull);

      // Finalization happens after paint; the retained context is now defunct.
      expect(originalContext.mounted, isFalse);
      expect(attachedTaskDropBox(originalContext), isNull);
      expect(key.currentContext, isNull);
      expect(attachedTaskDropBox(null), isNull);
    },
  );
}
