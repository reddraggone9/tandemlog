import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../domain/event.dart' show isCanonicalId;
import '../domain/event_chain.dart' show canonicalDataJson;
import 'inventory.dart';

/// Products and purchases (design/food-products.md). A product describes a
/// SKU; prices live only on purchases. Containers without an explicit product
/// link belong to the implicit product derived from their own description, so
/// existing history needs no migration writes.

const foodProductNamespace = '5b0e8a52-3c4d-4f71-9a2e-6d1c7b9f0e34';
const productFieldNames = {'name', 'brand', 'size', 'links', 'minimum'};
const purchaseFieldNames = {
  'product',
  'date',
  'store',
  'amount',
  'currency',
  'quantity',
  'source',
  'voided',
};
const _purchaseRequired = {
  'product',
  'date',
  'store',
  'amount',
  'currency',
  'quantity',
};
const maximumFoodProducts = 100000, maximumFoodPurchases = 200000;
const maximumProductLinks = 4, maximumProductMinimum = 999;

/// The implicit product of a description: identical name/brand/size share it.
String implicitFoodProductId(FoodDetails details) => const Uuid().v5(
  foodProductNamespace,
  'tandemlog:food-product:implicit:v1\n'
  '${canonicalDataJson([details.name, details.brand, details.size])}',
);

/// Imported purchase identity is a function of its receipt line, so a retried
/// import converges on the same purchase.
String importedFoodPurchaseId(String kind, String key) => const Uuid().v5(
  foodProductNamespace,
  'tandemlog:food-purchase:v1\n$kind\n$key',
);

Never _invalid(String what) => throw FormatException('Invalid food $what.');

void _text(Object? value, int limit, {bool required = false}) {
  if (value is! String ||
      value.length > limit ||
      (required && value.trim().isEmpty) ||
      value.contains('\u0000')) {
    _invalid('text');
  }
}

bool isFoodCivilDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  final date = DateTime.tryParse(value);
  return date != null &&
      date.year.toString().padLeft(4, '0') == value.substring(0, 4) &&
      date.month.toString().padLeft(2, '0') == value.substring(5, 7) &&
      date.day.toString().padLeft(2, '0') == value.substring(8, 10);
}

