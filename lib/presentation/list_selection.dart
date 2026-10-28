import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How one row activation asks to change a Tasks or Food multi-selection.
enum SelectionGesture {
  /// Plain click/tap: toggles while selecting, otherwise the row's own action.
  plain,

  /// Ctrl/Cmd-click: toggles the row and keeps explicit selection intent.
  toggle,

  /// Shift-click or Shift+Arrow: selects the visible range from the anchor.
  range,

  /// Long press, Space, Select actions: starts selection with only this row,
  /// or toggles it while already selecting.
  longPress,
}

/// Reads the modifiers held during a pointer activation. Shift wins over
/// Ctrl/Cmd, as in Tasks since RC4.
SelectionGesture pointerSelectionGesture() {
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isShiftPressed) return SelectionGesture.range;
  if (keyboard.isControlPressed || keyboard.isMetaPressed) {
    return SelectionGesture.toggle;
  }
  return SelectionGesture.plain;
}

@immutable
class ListSelection<K> {
  const ListSelection(this.selected, {required this.selecting, this.anchor});
  final Set<String> selected;

  /// Explicit multi-selection intent; false means the plain single-row action.
  final bool selecting;
  final K? anchor;
}

/// Shared Tasks/Food selection rules. A row ([K]) owns one or more selectable
/// IDs: one task, or every observed container of a Food group. Callers own
/// visibility checks, editors and any layout-specific intent changes.
ListSelection<K> nextListSelection<K>({
  required Set<String> selected,
  required bool selecting,
  required K? anchor,
  required K target,
  required List<K> order,
  required Iterable<String> Function(K row) members,
  required SelectionGesture gesture,
}) {
  final next = Set<String>.of(selected);
  final ids = members(target).toSet();
  var intent = selecting;
  var nextAnchor = anchor;
  if (gesture == SelectionGesture.range) {
    final from = order.indexOf(anchor ?? target), to = order.indexOf(target);
    next.clear();
    if (from >= 0 && to >= 0) {
      for (final row in order.sublist(
        from < to ? from : to,
        (from > to ? from : to) + 1,
      )) {
        next.addAll(members(row));
      }
    } else {
      next.addAll(ids);
      nextAnchor = target;
    }
    intent = true;
  } else if (gesture == SelectionGesture.longPress && !selecting) {
    next
      ..clear()
      ..addAll(ids);
    intent = true;
    nextAnchor = target;
  } else if (gesture != SelectionGesture.plain || selecting) {
    if (ids.every(next.contains)) {
      next.removeAll(ids);
    } else {
      next.addAll(ids);
    }
    intent = true;
    nextAnchor = target;
  } else {
    next
      ..clear()
      ..addAll(ids);
    intent = false;
    nextAnchor = target;
  }
  if (next.isEmpty) intent = false;
  return ListSelection(next, selecting: intent, anchor: nextAnchor);
}
