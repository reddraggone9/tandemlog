// TEST ONLY. Never imported by a production build target.
import 'package:sqlite3/sqlite3.dart';

/// Simulate loss of reconstructible task caches while retaining installation
/// identity, acknowledged history, exact outbox receipts and import witnesses.
Future<void> clearTaskProjections(String root) async {
  final db = sqlite3.open('$root/local.sqlite');
  try {
    final tables = db
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'tasks_[0-9a-f]*_*'",
        )
        .map((r) => r['name'] as String)
        .toList();
    db.execute('BEGIN IMMEDIATE');
    for (final table in tables) {
      if (!RegExp(r'^tasks_[0-9a-f]{64}_[a-z_]+$').hasMatch(table)) {
        throw StateError('Unexpected task projection name.');
      }
      db.execute('DROP TABLE "$table"');
    }
    db.execute('COMMIT');
  } finally {
    db.close();
  }
}
