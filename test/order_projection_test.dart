import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/projection.dart';

void main() {
  test(
    'moving a legacy task below a native task uses both creation actions',
    () {
      expect(
        projectOrder(
          ['legacy', 'native'],
          const [
            OrderAction('legacy', 'task.created'),
            OrderAction('native', 'task.createdWithText'),
            OrderAction('legacy', 'task.moved'),
          ],
        ),
        ['native', 'legacy'],
      );
    },
  );

  test('native creation after a move keeps chronological manual ordering', () {
    expect(
      projectOrder(
        ['first', 'second', 'later'],
        const [
          OrderAction('first', 'task.createdWithText'),
          OrderAction('second', 'task.createdWithText'),
          OrderAction('first', 'task.moved'),
          OrderAction('later', 'task.createdWithText'),
        ],
      ),
      ['second', 'first', 'later'],
    );
  });
  test(
    'deferred moves, first successor seed and fallback retain exact order',
    () {
      expect(
        projectOrder(
          ['future', 'seed', 'orphan', 'first', 'second', 'child'],
          const [
            OrderAction('second', 'task.moved', before: 'first'),
            OrderAction('first', 'task.created'),
            OrderAction('second', 'task.createdWithText'),
            OrderAction(
              'first',
              'task.completedWithChecklist',
              successor: 'child',
            ),
            OrderAction('second', 'task.completedWithText', successor: 'child'),
            OrderAction('future', 'user.created'),
            OrderAction('future', 'task.moved', before: 'missing'),
            OrderAction('orphan', 'task.moved', before: 'child'),
          ],
        ),
        ['second', 'orphan', 'child', 'first', 'future', 'seed'],
      );
    },
  );

  test(
    'ordering matches the original oracle across mixed deferred histories',
    () {
      final random = Random(24801);
      for (var trial = 0; trial < 1000; trial++) {
        final ids = [for (var i = 0; i < 12; i++) 'id-$i'];
        final available = [
          for (final id in ids)
            if (random.nextBool()) id,
        ];
        if (random.nextBool() && available.isNotEmpty) {
          available.add(available.first);
        }
        available.shuffle(random);
        final actions = <OrderAction>[];
        for (var step = 0; step < 40; step++) {
          final entity = ids[random.nextInt(ids.length)];
          switch (random.nextInt(6)) {
            case 0:
              actions.add(OrderAction(entity, 'task.created'));
            case 1:
              actions.add(OrderAction(entity, 'user.created'));
            case 2:
              actions.add(OrderAction(entity, 'task.createdWithText'));
            case 3:
              final before = random.nextBool()
                  ? null
                  : ids[random.nextInt(ids.length)];
              if (before != entity) {
                actions.add(OrderAction(entity, 'task.moved', before: before));
              }
            case 4:
              final child = ids[random.nextInt(ids.length)];
              if (child != entity) {
                actions.add(
                  OrderAction(
                    entity,
                    'task.completedWithChecklist',
                    successor: child,
                  ),
                );
              }
            case 5:
              actions.add(OrderAction(entity, 'checklist.itemCreated'));
          }
        }
        expect(
          projectOrder(available, actions),
          _originalOrder(available, actions),
          reason: 'History $trial',
        );
      }
    },
  );
}

// Frozen pre-optimization compatibility oracle.
List<String> _originalOrder(
  Iterable<String> availableInCreationOrder,
  Iterable<OrderAction> actions,
) {
  final available = availableInCreationOrder.toSet();
  final ordered = <String>[];
  final pending = <(String, String?)>[];
  final seeded = <String>{};
  bool move(String entity, String? before) {
    if (!ordered.contains(entity) ||
        (before != null && !ordered.contains(before))) {
      return false;
    }
    ordered.remove(entity);
    ordered.insert(
      before == null ? ordered.length : ordered.indexOf(before),
      entity,
    );
    return true;
  }

  void settlePending() =>
      pending.removeWhere((action) => move(action.$1, action.$2));
  for (final action in actions) {
    if (isTaskCompletion(action.type)) {
      final next = action.successor;
      if (next == null || !seeded.add(next) || !available.contains(next)) {
        continue;
      }
      if (!ordered.contains(next)) ordered.add(next);
      if (!move(next, action.entity)) pending.add((next, action.entity));
      settlePending();
    } else if (action.type == 'task.moved') {
      if (!move(action.entity, action.before)) {
        pending.add((action.entity, action.before));
      }
    } else if ((action.type == 'task.created' ||
            action.type == 'task.createdWithText' ||
            action.type == 'user.created') &&
        available.contains(action.entity) &&
        !ordered.contains(action.entity)) {
      ordered.add(action.entity);
      settlePending();
    }
  }
  for (final id in available) {
    if (!ordered.contains(id)) ordered.add(id);
  }
  settlePending();
  return ordered;
}
