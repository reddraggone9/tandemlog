import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_toolbar.dart';

void main() {
  testWidgets(
    'identity fits actual name/scale and retains accessible full name at narrow widths',
    (tester) async {
      const name = 'Alexandria Example Household';
      for (final brightness in Brightness.values) {
        for (final width in [320.0, 390.0, 900.0, 1450.0]) {
          for (final scale in [1.0, 2.0, 2.5]) {
            for (final searching in [false, true]) {
              tester.view.physicalSize = Size(width, 300);
              tester.view.devicePixelRatio = 1;
              await tester.pumpWidget(
                MaterialApp(
                  theme: ThemeData(brightness: brightness),
                  home: Scaffold(
                    body: MediaQuery(
                      data: MediaQueryData(
                        size: Size(width, 300),
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: TaskToolbar(
                          userName: name,
                          undo: IconButton(
                            onPressed: () {},
                            tooltip: 'Undo',
                            icon: const Icon(Icons.undo),
                          ),
                          search: () {},
                          searchField: searching
                              ? const TextField(
                                  decoration: InputDecoration(
                                    hintText: 'Search all tasks',
                                    border: InputBorder.none,
                                  ),
                                )
                              : null,
                          identityMenu: (child) => PopupMenuButton<String>(
                            key: const ValueKey('identity-menu'),
                            tooltip: 'Active user: $name',
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'settings',
                                child: Text('Settings'),
                              ),
                            ],
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason:
                    'width=$width scale=$scale search=$searching theme=$brightness',
              );
              expect(find.text('Tandemlog'), findsNothing);
              expect(find.byTooltip('Active user: $name'), findsOneWidget);
              final menu = tester.getRect(
                find.byKey(const ValueKey('identity-menu')),
              );
              expect(menu.width, greaterThanOrEqualTo(48));
              expect(menu.height, greaterThanOrEqualTo(48));
              expect(menu.right, lessThanOrEqualTo(width));
              if (width == 1450 && !searching) {
                expect(find.text(name), findsOneWidget);
              }
              if (width == 320) expect(find.text('A'), findsOneWidget);
            }
          }
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
