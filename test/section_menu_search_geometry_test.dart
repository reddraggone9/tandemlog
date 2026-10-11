import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'package:tandemlog/presentation/task_toolbar.dart';

import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(loadSdkRoboto);

  testWidgets(
    'Search and Add modes keep section, account and action geometry fixed',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      const name = 'Alex Example';
      const controlKeys = [
        'section-menu',
        'input-mode',
        'account',
        'undo',
        'filter',
      ];

      // Include intermediate desktop widths where mode-dependent reservations
      // previously changed account shape and shifted neighboring actions, plus
      // narrow icons and a comfortably wide named account. The longer Search
      // label must not move the toolbar when replacing Add.
      for (final sample in [
        (320.0, 2.5),
        (390.0, 1.0),
        (640.0, 1.5),
        (720.0, 1.5),
        (760.0, 2.0),
        (850.0, 2.0),
        (900.0, 2.5),
        (1450.0, 1.0),
      ]) {
        tester.view.physicalSize = Size(sample.$1, 500);
        List<Rect>? closedGeometry;
        bool? closedNamedAccount;
        for (final captureMode in [false, true, false]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(sample.$2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TaskToolbar(
                      sectionMenu: (compact) => SectionMenu(
                        food: false,
                        compact: compact,
                        onSelected: (_) {},
                      ),
                      userName: name,
                      count: '165 open',
                      countLabels: const ['165 open', '10000 completed'],
                      undo: IconButton(
                        key: const ValueKey('undo'),
                        tooltip: 'Undo',
                        onPressed: () {},
                        icon: const Icon(Icons.undo),
                      ),
                      inputModeAction: (compact) => compact
                          ? IconButton(
                              key: const ValueKey('input-mode'),
                              tooltip: captureMode
                                  ? 'Search tasks (Ctrl+F)'
                                  : 'Add tasks',
                              onPressed: () {},
                              icon: Icon(
                                captureMode ? Icons.search : Icons.add,
                                size: 20,
                              ),
                            )
                          : Tooltip(
                              message: captureMode
                                  ? 'Search tasks (Ctrl+F)'
                                  : 'Add tasks',
                              child: OutlinedButton.icon(
                                key: const ValueKey('input-mode'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: () {},
                                icon: Icon(
                                  captureMode ? Icons.search : Icons.add,
                                  size: 20,
                                ),
                                label: Text(captureMode ? 'Search' : 'Add'),
                              ),
                            ),
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
                      identityMenu: (child) => PopupMenuButton<String>(
                        key: const ValueKey('account'),
                        tooltip: 'Active user: $name',
                        itemBuilder: (_) => const [
                          PopupMenuItem(
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
          final reason =
              'width=${sample.$1} scale=${sample.$2} capture=$captureMode';
          expect(tester.takeException(), isNull, reason: reason);
          final geometry = [
            for (final key in controlKeys)
              tester.getRect(find.byKey(ValueKey(key))),
          ];
          final namedAccount = find.text(name).evaluate().isNotEmpty;
          closedGeometry ??= geometry;
          closedNamedAccount ??= namedAccount;
          expect(geometry, closedGeometry, reason: reason);
          expect(namedAccount, closedNamedAccount, reason: reason);
          expect(find.byTooltip('Active user: $name'), findsOneWidget);
          final action = find.byKey(const ValueKey('input-mode'));
          expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
          expect(
            find.byTooltip(captureMode ? 'Search tasks (Ctrl+F)' : 'Add tasks'),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: action,
              matching: find.text(captureMode ? 'Search' : 'Add'),
            ),
            sample.$1 - 16 < 600 ? findsNothing : findsOneWidget,
          );
        }
      }
    },
  );
}
