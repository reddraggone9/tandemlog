import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../domain/event.dart' show isCanonicalId;
import '../domain/event_chain.dart' show canonicalDataJson;
import 'inventory.dart';

/// Receipt lines prepared by Vex's YNAB itemization workflow
/// (design/food-products.md, section 5). Tandemlog validates and commits; it
/// never parses receipts.
final class FoodPurchaseLine {
  FoodPurchaseLine({
    required this.sourceKind,
    required this.sourceKey,
    required this.date,
    required this.store,
    required this.amount,
    this.currency = 'USD',
    required this.quantity,
    this.product,
    this.name,
    this.brand = '',
    this.size = '',
    this.link,
  });
  final String sourceKind, sourceKey, date, store, currency, brand, size;
  final int amount, quantity;

  /// An existing product ID (explicit or implicit), or else a description.
  final String? product, name, link;

  String get purchaseId => importedFoodPurchaseId(sourceKind, sourceKey);
  Map<String, Object?> get source => {'kind': sourceKind, 'key': sourceKey};

  Map<String, dynamic> toJson() => {
    'source': source,
    'date': date,
    'store': store,
    'amount': amount,
    'currency': currency,
    'quantity': quantity,
    if (product != null) 'product': product,
    if (name != null) 'name': name,
    if (name != null) 'brand': brand,
    if (name != null) 'size': size,
    if (link != null) 'link': link,
  };

  factory FoodPurchaseLine.fromJson(Map<String, dynamic> j) {
    const allowed = {
      'source',
      'date',
      'store',
      'amount',
      'currency',
      'quantity',
      'product',
      'name',
      'brand',
      'size',
      'link',
    };
    final source = j['source'];
    if (j.keys.any((k) => !allowed.contains(k)) ||
        source is! Map ||
        source.length != 2 ||
        source['kind'] is! String ||
        source['key'] is! String ||
        j['date'] is! String ||
        j['store'] is! String ||
        j['amount'] is! int ||
        j['currency'] is! String ||
        j['quantity'] is! int ||
        (j['product'] != null && j['product'] is! String) ||
        (j['name'] != null && j['name'] is! String) ||
        (j['brand'] != null && j['brand'] is! String) ||
        (j['size'] != null && j['size'] is! String) ||
        (j['link'] != null && j['link'] is! String) ||
        (j['name'] == null &&
            (j.containsKey('brand') || j.containsKey('size')))) {
      throw const FormatException('Invalid purchase line.');
    }
    final line = FoodPurchaseLine(
      sourceKind: source['kind'] as String,
      sourceKey: source['key'] as String,
      date: j['date'] as String,
      store: j['store'] as String,
      amount: j['amount'] as int,
      currency: j['currency'] as String,
      quantity: j['quantity'] as int,
      product: j['product'] as String?,
      name: j['name'] as String?,
      brand: j['brand'] as String? ?? '',
      size: j['size'] as String? ?? '',
      link: j['link'] as String?,
    );
    line.validate();
    return line;
  }

  void validate() {
    validateFoodPurchaseValues({
      'product': product ?? foodProductNamespace,
      'date': date,
      'store': store,
      'amount': amount,
      'currency': currency,
      'quantity': quantity,
      'source': source,
    }, complete: true);
    if ((product == null) == (name == null) ||
        (product != null && !isCanonicalId(product)) ||
        (link != null && !isFoodStoreLink(link))) {
      throw const FormatException(
        'A purchase line names one product or one description.',
      );
    }
    if (name != null) {
      FoodDetails(name: name!, brand: brand, size: size).validate();
    }
  }
}

