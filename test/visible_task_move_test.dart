import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/visible_task_move.dart';

VisibleTaskMovePlan plan(
  List<String> global,
  List<String> visible,
  Set<String> moving,
  String target,
  bool after,
) => resolveVisibleTaskMove(
  globalOrder: global,
  visibleOrder: visible,
  moving: moving,
  target: target,
  after: after,
)!;

List<String> apply(
  List<String> global,
  Set<String> moving,
  VisibleTaskMovePlan plan,
) {
  if (plan.noOp) return [...global];
  final block = global.where(moving.contains).toList();
  final result = global.where((id) => !moving.contains(id)).toList();
  result.insertAll(
    plan.before == null ? result.length : result.indexOf(plan.before!),
    block,
  );
  return result;
}

void main() {
  for (final hidden in [
    <String>[],
    ['completed'],
    ['assignee'],
    ['tag'],
    ['h1', 'h2'],
  ]) {
    test('both halves save before later visible row with hidden $hidden', () {
      final global = ['source', 'a', ...hidden, 'b', 'c'];
      final upper = plan(
        global,
        ['source', 'a', 'b', 'c'],
        {'source'},
        'a',
        true,
      );
      final lower = plan(
        global,
        ['source', 'a', 'b', 'c'],
        {'source'},
        'b',
        false,
      );
      expect(upper.before, 'b');
      expect(upper.visibleBefore, 'b');
      expect(upper.visibleAfter, 'a');
      expect(upper.sameGap(lower), isTrue);
      expect(upper.noOp, isFalse);
      expect(apply(global, {'source'}, upper), [
        'a',
        ...hidden,
        'source',
        'b',
        'c',
      ]);
      expect(
        apply(global, {'source'}, lower),
        apply(global, {'source'}, upper),
      );
    });
  }
  test('start goes immediately before first eligible visible row', () {
    final global = ['hidden-start', 'a', 'b', 'source', 'other-bucket'];
    final p = plan(global, ['a', 'b', 'source'], {'source'}, 'a', false);
    expect(p.before, 'a');
    expect(p.visibleAfter, isNull);
    expect(apply(global, {'source'}, p), [
      'hidden-start',
      'source',
      'a',
      'b',
      'other-bucket',
    ]);
  });
  test(
    'bucket end uses first non-moving global successor, never absolute end',
    () {
      final global = ['source', 'a', 'b', 'hidden-tail', 'other-bucket'];
      final p = plan(global, ['source', 'a', 'b'], {'source'}, 'b', true);
      expect(p.before, 'hidden-tail');
      expect(p.visibleBefore, isNull);
      expect(p.visibleAfter, 'b');
      expect(apply(global, {'source'}, p), [
        'a',
        'b',
        'source',
        'hidden-tail',
        'other-bucket',
      ]);
    },
  );
  test('true global end has a valid null anchor', () {
    final p = plan(['source', 'a'], ['source', 'a'], {'source'}, 'a', true);
    expect(p.before, isNull);
    expect(p.noOp, isFalse);
  });
  test('end skips all moving rows when finding global successor', () {
    final global = ['s1', 'a', 'b', 's2', 'hidden-tail'];
    final p = plan(global, ['s1', 'a', 'b', 's2'], {'s2', 's1'}, 'b', true);
    expect(p.before, 'hidden-tail');
    expect(apply(global, {'s2', 's1'}, p), [
      'a',
      'b',
      's1',
      's2',
      'hidden-tail',
    ]);
  });
  for (final moving in [
    {'s2', 's1'},
    {'s1', 's2'},
  ]) {
    test('noncontiguous block preserves global order, selection $moving', () {
      final global = ['s1', 'h1', 'a', 's2', 'h2', 'b', 'c'];
      final upper = plan(
        global,
        ['s1', 'a', 's2', 'b', 'c'],
        moving,
        'a',
        true,
      );
      final lower = plan(
        global,
        ['s1', 'a', 's2', 'b', 'c'],
        moving,
        'b',
        false,
      );
      expect(upper.sameGap(lower), isTrue);
      expect(apply(global, moving, upper), [
        'h1',
        'a',
        'h2',
        's1',
        's2',
        'b',
        'c',
      ]);
    });
  }
  for (final after in [false, true]) {
    test(
      'visible unchanged drop is no-op despite hidden-only movement $after',
      () {
        final global = ['a', 'hidden1', 'source', 'hidden2', 'b'];
        final p = plan(
          global,
          ['a', 'source', 'b'],
          {'source'},
          after ? 'a' : 'b',
          after,
        );
        expect(p.noOp, isTrue);
        expect(apply(global, {'source'}, p), global);
      },
    );
  }
  test('no-op at bucket start/end preserves hidden relative placement', () {
    final g = ['h0', 's1', 'h1', 's2', 'h2', 'a', 'h3'];
    final p = plan(g, ['s1', 's2', 'a'], {'s2', 's1'}, 'a', false);
    expect(p.noOp, isTrue);
    expect(apply(g, {'s1', 's2'}, p), g);
    expect(
      plan(
        ['a', 'h', 'source', 'tail'],
        ['a', 'source'],
        {'source'},
        'a',
        true,
      ).noOp,
      isTrue,
    );
  });
  test(
    'fresh gap rejects inferred anchor disappearing without canonical changes',
    () {
      final g = ['source', 'a', 'b', 'c'];
      final original = plan(g, g, {'source'}, 'a', true);
      final changed = plan(g, ['source', 'a', 'c'], {'source'}, 'a', true);
      expect(original.sameGap(changed), isFalse);
      // Partial application can change no-op status without changing the gap.
      final applied = plan(
        ['a', 'source', 'b', 'c'],
        ['a', 'source', 'b', 'c'],
        {'source'},
        'a',
        true,
      );
      expect(applied.noOp, isTrue);
      expect(original.sameGap(applied), isTrue);
    },
  );
  test(
    'malformed or selected targets do not yield a valid global-end plan',
    () {
      VisibleTaskMovePlan? resolve(
        List<String> g,
        List<String> v,
        Set<String> m,
        String t,
      ) => resolveVisibleTaskMove(
        globalOrder: g,
        visibleOrder: v,
        moving: m,
        target: t,
        after: true,
      );
      expect(resolve(['s', 'a', 'a'], ['s', 'a'], {'s'}, 'a'), isNull);
      expect(resolve(['s', 'a'], ['s', 'a', 'a'], {'s'}, 'a'), isNull);
      expect(resolve(['s', 'a'], ['a', 's'], {'s'}, 'a'), isNull);
      expect(resolve(['s', 'a'], ['s', 'a'], {}, 'a'), isNull);
      expect(resolve(['s', 'a'], ['s', 'a'], {'absent'}, 'a'), isNull);
      expect(resolve(['s', 'a'], ['s', 'a'], {'s'}, 's'), isNull);
      expect(resolve(['s', 'a'], ['s', 'a'], {'s'}, 'absent'), isNull);
    },
  );
}
