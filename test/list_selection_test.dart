import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/list_selection.dart';

// Rows a..d; row b owns two IDs, as a Food group of two containers does.
const _order = ['a', 'b', 'c', 'd'];
Iterable<String> _members(String row) => row == 'b' ? ['b1', 'b2'] : [row];

ListSelection<String> _next(
  String target,
  SelectionGesture gesture, {
  Set<String> selected = const {},
  bool selecting = false,
  String? anchor,
}) => nextListSelection<String>(
  selected: selected,
  selecting: selecting,
  anchor: anchor,
  target: target,
  order: _order,
  members: _members,
  gesture: gesture,
);

void main() {
  test('plain without selection is the single-row action', () {
    final result = _next('b', SelectionGesture.plain);
    expect(result.selected, {'b1', 'b2'});
    expect(result.selecting, isFalse);
    expect(result.anchor, 'b');
  });

  test('long press starts with only the row, then toggles', () {
    var result = _next(
      'c',
      SelectionGesture.longPress,
      selected: {'a'},
      anchor: 'a',
    );
    expect(result.selected, {'c'});
    expect(result.selecting, isTrue);
    result = _next(
      'b',
      SelectionGesture.longPress,
      selected: result.selected,
      selecting: true,
      anchor: 'c',
    );
    expect(result.selected, {'b1', 'b2', 'c'});
  });

  test('toggle adds, removes whole rows and exits when empty', () {
    var result = _next('b', SelectionGesture.toggle);
    expect(result.selected, {'b1', 'b2'});
    expect(result.selecting, isTrue);
    // A partially selected row is completed before it can be removed.
    result = _next(
      'b',
      SelectionGesture.toggle,
      selected: {'b1'},
      selecting: true,
    );
    expect(result.selected, {'b1', 'b2'});
    result = _next(
      'b',
      SelectionGesture.plain,
      selected: result.selected,
      selecting: true,
    );
    expect(result.selected, isEmpty);
    expect(result.selecting, isFalse);
  });

  test('range replaces the selection from the anchor and keeps it', () {
    final result = _next(
      'd',
      SelectionGesture.range,
      selected: {'a', 'x'},
      selecting: true,
      anchor: 'b',
    );
    expect(result.selected, {'b1', 'b2', 'c', 'd'});
    expect(result.anchor, 'b');
    final backwards = _next('a', SelectionGesture.range, anchor: 'c');
    expect(backwards.selected, {'a', 'b1', 'b2', 'c'});
    expect(backwards.selecting, isTrue);
  });

  test('range without a visible anchor selects only the target', () {
    final result = _next('c', SelectionGesture.range, anchor: 'gone');
    expect(result.selected, {'c'});
    expect(result.anchor, 'c');
  });
}
