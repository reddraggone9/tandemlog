import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/editor_dialog_gutter.dart';
import 'package:tandemlog/presentation/tandemlog_theme.dart';
import 'support/ux_capture.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1200, 850)]) {
    for (final scale in [1.0, 2.0]) {
      for (final brightness in Brightness.values) {
        for (final before in [true, false]) {
          testWidgets(
            'spacing ${size.width} $scale ${brightness.name} before=$before',
            (tester) async {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = size;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              Widget gutter(Widget child) =>
                  before ? child : EditorDialogGutter(child: child);
              await tester.pumpWidget(
                RepaintBoundary(
                  key: const ValueKey('ux-root'),
                  child: MaterialApp(
                    theme: tandemlogTheme(brightness),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: Scaffold(
                      body: AlertDialog(
                        scrollable: true,
                        insetPadding: const EdgeInsets.all(16),
                        titlePadding: EdgeInsets.fromLTRB(
                          before ? 16 : 0,
                          16,
                          before ? 16 : 0,
                          0,
                        ),
                        contentPadding: EdgeInsets.fromLTRB(
                          before ? 16 : 0,
                          12,
                          before ? 16 : 0,
                          12,
                        ),
                        actionsPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        title: gutter(
                          const Text('Edit task', key: ValueKey('heading')),
                        ),
                        content: gutter(
                          const SizedBox(
                            width: 480,
                            child: TextField(
                              key: ValueKey('field'),
                              decoration: InputDecoration(labelText: 'Title'),
                              controller: null,
                            ),
                          ),
                        ),
                        actions: [
                          FilledButton(
                            style: before
                                ? const ButtonStyle(
                                    minimumSize: WidgetStatePropertyAll(
                                      Size(64, 40),
                                    ),
                                  )
                                : null,
                            onPressed: () {},
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final dialog = tester.getRect(
                find
                    .descendant(
                      of: find.byType(Dialog),
                      matching: find.byType(Material),
                    )
                    .first,
              );
              final field = tester.getRect(find.byKey(const ValueKey('field')));
              if (!before) {
                expect(field.left - dialog.left, closeTo(16, .1));
                expect(dialog.right - field.right, closeTo(16, .1));
                expect(
                  tester
                      .getSize(
                        find
                            .descendant(
                              of: find.byType(FilledButton),
                              matching: find.byType(Material),
                            )
                            .first,
                      )
                      .height,
                  greaterThanOrEqualTo(48),
                );
              }
              await captureUx(
                tester,
                '${before ? 'before' : 'after'}-${size.width.toInt()}-${scale.toInt()}x-${brightness.name}',
              );
            },
          );
        }
      }
    }
  }
}
