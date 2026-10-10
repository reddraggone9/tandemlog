import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_import.dart';

void main() {
  test('v1 import identity and plan hash match independent frozen vector', () {
    final plan = FoodImportPlan.decode(
      File('test/fixtures/food-import/plan-v1.json').readAsStringSync(),
    );
    final expected =
        jsonDecode(
              File(
                'test/fixtures/food-import/expected-v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(plan.targetIds, expected['targetIds']);
    expect(plan.planHash, expected['planHash']);
    expect(plan.canonicalJson, expected['canonicalJson']);
    expect(plan.containers.single.contents.unknown, isTrue);
    expect(plan.containers.single.details.estimated, isNull);
    expect(plan.containers.single.createdAt, '2020-01-02T03:04:05+02:00');
  });
}
