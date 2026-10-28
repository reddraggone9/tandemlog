import 'package:tandemlog/food/inventory.dart';

/// Host-free page tests record which descriptive fields one Save touched.
/// Name, Brand and Container size now arrive as product changes; product
/// semantics themselves are covered by food_products_test against FoodStore.
List<String> foodTouchedFields(
  List<String> fields,
  FoodProductChange products,
) => [
  for (final field in const ['name', 'brand', 'size'])
    if (products.changes.containsKey(field)) field,
  ...fields,
];
