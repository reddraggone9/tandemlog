import '../domain/event.dart' show isCanonicalId;
import '../domain/event_chain.dart' show canonicalDataJson;

enum FoodAction { add, edit, remove, restore }

enum FoodView { inventory, inbox, retained, deleted }

/// Descriptive grouping never replaces physical container identity.
class FoodDetails {
  const FoodDetails({
    required this.name,
    this.brand = '',
    this.expiry,
    this.estimated = false,
    this.retention = '',
    this.location = '',
    this.size = '',
  });
  final String name, brand, retention, location, size;
  final String? expiry;
  final bool? estimated;
  Map<String, dynamic> toJson() => {
    'name': name,
    'brand': brand,
    'expiry': expiry,
    'estimated': estimated,
    'retention': retention,
    'location': location,
    'size': size,
  };
  String get groupKey => canonicalDataJson(toJson());
  void validate() {
    _text(name, 500, required: true);
    for (final value in [brand, retention, location, size]) {
      _text(value, 200);
    }
    if (expiry != null) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expiry!)) {
        _invalid('expiration');
      }
      final date = DateTime.tryParse(expiry!);
      if (date == null ||
          date.year.toString().padLeft(4, '0') != expiry!.substring(0, 4) ||
          date.month.toString().padLeft(2, '0') != expiry!.substring(5, 7) ||
          date.day.toString().padLeft(2, '0') != expiry!.substring(8, 10)) {
        _invalid('expiration');
      }
    }
  }

  factory FoodDetails.fromJson(Map<String, dynamic> j) {
    _keys(j, {
      'name',
      'brand',
      'expiry',
      'estimated',
      'retention',
      'location',
      'size',
    });
    if ((j['estimated'] != null && j['estimated'] is! bool) ||
        (j['expiry'] != null && j['expiry'] is! String)) {
      _invalid('details');
    }
    final value = FoodDetails(
      name: _string(j['name']),
      brand: _string(j['brand']),
      expiry: j['expiry'] as String?,
      estimated: j['estimated'] as bool?,
      retention: _string(j['retention']),
      location: _string(j['location']),
      size: _string(j['size']),
    );
    value.validate();
    return value;
  }
}

/// Exact rational contents. Unknown is distinct from full; no unit conversion.
class Contents {
  const Contents.unknown() : numerator = null, denominator = null, unit = null;
  const Contents.fraction(int this.numerator, int this.denominator)
    : unit = null;
  const Contents.amount(
    int this.numerator,
    int this.denominator,
    String this.unit,
  );
  final int? numerator, denominator;
  final String? unit;
  bool get full =>
      unit == null && numerator != null && numerator == denominator;
  bool get unknown => numerator == null;
  void validate() {
    if (unknown) {
      if (denominator != null || unit != null) _invalid('unknown contents');
      return;
    }
    if (numerator! < 0 ||
        numerator! > 1000000000 ||
        denominator == null ||
        denominator! < 1 ||
        denominator! > 1000000 ||
        (unit == null && numerator! > denominator!)) {
      _invalid('contents');
    }
    if (unit != null) _text(unit!, 40, required: true);
  }

  Map<String, dynamic> toJson() => {
    'numerator': numerator == null
        ? null
        : numerator! ~/ numerator!.gcd(denominator!),
    'denominator': numerator == null
        ? null
        : denominator! ~/ numerator!.gcd(denominator!),
    'unit': unit,
  };
  String get label {
    if (unknown) return 'Unspecified contents';
    if (full) return 'Full';
    final reduced = toJson(),
        n = reduced['numerator'] as int,
        d = reduced['denominator'] as int;
    final amount = n == 0
        ? '0'
        : n == d
        ? '1'
        : d == 1
        ? '$n'
        : switch ((n, d)) {
            (1, 2) => '½',
            (1, 3) => '⅓',
            (2, 3) => '⅔',
            (1, 4) => '¼',
            (3, 4) => '¾',
            _ => '$n/$d',
          };
    return unit == null ? '$amount remaining' : '$amount $unit remaining';
  }

