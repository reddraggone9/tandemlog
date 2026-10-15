/// A visible insertion gap and its existing v3 global `before` anchor.
/// Hidden rows keep their relative order; only the moving block is relocated.
class VisibleTaskMovePlan {
  const VisibleTaskMovePlan({
    required this.before,
    required this.visibleBefore,
    required this.visibleAfter,
    required this.noOp,
  });

  final String? before;
  final String? visibleBefore;
  final String? visibleAfter;
  final bool noOp;

  /// Revalidation compares the gap, independently of partially applied moves.
  bool sameGap(VisibleTaskMovePlan other) =>
      before == other.before &&
      visibleBefore == other.visibleBefore &&
      visibleAfter == other.visibleAfter;
}

/// [visibleOrder] contains one eligible reorder bucket in global relative order.
/// Callers own projection and bucket validation, including at the write boundary.
VisibleTaskMovePlan? resolveVisibleTaskMove({
  required List<String> globalOrder,
  required List<String> visibleOrder,
  required Set<String> moving,
  required String target,
  required bool after,
}) {
  final globalIds = globalOrder.toSet(), visibleIds = visibleOrder.toSet();
  if (moving.isEmpty ||
      globalIds.length != globalOrder.length ||
      visibleIds.length != visibleOrder.length ||
      !globalIds.containsAll(visibleIds) ||
      !visibleIds.containsAll(moving) ||
      !visibleIds.contains(target) ||
      moving.contains(target)) {
    return null;
  }
  bool equal(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
  if (!equal(globalOrder.where(visibleIds.contains).toList(), visibleOrder)) {
    return null;
  }
  final remaining = visibleOrder.where((id) => !moving.contains(id)).toList();
  final slot = remaining.indexOf(target) + (after ? 1 : 0);
  final later = slot < remaining.length ? remaining[slot] : null;
  final earlier = slot > 0 ? remaining[slot - 1] : null;
  final globalRemaining = globalOrder
      .where((id) => !moving.contains(id))
      .toList();
  final lastIndex = earlier == null ? -1 : globalRemaining.indexOf(earlier);
  final before =
      later ??
      (lastIndex + 1 < globalRemaining.length
          ? globalRemaining[lastIndex + 1]
          : null);
  final result = [...remaining]
    ..insertAll(slot, globalOrder.where(moving.contains));
  return VisibleTaskMovePlan(
    before: before,
    visibleBefore: later,
    visibleAfter: earlier,
    noOp: equal(result, visibleOrder),
  );
}
