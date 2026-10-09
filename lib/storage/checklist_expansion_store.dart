import 'package:sqlite3/sqlite3.dart';

import '../domain/event.dart' show isCanonicalId;
import 'task_tables.dart';
import 'local_profile_database.dart';

/// Optional device-local display state in the already workspace-bound cache.
/// Losing this namespace/cache simply restores collapsed checklists.
class ChecklistExpansionStore {
  ChecklistExpansionStore(
    this._database, {
    this.tables = const TaskTables.legacy(),
    this.profileDatabase,
  }) {
    if (profileDatabase != null &&
        !identical(_database, profileDatabase!.database)) {
      throw ArgumentError(
        'Checklist display state must use its profile connection.',
      );
    }
  }
  final Database _database;
  final LocalProfileDatabase? profileDatabase;
  Database get db => profileDatabase?.database ?? _database;
  final TaskTables tables;
  static const prefix = 'ui.checklist-expanded:';

  Set<String> load() => {
    for (final row in db.select(
      'SELECT key FROM ${tables.metadata} WHERE key LIKE ? AND value=?',
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
    void write() {
      for (final id in ids) {
        if (expanded) {
          db.execute('INSERT OR REPLACE INTO ${tables.metadata} VALUES (?,?)', [
            '$prefix$id',
            '1',
          ]);
        } else {
          db.execute('DELETE FROM ${tables.metadata} WHERE key=?', [
            '$prefix$id',
          ]);
        }
      }
    }

    if (profileDatabase != null) {
      profileDatabase!.transaction(write);
    } else {
      db.execute('BEGIN IMMEDIATE');
      try {
        write();
        db.execute('COMMIT');
      } catch (_) {
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      }
    }
  }
}