/// A store link: an absolute http(s) URL of at most 2,048 bytes.
bool isFoodStoreLink(Object? value) {
  if (value is! String ||
      value.trim() != value ||
      utf8.encode(value).length > 2048) {
    return false;
  }
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

void validateFoodProductValues(Map<String, Object?> values) {
  if (values.isEmpty ||
      values.keys.any((k) => !productFieldNames.contains(k))) {
    _invalid('product fields');
  }
  for (final MapEntry(:key, :value) in values.entries) {
    switch (key) {
      case 'name':
        _text(value, 500, required: true);
      case 'brand' || 'size':
        _text(value, 200);
      case 'links':
        if (value is! List ||
            value.length > maximumProductLinks ||
            value.toSet().length != value.length ||
            value.any((link) => !isFoodStoreLink(link))) {
          _invalid('store links');
        }
      case 'minimum':
        if (value != null &&
            (value is! int || value < 0 || value > maximumProductMinimum)) {
          _invalid('minimum');
        }
    }
  }
}

void validateFoodPurchaseValues(
  Map<String, Object?> values, {
  required bool complete,
}) {
  final keys = values.keys.toSet();
  if (keys.any((k) => !purchaseFieldNames.contains(k)) ||
      (complete
          ? !keys.containsAll(_purchaseRequired) || keys.contains('voided')
          : keys.isEmpty || keys.contains('source'))) {
    _invalid('purchase fields');
  }
  for (final MapEntry(:key, :value) in values.entries) {
    final valid = switch (key) {
      'product' => isCanonicalId(value),
      'date' => isFoodCivilDate(value),
      'store' =>
        value is String && value.length <= 200 && !value.contains('\u0000'),
      'amount' => value is int && value >= 0 && value <= 1000000000,
      'currency' => value is String && RegExp(r'^[A-Z]{3}$').hasMatch(value),
      'quantity' => value is int && value >= 1 && value <= 1000,
      'voided' => value is bool,
      _ =>
        value is Map &&
            value.length == 2 &&
            value['kind'] is String &&
            RegExp(r'^[a-z0-9][a-z0-9.-]{0,39}$').hasMatch(value['kind']) &&
            value['key'] is String &&
            (value['key'] as String).isNotEmpty &&
            (value['key'] as String).length <= 200 &&
            !(value['key'] as String).contains('\u0000'),
    };
    if (!valid) _invalid('purchase $key');
  }
}

/// container.add revision 2 requires a product; container.link names a
/// subset of product/purchase, where a null purchase clears the link.
void validateFoodLink(Map<String, Object?> values, {required bool creation}) {
  final keys = values.keys.toSet();
  if (keys.isEmpty ||
      keys.any((k) => k != 'product' && k != 'purchase') ||
      (creation && !keys.contains('product')) ||
      (keys.contains('product') && !isCanonicalId(values['product'])) ||
      (keys.contains('purchase') &&
          !(values['purchase'] == null && !creation) &&
          !isCanonicalId(values['purchase']))) {
    _invalid('container link');
  }
}

/// One receipt line after per-field last-writer-wins.
class FoodPurchase {
  const FoodPurchase({
    required this.id,
    required this.product,
    required this.date,
    required this.store,
    required this.amount,
    required this.currency,
    required this.quantity,
    this.source,
    this.voided = false,
  });
  final String id, product, date, store, currency;
  final int amount, quantity;
  final Map<String, Object?>? source;
  final bool voided;

  /// Cost of one container in minor units (fractional).
  double get unitCost => amount / quantity;

  FoodPurchase _apply(Map<String, Object?> values) => FoodPurchase(
    id: id,
    product: values['product'] as String? ?? product,
    date: values['date'] as String? ?? date,
    store: values['store'] as String? ?? store,
    amount: values['amount'] as int? ?? amount,
    currency: values['currency'] as String? ?? currency,
    quantity: values['quantity'] as int? ?? quantity,
    source: values.containsKey('source')
        ? Map.unmodifiable(values['source'] as Map)
        : source,
    voided: values['voided'] as bool? ?? voided,
  );

  Map<String, Object?> toJson() => {
    'product': product,
    'date': date,
    'store': store,
    'amount': amount,
    'currency': currency,
    'quantity': quantity,
    if (source != null) 'source': source,
  };
}

/// Product-level state folded from non-retracted product-level operations in
/// canonical order: per-field product values, merge aliases and purchases.
class FoodCatalog {
  FoodCatalog._(this.products, this.aliases, this.purchases);
  static final empty = FoodCatalog._(const {}, const {}, const {});

  /// Edited product fields by product ID (merged-away products included).
  final Map<String, Map<String, Object?>> products;

  /// Merged-away product ID to its current root.
  final Map<String, String> aliases;
  final Map<String, FoodPurchase> purchases;
  bool get isEmpty => products.isEmpty && aliases.isEmpty && purchases.isEmpty;

  String resolve(String product) => aliases[product] ?? product;

  /// Same product-level state (for view reuse after a full re-admission).
  bool equivalent(FoodCatalog other) =>
      identical(this, other) ||
      (isEmpty && other.isEmpty) ||
      _signature == other._signature;
  late final String _signature = canonicalDataJson({
    'products': products,
    'aliases': aliases,
    'purchases': {
      for (final p in purchases.values)
        p.id: {...p.toJson(), 'voided': p.voided},
    },
  });

  /// Product IDs referenced by any edit or merge.
  bool knows(String product) =>
      products.containsKey(product) || aliases.containsKey(product);

  /// Purchases by resolved product, newest first (date, then ID).
  late final Map<String, List<FoodPurchase>> purchasesByProduct = () {
    final result = <String, List<FoodPurchase>>{};
    for (final purchase in purchases.values) {
      (result[resolve(purchase.product)] ??= []).add(purchase);
    }
    for (final list in result.values) {
      list.sort((a, b) {
        final date = b.date.compareTo(a.date);
        return date != 0 ? date : b.id.compareTo(a.id);
      });
    }
    return result;
  }();

  /// [ordered] holds non-retracted product-level operations in canonical
  /// order. Later operations win each field.
  factory FoodCatalog.build(Iterable<FoodOperation> ordered) {
    final products = <String, Map<String, Object?>>{};
    final aliases = <String, String>{};
    final purchases = <String, FoodPurchase>{};
    final pendingEdits = <String, Map<String, Object?>>{};
    String resolve(String id) => aliases[id] ?? id;
    for (final op in ordered) {
      final target = op.targets.single;
      switch (op.action) {
        case FoodAction.product:
          (products[target] ??= {}).addAll(op.product!);
        case FoodAction.merge:
          final source = resolve(target), into = resolve(op.into!);
          if (source == into) continue;
          aliases[source] = into;
          for (final entry in aliases.entries.toList()) {
            if (entry.value == source) aliases[entry.key] = into;
          }
        case FoodAction.purchase:
          final previous = purchases[target];
          final values = op.purchase!;
          purchases[target] = previous != null
              ? previous._apply(values)
              : FoodPurchase(
                  id: target,
                  product: values['product'] as String,
                  date: values['date'] as String,
                  store: values['store'] as String,
                  amount: values['amount'] as int,
                  currency: values['currency'] as String,
                  quantity: values['quantity'] as int,
                  source: values['source'] == null
                      ? null
                      : Map.unmodifiable(values['source'] as Map),
                )._apply(pendingEdits.remove(target) ?? const {});
        case FoodAction.purchaseEdit:
          final previous = purchases[target];
          if (previous != null) {
            purchases[target] = previous._apply(op.purchase!);
          } else {
            (pendingEdits[target] ??= {}).addAll(op.purchase!);
          }
        default:
          throw ArgumentError('Not a product-level Food operation.');
      }
      if (products.length + aliases.length > maximumFoodProducts) {
        throw const FormatException('Too many food products.');
      }
      if (purchases.length + pendingEdits.length > maximumFoodPurchases) {
        throw const FormatException('Too many food purchases.');
      }
    }
    return FoodCatalog._(
      Map<String, Map<String, Object?>>.unmodifiable({
        for (final e in products.entries)
          e.key: Map<String, Object?>.unmodifiable(e.value),
      }),
      Map<String, String>.unmodifiable(aliases),
      Map<String, FoodPurchase>.unmodifiable(purchases),
    );
  }

  /// Displayed details: product fields over the container's own.
  FoodDetails overlay(FoodDetails own, String root) {
    final fields = products[root];
    if (fields == null) return own;
    final name = fields['name'] as String?,
        brand = fields['brand'] as String?,
        size = fields['size'] as String?;
    if ((name == null || name == own.name) &&
        (brand == null || brand == own.brand) &&
        (size == null || size == own.size)) {
      return own;
    }
    return FoodDetails(
      name: name ?? own.name,
      brand: brand ?? own.brand,
      expiry: own.expiry,
      estimated: own.estimated,
      retention: own.retention,
      location: own.location,
      size: size ?? own.size,
    );
  }
}

/// Derived product figures for the editor and Running low.
class FoodProductSummary {
  FoodProductSummary({
    required this.id,
    required this.name,
    required this.brand,
    required this.size,
    required this.links,
    required this.minimum,
    required this.onHand,
    required this.containers,
    required this.purchases,
  });
  final String id, name, brand, size;
  final List<String> links;
  final int? minimum;

  /// Non-deleted containers (decision 5), and every container.
  final int onHand, containers;

  /// Non-voided purchases, newest first.
  final List<FoodPurchase> purchases;
  bool get runningLow => minimum != null && onHand < minimum!;
  FoodPurchase? get last => purchases.firstOrNull;

  /// Median unit cost of the newest 5 purchases within 12 months of the newest,
  /// from 2 purchases (decision 10).
  double? typicalUnitCost(DateTime today) {
    final cutoff = DateTime.utc(today.year - 1, today.month, today.day);
    final recent = purchases
        .where((p) => !DateTime.parse(p.date).isBefore(cutoff))
        .take(5)
        .map((p) => p.unitCost)
        .toList();
    if (recent.length < 2) return null;
    recent.sort();
    final middle = recent.length ~/ 2;
    return recent.length.isOdd
        ? recent[middle]
        : (recent[middle - 1] + recent[middle]) / 2;
  }

  FoodDetails get description =>
      FoodDetails(name: name, brand: brand, size: size);
}

/// Money in minor units, e.g. \$3.48 (USD) or 3.48 EUR.
String foodMoney(double minorUnits, String currency) {
  final value = (minorUnits / 100).toStringAsFixed(2);
  return currency == 'USD' ? '\$$value' : '$value $currency';
}

String _normal(String value) => value.trim().toLowerCase();
String foodDescriptionKey(String name, String brand, String size) =>
    canonicalDataJson([_normal(name), _normal(brand), _normal(size)]);

/// Product changes requested with a Food edit: [changes] holds only changed
/// fields (name/brand/size, and links/minimum from the single-row editor).
class FoodProductChange {
  const FoodProductChange({this.roots = const [], this.changes = const {}});
  final List<String> roots;
  final Map<String, Object?> changes;
  bool get isEmpty => roots.isEmpty || changes.isEmpty;
}

/// One product-level step of a planned edit.
sealed class FoodProductStep {
  const FoodProductStep();
}

class FoodProductEdit extends FoodProductStep {
  FoodProductEdit(this.product, Map<String, Object?> values)
    : values = Map.unmodifiable(values);
  final String product;
  final Map<String, Object?> values;
}

class FoodProductMerge extends FoodProductStep {
  const FoodProductMerge(this.source, this.into);
  final String source, into;
}

/// Plans product changes. [changes] holds only the fields the user changed:
/// name/brand/size and, from the single-row editor, links/minimum. Products
/// whose resulting descriptions coincide with each other, or with another
/// existing product, merge (decisions 2 and 4).
List<FoodProductStep> planFoodProductChanges(
  FoodState state,
  List<String> roots,
  Map<String, Object?> changes,
) {
  final products = state.products;
  final selected = roots.toSet();
  final steps = <FoodProductStep>[];
  final groups = <String, List<FoodProductSummary>>{};
  for (final root in roots) {
    final product = products[root];
    if (product == null) continue;
    final name = changes['name'] as String? ?? product.name,
        brand = changes['brand'] as String? ?? product.brand,
        size = changes['size'] as String? ?? product.size;
    (groups[foodDescriptionKey(name, brand, size)] ??= []).add(product);
  }
  for (final MapEntry(key: description, value: members) in groups.entries) {
    final outside = state.productsByDescription[description]
        ?.where((p) => !selected.contains(p.id))
        .firstOrNull;
    // Keep the identity with the most containers (lowest ID on a tie), so the
    // fewest containers change product.
    final target =
        outside ??
        members.reduce(
          (a, b) =>
              b.containers > a.containers ||
                  (b.containers == a.containers && b.id.compareTo(a.id) < 0)
              ? b
              : a,
        );
    final sources = members.where((p) => p.id != target.id).toList();
    final values = <String, Object?>{};
    if (outside == null) {
      for (final (field, current) in [
        ('name', target.name),
        ('brand', target.brand),
        ('size', target.size),
      ]) {
        final next = changes[field] as String?;
        if (next != null && next != current) values[field] = next;
      }
    }
    if (changes.containsKey('links') &&
        canonicalDataJson(changes['links']) !=
            canonicalDataJson(target.links)) {
      values['links'] = changes['links'];
    }
    if (changes.containsKey('minimum') &&
        changes['minimum'] != target.minimum) {
      values['minimum'] = changes['minimum'];
    }
    // The first edit of an implicit product, or a merge into it, records its
    // description so it no longer depends on any container's own fields.
    if ((values.isNotEmpty || sources.isNotEmpty) &&
        !state.catalog.products.containsKey(target.id)) {
      values.putIfAbsent('name', () => target.name);
      values.putIfAbsent('brand', () => target.brand);
      values.putIfAbsent('size', () => target.size);
    }
    if (values.isNotEmpty) steps.add(FoodProductEdit(target.id, values));
    for (final source in sources) {
      steps.add(FoodProductMerge(source.id, target.id));
    }
  }
  return steps;
}

/// How an Add or import attaches new containers to a product.
class FoodAddPlan {
  const FoodAddPlan({this.product, this.create});

  /// Explicit product link; null writes container.add revision 1 (implicit).
  final String? product;

  /// Values of a new explicit product to create in the same action.
  final Map<String, Object?>? create;
}

/// Matches typed name/brand/size against existing products (trimmed,
/// case-insensitive; most containers wins a tie). [preferred] keeps Add
/// another on its row's product while the description still matches.
FoodAddPlan planFoodAdd(
  FoodState state,
  FoodDetails details, {
  String? preferred,
  String Function()? newId,
}) {
  final key = foodDescriptionKey(details.name, details.brand, details.size);
  final implicit = implicitFoodProductId(details);
  FoodProductSummary? match;
  if (preferred != null) {
    final product = state.products[state.catalog.resolve(preferred)];
    if (product != null &&
        foodDescriptionKey(product.name, product.brand, product.size) == key) {
      match = product;
    }
  }
  match ??= state.productsByDescription[key]?.first;
  if (match != null) {
    return state.catalog.resolve(implicit) == match.id
        ? const FoodAddPlan()
        : FoodAddPlan(product: match.id);
  }
  // A renamed or merged-away product keeps its derived ID; a new product with
  // that old description needs its own identity.
  if (state.catalog.knows(implicit)) {
    return FoodAddPlan(
      product: (newId ?? () => const Uuid().v4())(),
      create: {
        'name': details.name,
        'brand': details.brand,
        'size': details.size,
      },
    );
  }
  return const FoodAddPlan();
}