final class FoodPurchaseImportPlan {
  FoodPurchaseImportPlan({
    required this.space,
    required this.importId,
    required this.sourceSha256,
    required List<FoodPurchaseLine> lines,
  }) : lines = List.unmodifiable(lines) {
    validate();
  }
  final String space, importId, sourceSha256;
  final List<FoodPurchaseLine> lines;
  static const maximumLines = 500, maximumBytes = 1024 * 1024;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'space': space,
    'importId': importId,
    'sourceSha256': sourceSha256,
    'lines': [for (final line in lines) line.toJson()],
  };
  String get canonicalJson => canonicalDataJson(toJson());
  String get planHash => sha256
      .convert(
        utf8.encode('tandemlog:food-purchase-import-plan:v1\n$canonicalJson'),
      )
      .toString();

  factory FoodPurchaseImportPlan.decode(String encoded) {
    if (utf8.encode(encoded).length > maximumBytes) {
      throw const FormatException('Purchase plan exceeds staging limit.');
    }
    final j = jsonDecode(encoded);
    if (j is! Map<String, dynamic> ||
        j.length != 5 ||
        j['v'] != 1 ||
        j['space'] is! String ||
        j['importId'] is! String ||
        j['sourceSha256'] is! String ||
        j['lines'] is! List ||
        (j['lines'] as List).length > maximumLines) {
      throw const FormatException('Invalid purchase plan.');
    }
    return FoodPurchaseImportPlan(
      space: j['space'] as String,
      importId: j['importId'] as String,
      sourceSha256: j['sourceSha256'] as String,
      lines: [
        for (final line in j['lines'] as List)
          if (line is Map<String, dynamic>)
            FoodPurchaseLine.fromJson(line)
          else
            throw const FormatException('Invalid purchase line.'),
      ],
    );
  }

  void validate() {
    if (!isCanonicalId(space) ||
        !isCanonicalId(importId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceSha256) ||
        lines.isEmpty ||
        lines.length > maximumLines) {
      throw const FormatException('Invalid purchase plan identity or count.');
    }
    final ids = <String>{};
    for (final line in lines) {
      line.validate();
      if (!ids.add(line.purchaseId)) {
        throw const FormatException('Duplicate purchase line source.');
      }
    }
    if (utf8.encode(canonicalJson).length > maximumBytes) {
      throw const FormatException('Purchase plan exceeds staging limit.');
    }
  }
}

enum FoodPurchaseLineStatus { recorded, present }

class FoodPurchaseLineReport {
  FoodPurchaseLineReport({
    required this.purchase,
    required this.product,
    required this.status,
    required List<String> matched,
    required List<String> created,
    this.newProduct = false,
  }) : matched = List.unmodifiable(matched),
       created = List.unmodifiable(created);
  final String purchase, product;
  final FoodPurchaseLineStatus status;

  /// Recent hand entries linked to this purchase, and new Inbox containers.
  final List<String> matched, created;
  final bool newProduct;
}

enum FoodPurchaseImportStatus { ready, committed }

class FoodPurchaseImportReport {
  FoodPurchaseImportReport(
    this.status,
    this.planHash,
    List<FoodPurchaseLineReport> lines,
  ) : lines = List.unmodifiable(lines);
  final FoodPurchaseImportStatus status;
  final String planHash;
  final List<FoodPurchaseLineReport> lines;
}

/// The writes one purchase import makes, in order.
sealed class FoodImportStep {
  const FoodImportStep();
}

class FoodImportProduct extends FoodImportStep {
  const FoodImportProduct(this.product, this.values);
  final String product;
  final Map<String, Object?> values;
}

class FoodImportPurchase extends FoodImportStep {
  const FoodImportPurchase(this.purchase, this.values);
  final String purchase;
  final Map<String, Object?> values;
}

class FoodImportLink extends FoodImportStep {
  const FoodImportLink(this.containers, this.purchase);
  final List<String> containers;
  final String purchase;
}

class FoodImportCreate extends FoodImportStep {
  const FoodImportCreate(
    this.containers,
    this.details,
    this.product,
    this.purchase,
  );
  final List<String> containers;
  final FoodDetails details;
  final String product, purchase;
}

/// Hand entries match from the day before the purchase through 14 days after.
const purchaseMatchDaysBefore = 1, purchaseMatchDaysAfter = 14;

