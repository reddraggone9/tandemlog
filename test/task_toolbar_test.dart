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
                          count: '165 open',
                          countLabels: const ['165 open', '10000 completed'],
                          filter: (compact) => compact
                              ? IconButton(
                                  key: const ValueKey('filter'),
                                  tooltip: 'Filter tasks',
                                  onPressed: () {},
                                  icon: const Icon(Icons.filter_list),
                                )
                              : OutlinedButton.icon(
                                  key: const ValueKey('filter'),
                                  onPressed: () {},
                                  icon: const Icon(Icons.filter_list),
                                  label: const Text('Filter'),
                                ),
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
              final filter = tester.getRect(
                find.byKey(const ValueKey('filter')),
              );
              expect(filter.width, greaterThanOrEqualTo(48));
              expect(filter.right, lessThanOrEqualTo(width));
              if (width == 1450 && !searching && scale == 1) {
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
  testWidgets('status changes reserve count and control geometry', (
    tester,
  ) async {
    for (final width in [320.0, 390.0, 1200.0]) {
      for (final scale in [1.0, 2.5]) {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        Widget header(String count) => MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TaskToolbar(
                  userName: 'Alex Example',
                  count: count,
                  countLabels: const ['10000 open', '1 completed'],
                  undo: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.undo),
                  ),
                  search: () {},
                  filter: (compact) => IconButton(
                    key: const ValueKey('filter'),
                    onPressed: () {},
                    icon: const Icon(Icons.filter_list),
                  ),
                  identityMenu: (child) => PopupMenuButton(
                    key: const ValueKey('identity'),
                    itemBuilder: (_) => [
                      const PopupMenuItem(child: Text('Settings')),
                    ],
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(header('10000 open'));
        await tester.pumpAndSettle();
        final before = [
          for (final key in ['task-header', 'filter', 'identity'])
            tester.getRect(find.byKey(ValueKey(key))),
        ];
        await tester.pumpWidget(header('1 completed'));
        await tester.pumpAndSettle();
        expect([
          for (final key in ['task-header', 'filter', 'identity'])
            tester.getRect(find.byKey(ValueKey(key))),
        ], before);
        expect(tester.takeException(), isNull);
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
