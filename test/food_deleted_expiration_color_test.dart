import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/expiration_presentation.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/list_row_surface.dart';
import 'food_stock_toolbar_workflow_test.dart' show chooseFoodView;

void main() {
  for (final brightness in Brightness.values) {
    for (final sample in [(1200.0, 1.0), (320.0, 2.0)]) {
      testWidgets(
        'Deleted dates are neutral in view/search and restore urgency $brightness $sample',
        (tester) async {
          tester.view.physicalSize = Size(sample.$1, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final today = DateTime(2026, 10, 11);
          final colors = ColorScheme.fromSeed(
            seedColor: const Color(0xff267461),
            brightness: brightness,
          );
          const writer = '00000000-0000-4000-8000-000000000091';
          const active = '00000000-0000-4000-8000-000000000101';
          const retained = '00000000-0000-4000-8000-000000000102';
          const deletedExpired = '00000000-0000-4000-8000-000000000103';
          const deletedApproaching = '00000000-0000-4000-8000-000000000104';
          var sequence = 0, restores = 0;
          FoodOperation operation(
            FoodAction action,
            String target, {
            FoodDetails? details,
            List<String> observed = const [],
          }) {
            sequence++;
            return FoodOperation(
              id: '$writer:$sequence',
              order: sequence,
              action: action,
              targets: [target],
              details: details,
              observedDeletes: observed,
              contents: action == FoodAction.add
                  ? const Contents.fraction(1, 1)
                  : null,
              createdAt: action == FoodAction.add
                  ? '2026-10-11T00:00:00Z'
                  : null,
            );
          }

          final events = [
            operation(
              FoodAction.add,
              active,
              details: const FoodDetails(
                name: 'Food active expired',
                expiry: '2026-10-10',
              ),
            ),
            operation(
              FoodAction.add,
              retained,
              details: const FoodDetails(
                name: 'Food retained approaching',
                expiry: '2026-10-14',
                retention: 'Emergency',
              ),
            ),
            operation(
              FoodAction.add,
              deletedExpired,
              details: const FoodDetails(
                name: 'Food deleted expired',
                expiry: '2026-10-10',
              ),
            ),
            operation(FoodAction.remove, deletedExpired),
            operation(
              FoodAction.add,
              deletedApproaching,
              details: const FoodDetails(
                name: 'Food deleted approaching',
                expiry: '2026-10-14',
              ),
            ),
            operation(FoodAction.remove, deletedApproaching),
          ];
          final original = jsonEncode(events.map((e) => e.toJson()).toList());
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(colorScheme: colors),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(sample.$2)),
                child: child!,
              ),
              home: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return FoodInventoryPage(
                    state: projectFood(events),
                    now: () => today,
                    onAdd: (_, _) => fail('Unexpected Add'),
                    onRemove: (_) => fail('Unexpected Remove'),
                    onDetails: (_, _, _, _) => fail('Unexpected Edit'),
                    onRestore: (c) => update(() {
                      restores++;
                      events.add(
                        operation(
                          FoodAction.restore,
                          c.id,
                          observed: c.deletions.toList(),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scrollable = find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          );
          Future<void> top() async {
            tester.state<ScrollableState>(scrollable).position.jumpTo(0);
            await tester.pumpAndSettle();
          }

          Future<void> dateColor(
            String name,
            String date,
            Color expected,
          ) async {
            await top();
            final row = find.widgetWithText(ListRowSurface, name);
            await tester.scrollUntilVisible(row, 160, scrollable: scrollable);
            await tester.pumpAndSettle();
            final label = find.descendant(of: row, matching: find.text(date));
            expect(label, findsOneWidget);
            expect(tester.widget<Text>(label).style!.color, expected);
            expect(
              tester.widget<Text>(label).style!.fontWeight,
              FontWeight.w600,
            );
          }

          await dateColor('Food active expired', '2026-10-10', colors.error);
          await chooseFoodView(tester, 'Retained');
          await dateColor(
            'Food retained approaching',
            '2026-10-14',
            foodExpiryColor('2026-10-14', today, colors),
          );
          await chooseFoodView(tester, 'Deleted');
          await dateColor(
            'Food deleted expired',
            '2026-10-10',
            colors.onSurfaceVariant,
          );
          await dateColor(
            'Food deleted approaching',
            '2026-10-14',
            colors.onSurfaceVariant,
          );
          expect(restores, 0);
          expect(jsonEncode(events.map((e) => e.toJson()).toList()), original);

          await top();
          await tester.enterText(
            find.byKey(const ValueKey('food-search')),
            'Food',
          );
          await tester.pumpAndSettle();
          await dateColor('Food active expired', '2026-10-10', colors.error);
          await dateColor(
            'Food retained approaching',
            '2026-10-14',
            foodExpiryColor('2026-10-14', today, colors),
          );
          await dateColor(
            'Food deleted expired',
            '2026-10-10',
            colors.onSurfaceVariant,
          );
          await tester.tap(
            find.byTooltip('Restore one Food deleted expired container'),
          );
          await tester.pumpAndSettle();
          await dateColor('Food deleted expired', '2026-10-10', colors.error);
          await dateColor(
            'Food deleted approaching',
            '2026-10-14',
            colors.onSurfaceVariant,
          );
          await tester.tap(
            find.byTooltip('Restore one Food deleted approaching container'),
          );
          await tester.pumpAndSettle();
          await dateColor(
            'Food deleted approaching',
            '2026-10-14',
            foodExpiryColor('2026-10-14', today, colors),
          );
          expect(restores, 2);
          expect(
            jsonEncode(events.take(6).map((e) => e.toJson()).toList()),
            original,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
