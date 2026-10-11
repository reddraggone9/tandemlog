import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_import.dart';

void main() {
  test(
    'obsolete all-null import vector is rejected without rewriting frozen bytes',
    () {
      final bytes = File(
        'test/fixtures/food-import/plan-v1.json',
      ).readAsStringSync();
      expect(() => FoodImportPlan.decode(bytes), throwsFormatException);
      final expected =
          jsonDecode(
                File(
                  'test/fixtures/food-import/expected-v1.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(expected['canonicalJson'], contains('"numerator":null'));
    },
  );
}
