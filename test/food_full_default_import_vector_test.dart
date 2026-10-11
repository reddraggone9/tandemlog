import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_import.dart';
import 'package:tandemlog/food/inventory.dart';

Map<String, dynamic> _expected() =>
    jsonDecode(
          File(
            'test/fixtures/food-import/expected-v1-full-default.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

FoodImportPlan _plan() => FoodImportPlan.decode(
  File(
    'test/fixtures/food-import/plan-v1-full-default.json',
  ).readAsStringSync(),
);

void main() {
  test(
    'Full-default v1 import matches independent canonical/hash/UUID vector',
    () {
      final plan = _plan(), expected = _expected();
      expect(plan.targetIds, expected['targetIds']);
      expect(plan.planHash, expected['planHash']);
      expect(plan.canonicalJson, expected['canonicalJson']);
      expect(
        plan.sourceSha256,
        sha256
            .convert(utf8.encode(expected['sourceBytesUtf8'] as String))
            .toString(),
      );
      final container = plan.containers.single;
      expect(container.contents.full, isTrue);
      expect(container.contents.toJson(), {
        'numerator': 1,
        'denominator': 1,
        'unit': null,
      });
      expect(container.details.size, isEmpty);
      expect(container.details.estimated, isNull);
      expect(container.createdAt, '2020-01-02T03:04:05+02:00');
    },
  );

  test(
    'omitted builder contents defaults Full without inferring nominal size',
    () {
      final plan = _plan(), source = plan.containers.single;
      final defaulted = FoodImportContainer(
        sourceId: source.sourceId,
        ordinal: source.ordinal,
        details: source.details,
        createdAt: source.createdAt,
      );
      expect(defaulted.toJson(), source.toJson());
      final rebuilt = FoodImportPlan(
        space: plan.space,
        importId: plan.importId,
        sourceSha256: plan.sourceSha256,
        containers: [defaulted],
      );
      expect(rebuilt.planHash, _expected()['planHash']);
      expect(rebuilt.targetIds, _expected()['targetIds']);
      expect(rebuilt.canonicalJson, _expected()['canonicalJson']);
    },
  );

  test(
    'Full vector replays deterministically with its independently bound identity',
    () {
      const writer = '00000000-0000-4000-8000-000000000010';
      final plan = _plan(), container = plan.containers.single;
      final addition = FoodOperation(
        id: '$writer:1',
        order: 1,
        action: FoodAction.add,
        targets: plan.targetIds,
        details: container.details,
        contents: container.contents,
        createdAt: container.createdAt,
      );
      final edit = FoodOperation(
        id: '$writer:2',
        order: 2,
        action: FoodAction.edit,
        targets: plan.targetIds,
        contents: const Contents.fraction(1, 3),
      );
      final state = projectFood([addition, edit]);
      final duplicateReordered = projectFood([edit, addition, edit, addition]);
      expect(
        duplicateReordered.containers.map((e) => e.toJson()).toList(),
        state.containers.map((e) => e.toJson()).toList(),
      );
      expect(
        state.containers.single.id,
        (_expected()['targetIds'] as List).single,
      );
      expect(state.containers.single.contents.label, '⅓ remaining');
      expect(state.containers.single.details.size, isEmpty);
      expect(projectFood([addition]).containers.single.contents.full, isTrue);
      expect(
        FoodOperation.fromJson(addition.toJson()).toJson(),
        addition.toJson(),
      );
      expect(
        FoodImportPlan.decode(plan.canonicalJson).canonicalJson,
        plan.canonicalJson,
      );
    },
  );

  test(
    'explicit fractions and measured amounts remain exact with blank size',
    () {
      final source = _plan().containers.single;
      for (final contents in [
        const Contents.fraction(2, 6),
        const Contents.amount(2, 6, 'L'),
      ]) {
        final container = FoodImportContainer(
          sourceId: source.sourceId,
          ordinal: source.ordinal,
          details: source.details,
          contents: contents,
          createdAt: source.createdAt,
        );
        expect(container.contents.toJson(), {
          'numerator': 1,
          'denominator': 3,
          'unit': contents.unit,
        });
        expect(container.contents.full, isFalse);
        expect(container.details.size, isEmpty);
        expect(
          FoodImportContainer.fromJson(container.toJson()).toJson(),
          container.toJson(),
        );
      }
    },
  );

  test(
    'an Add without a contents edit projects Full without rewriting its payload',
    () {
      final plan = _plan(), container = plan.containers.single;
      final addition = FoodOperation(
        id: '00000000-0000-4000-8000-000000000010:1',
        order: 1,
        action: FoodAction.add,
        targets: plan.targetIds,
        details: container.details,
        createdAt: container.createdAt,
      );
      final before = addition.toJson();
      expect(projectFood([addition]).containers.single.contents.full, isTrue);
      expect(addition.contents, isNull);
      expect(addition.toJson(), before);
    },
  );
}
