import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/food/food_import.dart';

void main() {
  test(
    'unprovided contents defaults to Full without asserting container size',
    () {
      final state = projectFood([
        FoodOperation(
          id: '00000000-0000-4000-8000-000000000050:1',
          order: 1,
          action: FoodAction.add,
          targets: ['00000000-0000-4000-8000-000000000901'],
          details: const FoodDetails(name: 'Synthetic food'),
          createdAt: '2026-10-11T00:00:00Z',
        ),
      ]);
      expect(state.active.single.contents.full, isTrue);
      expect(state.active.single.details.size, '');
    },
  );
  test(
    'import defaults Full and explicitly supplied partial remains partial',
    () {
      FoodImportContainer imported({Contents? contents}) => FoodImportContainer(
        sourceId: 'synthetic',
        ordinal: 1,
        details: const FoodDetails(name: 'Synthetic food'),
        createdAt: '2026-10-11T00:00:00Z',
        contents: contents ?? const Contents.fraction(1, 1),
      );
      final defaultImport = FoodImportContainer(
        sourceId: 'default',
        ordinal: 1,
        details: const FoodDetails(name: 'Synthetic default'),
        createdAt: '2026-10-11T00:00:00Z',
      );
      expect(defaultImport.contents.full, isTrue);
      expect(imported().contents.full, isTrue);
      expect(
        imported(contents: const Contents.fraction(1, 2)).contents.label,
        '½ remaining',
      );
    },
  );
  test(
    'all-null development payload is rejected rather than rehashed as Full',
    () {
      expect(
        () => Contents.fromJson({
          'numerator': null,
          'denominator': null,
          'unit': null,
        }),
        throwsFormatException,
      );
      for (final value in [
        const Contents.fraction(1, 2),
        const Contents.fraction(1, 4),
        const Contents.amount(3, 2, 'cups'),
      ]) {
        expect(Contents.fromJson(value.toJson()).toJson(), value.toJson());
      }
    },
  );
}
