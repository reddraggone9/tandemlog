import 'package:flutter/foundation.dart';

import 'native_bridge.dart';

class EditorSession extends ChangeNotifier {
  EditorSession() : _bridge = NativeBridge() {
    reset();
  }
  final NativeBridge _bridge;
  bool editing = false;
  bool composing = false;
  bool canUndo = false;
  bool canRedo = false;
  int publishedLocalUpdates = 0;
  int _nextActor = 30;
  String committedA = '';
  String committedB = '';
  String draftText = '';
  final List<String> trace = [];

  Map<String, dynamic> _call(
    String op, [
    Map<String, dynamic> args = const {},
  ]) => _bridge.call(op, args);
  void _refresh(String action) {
    committedA = _call('read', {'name': 'a'})['text'] as String;
    committedB = _call('read', {'name': 'b'})['text'] as String;
    if (editing) draftText = _call('read', {'name': 'draft'})['text'] as String;
    trace.add(action);
    if (trace.length > 12) trace.removeAt(0);
    notifyListeners();
  }

  void reset() {
    _call('reset');
    final seed = _call('seed', {'text': 'A😀B'})['update'];
    _call('new', {'name': 'a', 'client': 10, 'seed': seed});
    _call('new', {'name': 'b', 'client': 20, 'seed': seed});
    editing = composing = canUndo = canRedo = false;
    publishedLocalUpdates = 0;
    _nextActor = 30;
    trace.clear();
    _refresh('Native seed/Unicode initialization passed');
  }

  void beginEdit() {
    if (editing) throw StateError('Already editing');
    _call('draft', {'name': 'draft', 'source': 'a', 'client': _nextActor++});
    editing = true;
    composing = false;
    _refresh('Captured private draft');
  }

  void setComposing(bool value) {
    if (!editing) throw StateError('No active draft');
    _call('composition', {'name': 'draft', 'active': value});
    if (composing != value) {
      composing = value;
      notifyListeners();
    }
  }

  void replaceDraft(String text) {
    if (!editing) throw StateError('No active draft');
    if (text == draftText) return;
    // Diff against private captured document, never received committed buffer.
    final old = draftText;
    var prefix = 0;
    while (prefix < old.length &&
        prefix < text.length &&
        old.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
      prefix++;
    }
    while (!_boundary(old, prefix) || !_boundary(text, prefix)) {
      prefix--;
    }
    var suffix = 0;
    while (suffix < old.length - prefix &&
        suffix < text.length - prefix &&
        old.codeUnitAt(old.length - 1 - suffix) ==
            text.codeUnitAt(text.length - 1 - suffix)) {
      suffix++;
    }
    while (!_boundary(old, old.length - suffix) ||
        !_boundary(text, text.length - suffix)) {
      suffix--;
    }
    _call('edit', {
      'name': 'draft',
      'index': prefix,
      'delete': old.length - prefix - suffix,
      'insert': text.substring(prefix, text.length - suffix),
    });
    _refresh('Private draft edit; published=$publishedLocalUpdates');
  }

  static bool _boundary(String text, int n) =>
      n == 0 ||
      n == text.length ||
      !(text.codeUnitAt(n - 1) >= 0xd800 &&
          text.codeUnitAt(n - 1) <= 0xdbff &&
          text.codeUnitAt(n) >= 0xdc00 &&
          text.codeUnitAt(n) <= 0xdfff);
  void remotePrefix() {
    final update = _call('edit', {
      'name': 'b',
      'index': 0,
      'delete': 0,
      'insert': 'REMOTE ',
    })['update'];
    _call('apply', {'name': 'a', 'update': update});
    _refresh('Remote prefix arrived; captured editor retained');
  }

  void save() {
    if (!editing) throw StateError('No active draft');
    final update = _call('save', {'name': 'draft', 'target': 'a'})['update'];
    _call('apply', {'name': 'b', 'update': update});
    publishedLocalUpdates++;
    editing = composing = false;
    canUndo = true;
    canRedo = false;
    _refresh('Save published one captured update batch');
  }

  void cancel() {
    if (!editing) throw StateError('No active draft');
    _call('cancel', {'name': 'draft'});
    editing = composing = false;
    _refresh('Cancel published no draft operations');
  }

  void undo() => _compensate('undo');
  void redo() => _compensate('redo');
  void _compensate(String op) {
    if (editing) throw StateError('Close draft before Undo/Redo');
    final result = _call(op, {'name': 'a'});
    _call('apply', {'name': 'b', 'update': result['update']});
    canUndo = op == 'redo' && result['changed'] == true;
    canRedo = op == 'undo' && result['changed'] == true;
    _refresh('$op compensation applied to both replicas');
  }
}
