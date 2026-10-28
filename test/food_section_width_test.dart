import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/section_menu.dart';

import 'food_expiry_guidance_test.dart' show loadSdkRoboto;
import 'food_stock_toolbar_workflow_test.dart' show stockToolbarFoods;

void main() {
  setUpAll(loadSdkRoboto);
  testWidgets(
    'Food keeps the Tasks outer edges for empty and populated views',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var commands = 0;
      for (final width in [
        2048.0,
        1600.0,
        1450.0,
        1200.0,
        900.0,
        390.0,
        320.0,
      ]) {
        tester.view.physicalSize = Size(width, 1000);
        for (final brightness in Brightness.values) {
          for (final scale in [1.0, 2.0]) {
            for (final populated in [false, true]) {
              await tester.pumpWidget(
                MaterialApp(
                  key: ValueKey('$width-$brightness-$scale-$populated'),
                  theme: ThemeData(brightness: brightness),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: FoodInventoryPage(
                    state: projectFood(populated ? stockToolbarFoods() : []),
                    now: () => DateTime(2026, 10, 11),
                    userName: 'Synthetic household',
                    sectionMenu: (compact) => SectionMenu(
                      food: true,
                      compact: compact,
                      onSelected: (_) => commands++,
                    ),
                    onAdd: (_, _) => commands++,
                    onRemove: (_) => commands++,
                    onRestore: (_) => commands++,
                    onDetails: (_, _, _, _) => commands++,
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final reason =
                  '$width $brightness scale=$scale populated=$populated';
              final contentWidth = math.min(width, 1450.0);
              final left = (width - contentWidth) / 2;
              final search = tester.getRect(
                find.byKey(const ValueKey('food-search')),
              );
              expect(search.left, closeTo(left + 16, .01), reason: reason);
              expect(
                search.right,
                closeTo(left + contentWidth - 16, .01),
                reason: reason,
              );
              final section = tester.getRect(
                find.byKey(const ValueKey('section-menu')),
              );
              expect(section.left, closeTo(left + 16, .01), reason: reason);
              expect(tester.takeException(), isNull, reason: reason);
              expect(
                find.text('Food undated'),
                populated ? findsOneWidget : findsNothing,
              );
            }
          }
        }
      }
      expect(
        commands,
        0,
        reason: 'layout and text scaling do not issue commands',
      );
    },
  );
}