  factory Contents.fromJson(Map<String, dynamic> j) {
    _keys(j, {'numerator', 'denominator', 'unit'});
    if (j['numerator'] == null) {
      final v = const Contents.unknown();
      if (j['denominator'] != null || j['unit'] != null) _invalid('contents');
      return v;
    }
    if (j['numerator'] is! int ||
        j['denominator'] is! int ||
        (j['unit'] != null && j['unit'] is! String)) {
      _invalid('contents');
    }
    final v = j['unit'] == null
        ? Contents.fraction(j['numerator'] as int, j['denominator'] as int)
        : Contents.amount(
            j['numerator'] as int,
            j['denominator'] as int,
            j['unit'] as String,
          );
    v.validate();
    return v;
  }
}

/// Absolute contents edits carry observed edit IDs; concurrent alternatives are
/// retained for explicit resolution instead of silently treating them as stock.
class FoodOperation {
  FoodOperation({
    required this.id,
    required this.order,
    required this.action,
    required List<String> targets,
    this.details,
    this.contents,
    this.createdAt,
    List<String> observedDeletes = const [],
    List<String> observedEdits = const [],
    List<String>? fields,
  }) : targets = List.unmodifiable(targets),
       observedDeletes = List.unmodifiable(observedDeletes),
       observedEdits = List.unmodifiable(observedEdits),
       fields = List.unmodifiable(
         fields ??
             (action == FoodAction.edit && details != null
                 ? details.toJson().keys.toList()
                 : <String>[]),
       );
  final String id;
  final int order;
  final FoodAction action;
  final List<String> targets, observedDeletes, observedEdits;
  final List<String> fields;
  final FoodDetails? details;
  final Contents? contents;
  final String? createdAt;
  void validate() {
    _reference(id);
    if (order < 0 ||
        targets.isEmpty ||
        targets.length > 100 ||
        targets.toSet().length != targets.length ||
        targets.any((id) => !isCanonicalId(id))) {
      _invalid('container targets');
    }
    details?.validate();
    contents?.validate();
    if (fields.toSet().length != fields.length ||
        fields.any(
          (key) => !const {
            'name',
            'brand',
            'expiry',
            'estimated',
            'retention',
            'location',
            'size',
          }.contains(key),
        ) ||
        (fields.isNotEmpty && (action != FoodAction.edit || details == null)) ||
        (action == FoodAction.edit && details != null && fields.isEmpty) ||
        (observedEdits.isNotEmpty && contents == null)) {
      _invalid('edit fields');
    }
    if (action == FoodAction.add) {
      if (details == null ||
          createdAt == null ||
          createdAt!.length > 64 ||
          DateTime.tryParse(createdAt!) == null) {
        _invalid('creation');
      }
    } else if (createdAt != null) {
      _invalid('creation field');
    }
    if (action == FoodAction.edit && details == null && contents == null) {
      _invalid('empty edit');
    }
    if ((action == FoodAction.remove || action == FoodAction.restore) &&
        (details != null || contents != null)) {
      _invalid('deletion payload');
    }
    if (action != FoodAction.restore && observedDeletes.isNotEmpty) {
      _invalid('restore references');
    }
    if (action == FoodAction.restore && observedDeletes.isEmpty) {
      _invalid('empty restore');
    }
    if (action != FoodAction.edit && observedEdits.isNotEmpty) {
      _invalid('edit references');
    }
    for (final refs in [observedDeletes, observedEdits]) {
      if (refs.length > 1000 || refs.toSet().length != refs.length) {
        _invalid('references');
      }
      for (final ref in refs) {
        _reference(ref);
        final left = id.split(':'), right = ref.split(':');
        if (left.first == right.first &&
            int.parse(right.last) >= int.parse(left.last)) {
          _invalid('forward reference');
        }
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'order': order.toString(),
    'action': action.name,
    'targets': targets,
    'details': details?.toJson(),
    'contents': contents?.toJson(),
    'createdAt': createdAt,
    'observedDeletes': observedDeletes,
    'observedEdits': observedEdits,
    'fields': fields,
  };
  factory FoodOperation.fromJson(Map<String, dynamic> j) {
    _keys(j, {
      'id',
      'order',
      'action',
      'targets',
      'details',
      'contents',
      'createdAt',
      'observedDeletes',
      'observedEdits',
      'fields',
    });
    try {
      if (j['order'] is! String ||
          !RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(j['order'])) {
        _invalid('clock');
      }
      final v = FoodOperation(
        id: _string(j['id']),
        order: int.parse(j['order'] as String),
        action: FoodAction.values.byName(_string(j['action'])),
        targets: _strings(j['targets']),
        details: j['details'] == null
            ? null
            : FoodDetails.fromJson(_map(j['details'])),
        contents: j['contents'] == null
            ? null
            : Contents.fromJson(_map(j['contents'])),
        createdAt: j['createdAt'] == null ? null : _string(j['createdAt']),
        observedDeletes: _strings(j['observedDeletes']),
        observedEdits: _strings(j['observedEdits']),
        fields: _strings(j['fields']),
      );
      v.validate();
      return v;
    } on FormatException {
      rethrow;
    } catch (_) {
      _invalid('operation');
    }
  }
}

class FoodContainer {
  FoodContainer({
    required this.id,
    required this.details,
    required this.contents,
    required this.createdAt,
    required Set<String> deletions,
    required this.deletedOrder,
    this.lastDeletionId,
    required Map<String, Contents> contentsEdits,
  }) : deletions = Set.unmodifiable(deletions),
       contentsEdits = Map.unmodifiable(contentsEdits);
  final String id, createdAt;
  final FoodDetails details;
  final Contents contents;
  final Set<String> deletions;
  final int deletedOrder;
  final String? lastDeletionId;
  final Map<String, Contents> contentsEdits;
  bool get deleted => deletions.isNotEmpty;
  bool get contentsConflict =>
      contentsEdits.values
          .map((v) => canonicalDataJson(v.toJson()))
          .toSet()
          .length >
      1;
  Map<String, dynamic> toJson() => {
    'id': id,
    'details': details.toJson(),
    'contents': contents.toJson(),
    'createdAt': createdAt,
    'deletions': deletions.toList()..sort(),
    'deletedOrder': deletedOrder,
    'lastDeletionId': lastDeletionId,
    'contentsEdits': contentsEdits.map((k, v) => MapEntry(k, v.toJson())),
  };
}

class FoodGroup {
  FoodGroup(List<FoodContainer> values)
    : containers = List.unmodifiable(values);
  final List<FoodContainer> containers;
  FoodDetails get details => containers.first.details;
  bool get contentsConflict => containers.any((e) => e.contentsConflict);
  String? get quickRemoveTarget =>
      !contentsConflict && containers.every((e) => e.contents.full)
      ? containers.first.id
      : null;
  String get summary {
    if (contentsConflict) {
      return '${containers.length} containers · contents need review';
    }
    if (containers.every((e) => e.contents.unknown)) {
      return '× ${containers.length}';
    }
    final full = containers.where((e) => e.contents.full).length;
    final rest = containers.where((e) => !e.contents.full).toList();
    if (rest.isEmpty) return '$full full';
    if (rest.length == 1 && !rest.first.contents.unknown) {
      return '${full > 0 ? '$full full + ' : ''}1 container ${rest.first.contents.unit == null ? rest.first.contents.label.replaceFirst(' remaining', ' full') : rest.first.contents.label}';
    }
    return '${containers.length} containers · ${full > 0 ? '$full full · ' : ''}inspect contents';
  }
}

class FoodState {
  FoodState(List<FoodContainer> containers)
    : containers = List.unmodifiable(containers);
  final List<FoodContainer> containers;
  List<FoodContainer> get active =>
      containers.where((e) => !e.deleted).toList();
  List<FoodContainer> get deleted =>
      containers.where((e) => e.deleted).toList();
  List<FoodGroup> get groups => _group(active);
  List<String> get reasons =>
      (active
          .map((e) => e.details.retention)
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort());
  List<FoodGroup> view(
    FoodView view, {
    String search = '',
    Set<String> reasons = const {},
  }) {
    final terms = search
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final values = (view == FoodView.deleted ? deleted : active).where((e) {
      if (terms.isNotEmpty) {
        final text = [
          e.details.name,
          e.details.brand,
          e.details.retention,
          e.details.location,
          e.details.size,
        ].join(' ').toLowerCase();
        return terms.every(text.contains);
      }
      return switch (view) {
        FoodView.inventory =>
          e.details.expiry != null && e.details.retention.isEmpty,
        FoodView.inbox => e.details.expiry == null,
        FoodView.retained =>
          e.details.retention.isNotEmpty &&
              (reasons.isEmpty || reasons.contains(e.details.retention)),
        FoodView.deleted => true,
      };
    });
    final result = _group(values);
    if (view == FoodView.deleted) {
      result.sort((a, b) {
        FoodContainer latest(FoodGroup group) => group.containers.reduce(
          (left, right) => _compareDeletions(left, right) >= 0 ? left : right,
        );
        final n = _compareDeletions(latest(b), latest(a));
        return n != 0
            ? n
            : a.containers.first.id.compareTo(b.containers.first.id);
      });
    }
    return result;
  }
}

FoodState projectFood(Iterable<FoodOperation> delivery) {
  final indexed = <String, FoodOperation>{};
  for (final op in delivery) {
    op.validate();
    final previous = indexed[op.id];
    if (previous != null &&
        canonicalDataJson(previous.toJson()) !=
            canonicalDataJson(op.toJson())) {
      _invalid('conflicting operation identity');
    }
    indexed[op.id] = op;
  }
  final events = indexed.values.toList()..sort(_compareFoodOperations);
  final targetSets = {for (final op in events) op.id: op.targets.toSet()};
  // Admission must not depend on whether a target's creation has arrived.
  for (final op in events) {
    for (final (refs, kind) in [
      (op.observedDeletes, FoodAction.remove),
      (op.observedEdits, FoodAction.edit),
    ]) {
      for (final ref in refs) {
        final before = indexed[ref];
        if (before != null &&
            (before.action != kind ||
                (kind == FoodAction.edit && before.contents == null) ||
                op.targets.any((id) => !targetSets[before.id]!.contains(id)) ||
                before.order >= op.order)) {
          _invalid('cross-container or noncausal reference');
        }
      }
    }
  }
  final result = <FoodContainer>[];
  final creations = <String, FoodOperation>{};
  final histories = <String, List<FoodOperation>>{};
  for (final op in events.where((e) => e.action != FoodAction.add)) {
    for (final id in op.targets) {
      histories.putIfAbsent(id, () => []).add(op);
    }
  }
  for (final op in events.where((e) => e.action == FoodAction.add)) {
    for (final id in op.targets) {
      final prior = creations[id];
      if (prior != null &&
          (prior.details!.groupKey != op.details!.groupKey ||
              prior.createdAt != op.createdAt ||
              canonicalDataJson(prior.contents?.toJson()) !=
                  canonicalDataJson(op.contents?.toJson()))) {
        _invalid('conflicting container creation');
      }
      creations.putIfAbsent(id, () => op);
    }
  }
  for (final entry in creations.entries) {
    final id = entry.key, seed = entry.value;
    var details = seed.details!,
        contents = seed.contents ?? const Contents.unknown(),
        deletedOrder = 0;
    final deletions = <String>{},
        restored = <String>{},
        edits = <String, Contents>{},
        dominated = <String>{};
    for (final op in histories[id] ?? <FoodOperation>[]) {
      if (op.order <= seed.order) {
        _invalid('mutation before container creation');
      }
      if (op.action == FoodAction.edit) {
        if (op.details != null) {
          final merged = details.toJson(), changed = op.details!.toJson();
          for (final field in op.fields) {
            merged[field] = changed[field];
          }
          details = FoodDetails.fromJson(merged);
        }
        if (op.contents != null) {
          for (final ref in op.observedEdits) {
            dominated.add(ref);
          }
          edits[op.id] = op.contents!;
          contents = op.contents!;
        }
      } else if (op.action == FoodAction.remove) {
        deletions.add(op.id);
        deletedOrder = _max(deletedOrder, op.order);
      } else if (op.action == FoodAction.restore) {
        for (final ref in op.observedDeletes) {
          restored.add(ref);
        }
      }
    }
    deletions.removeAll(restored);
    deletedOrder = deletions.isEmpty
        ? 0
        : deletions.map((ref) => indexed[ref]!.order).reduce(_max);
    edits.removeWhere((key, _) => dominated.contains(key));
    result.add(
      FoodContainer(
        id: id,
        details: details,
        contents: contents,
        createdAt: seed.createdAt!,
        deletions: deletions,
        deletedOrder: deletedOrder,
        lastDeletionId: deletions.isEmpty ? null : deletions.last,
        contentsEdits: edits,
      ),
    );
  }
  result.sort((a, b) => a.id.compareTo(b.id));
  return FoodState(result);
}

List<FoodGroup> _group(Iterable<FoodContainer> values) {
  final grouped = <String, List<FoodContainer>>{};
  for (final item in values) {
    grouped.putIfAbsent(item.details.groupKey, () => []).add(item);
  }
  final result = grouped.values
      .map((items) => FoodGroup(items..sort((a, b) => a.id.compareTo(b.id))))
      .toList();
  result.sort((a, b) {
    final date = (a.details.expiry ?? '9999-99-99').compareTo(
      b.details.expiry ?? '9999-99-99',
    );
    return date != 0 ? date : a.details.groupKey.compareTo(b.details.groupKey);
  });
  return result;
}

Never _invalid(String field) => throw FormatException('Invalid food $field.');
void _text(String value, int limit, {bool required = false}) {
  if (value.length > limit ||
      (required && value.trim().isEmpty) ||
      value.contains('\u0000')) {
    _invalid('text');
  }
}

void _reference(String ref) {
  final parts = ref.split(':');
  if (parts.length != 2 ||
      !isCanonicalId(parts.first) ||
      !RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(parts.last) ||
      int.parse(parts.last) > 9007199254740991) {
    _invalid('operation reference');
  }
}

void _keys(Map<String, dynamic> j, Set<String> keys) {
  if (j.length != keys.length || !j.keys.every(keys.contains)) {
    _invalid('fields');
  }
}

String _string(Object? v) {
  if (v is! String) _invalid('string');
  return v;
}

List<String> _strings(Object? v) {
  if (v is! List || v.any((e) => e is! String)) _invalid('list');
  return v.cast<String>();
}

Map<String, dynamic> _map(Object? v) {
  if (v is! Map<String, dynamic>) _invalid('object');
  return v;
}

int _max(int a, int b) => a > b ? a : b;
int _compareDeletions(FoodContainer a, FoodContainer b) {
  final order = a.deletedOrder.compareTo(b.deletedOrder);
  return order != 0
      ? order
      : _compareOperationIds(a.lastDeletionId!, b.lastDeletionId!);
}

int _compareOperationIds(String a, String b) {
  final left = a.split(':'), right = b.split(':');
  final writer = left.first.compareTo(right.first);
  return writer != 0
      ? writer
      : int.parse(left.last).compareTo(int.parse(right.last));
}

int _compareFoodOperations(FoodOperation a, FoodOperation b) {
  final order = a.order.compareTo(b.order);
  if (order != 0) return order;
  return _compareOperationIds(a.id, b.id);
}