/// Plans one purchase import against [state] (decision 7): each line links up
/// to its quantity of recent unlinked hand entries of its product and creates
/// the remaining units as Inbox containers. Lines already recorded with the
/// same values are skipped; different values for the same source fail.
({FoodPurchaseImportReport report, List<FoodImportStep> steps})
planFoodPurchaseImport(
  FoodState state,
  FoodPurchaseImportPlan plan, {
  Map<String, FoodPurchase>? recordedPurchases,
}) {
  final steps = <FoodImportStep>[];
  final reports = <FoodPurchaseLineReport>[];
  final claimed = <String>{};
  final newProducts = <String, String>{};
  final edited = <String, List<String>>{};
  for (final line in plan.lines) {
    final purchaseId = line.purchaseId;
    final existing = (recordedPurchases ?? state.catalog.purchases)[purchaseId];
    if (existing != null) {
      final recorded = existing.toJson()..remove('product');
      final requested = {
        'date': line.date,
        'store': line.store,
        'amount': line.amount,
        'currency': line.currency,
        'quantity': line.quantity,
        'source': line.source,
      };
      if (canonicalDataJson(recorded) != canonicalDataJson(requested) ||
          (line.product != null &&
              state.catalog.resolve(existing.product) !=
                  state.catalog.resolve(line.product!))) {
        throw FormatException(
          'Purchase ${line.sourceKind} ${line.sourceKey} was recorded with different values.',
        );
      }
      reports.add(
        FoodPurchaseLineReport(
          purchase: purchaseId,
          product: state.catalog.resolve(existing.product),
          status: FoodPurchaseLineStatus.present,
          matched: const [],
          created: const [],
        ),
      );
      continue;
    }
    String root;
    var created = false;
    if (line.product != null) {
      root = state.catalog.resolve(line.product!);
      if (!state.products.containsKey(root) &&
          !newProducts.containsValue(root)) {
        throw FormatException('Unknown product ${line.product}.');
      }
    } else {
      final details = FoodDetails(
        name: line.name!,
        brand: line.brand,
        size: line.size,
      );
      final key = foodDescriptionKey(details.name, details.brand, details.size);
      final planned = newProducts[key];
      if (planned != null) {
        root = planned;
      } else {
        final add = planFoodAdd(
          state,
          details,
          newId: () => const Uuid().v5(
            foodProductNamespace,
            'tandemlog:food-product:import:v1\n$purchaseId',
          ),
        );
        root =
            add.product ??
            state.catalog.resolve(implicitFoodProductId(details));
        if (add.create != null) {
          steps.add(FoodImportProduct(root, add.create!));
          created = true;
        }
        if (!state.products.containsKey(root)) {
          newProducts[key] = root;
          created = true;
        }
      }
    }
    final values = {
      'product': root,
      'date': line.date,
      'store': line.store,
      'amount': line.amount,
      'currency': line.currency,
      'quantity': line.quantity,
      'source': line.source,
    };
    if (line.link != null) {
      final links =
          edited[root] ??
          List.of(state.products[root]?.links ?? const <String>[]);
      if (!links.contains(line.link) && links.length < maximumProductLinks) {
        links.add(line.link!);
        edited[root] = links;
      }
    }
    final purchased = DateTime.parse('${line.date}T00:00:00Z');
    final from = purchased.subtract(
      const Duration(days: purchaseMatchDaysBefore),
    );
    final to = purchased.add(const Duration(days: purchaseMatchDaysAfter + 1));
    final candidates =
        state.containers.where((c) {
          if (c.product != root ||
              c.purchase != null ||
              claimed.contains(c.id)) {
            return false;
          }
          final at = DateTime.tryParse(c.createdAt)?.toUtc();
          return at != null && !at.isBefore(from) && at.isBefore(to);
        }).toList()..sort((a, b) {
          final time = DateTime.parse(
            a.createdAt,
          ).compareTo(DateTime.parse(b.createdAt));
          return time != 0 ? time : a.id.compareTo(b.id);
        });
    final matched = [for (final c in candidates.take(line.quantity)) c.id];
    claimed.addAll(matched);
    final fresh = [
      for (var i = 0; i < line.quantity - matched.length; i++)
        importedFoodContainerId(purchaseId, i),
    ];
    steps.add(FoodImportPurchase(purchaseId, values));
    for (var i = 0; i < matched.length; i += 100) {
      steps.add(
        FoodImportLink(
          matched.sublist(i, (i + 100).clamp(0, matched.length)),
          purchaseId,
        ),
      );
    }
    final product = state.products[root];
    final details = FoodDetails(
      name: product?.name ?? line.name!,
      brand: product?.brand ?? line.brand,
      size: product?.size ?? line.size,
    );
    for (var i = 0; i < fresh.length; i += 100) {
      steps.add(
        FoodImportCreate(
          fresh.sublist(i, (i + 100).clamp(0, fresh.length)),
          details,
          root,
          purchaseId,
        ),
      );
    }
    reports.add(
      FoodPurchaseLineReport(
        purchase: purchaseId,
        product: root,
        status: FoodPurchaseLineStatus.recorded,
        matched: matched,
        created: fresh,
        newProduct: created,
      ),
    );
  }
  for (final MapEntry(key: product, value: links) in edited.entries) {
    steps.insert(
      0,
      FoodImportProduct(product, {
        if (!state.catalog.products.containsKey(product) &&
            state.products[product] != null) ...{
          'name': state.products[product]!.name,
          'brand': state.products[product]!.brand,
          'size': state.products[product]!.size,
        },
        'links': links,
      }),
    );
  }
  final recorded = reports.any(
    (r) => r.status == FoodPurchaseLineStatus.recorded,
  );
  return (
    report: FoodPurchaseImportReport(
      recorded
          ? FoodPurchaseImportStatus.ready
          : FoodPurchaseImportStatus.committed,
      plan.planHash,
      reports,
    ),
    steps: recorded ? steps : const [],
  );
}
