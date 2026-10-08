import 'package:sqlite3/sqlite3.dart';

import '../domain/event.dart' show isCanonicalId;

/// Optional device-local display state in the already workspace-bound cache.
/// Losing this namespace/cache simply restores collapsed checklists.
class ChecklistExpansionStore {
  ChecklistExpansionStore(this.db);
  final Database db;
  static const prefix = 'ui.checklist-expanded:';

  Set<String> load() => {
    for (final row in db.select(
      'SELECT key FROM metadata WHERE key LIKE ? AND value=?',
      ['$prefix%', '1'],
    ))
      if (isCanonicalId((row['key'] as String).substring(prefix.length)))
        (row['key'] as String).substring(prefix.length),
  };

  void setExpanded(Iterable<String> parents, bool expanded) {
    final ids = parents.toSet();
    if (ids.any((id) => !isCanonicalId(id))) {
      throw ArgumentError('Checklist display state needs parent task IDs.');
    }
    if (ids.isEmpty) return;
    if (!db.autocommit) {
      throw StateError(
        'Wait for the active cache transaction before display changes.',
      );
    }
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final id in ids) {
        if (expanded) {
          db.execute('INSERT OR REPLACE INTO metadata VALUES (?,?)', [
            '$prefix$id',
            '1',
          ]);
        } else {
          db.execute('DELETE FROM metadata WHERE key=?', ['$prefix$id']);
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}
