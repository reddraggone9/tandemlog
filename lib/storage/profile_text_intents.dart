import 'dart:convert';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart' show Row;

import '../domain/event.dart';
import 'local_profile_database.dart';

/// Exact immutable pending bytes, not an accepted task projection. This
/// opt-in adapter has no canonical append or automatic receipt retirement.
class ProfileTextIntents {
  ProfileTextIntents(this.profile);
  final LocalProfileDatabase profile;

  void stage(String space, String writer, Uint8List bytes) {
    profile.transaction(() => stageInTransaction(space, writer, bytes));
  }

  void stageInTransaction(String space, String writer, Uint8List bytes) {
    if (profile.database.autocommit) {
      throw StateError('Staging a text intent requires an active transaction.');
    }
    final raw = utf8.decode(bytes);
    final event = LogEvent.decode(raw);
    if (event.space != space ||
        event.writer != writer ||
        !nativeTextIntentTypes.contains(event.type)) {
      throw FormatFailure(
        'Invalid private prepared text intent; evidence was retained.',
      );
    }
    final rows = profile.database.select(
      'SELECT sequence,id,entity,raw FROM protected_text_intents WHERE space=? AND writer=? AND sequence=?',
      [space, writer, event.sequence],
    );
    if (rows.isNotEmpty) {
      if (!_sameBytes(_boundBytes(space, writer, rows.single), bytes)) {
        throw FormatFailure(
          'Prepared text intent differs from its immutable event bytes.',
        );
      }
      return;
    }
    profile.database.execute(
      'INSERT INTO protected_text_intents VALUES (?,?,?,?,?,?)',
      [space, writer, event.sequence, event.id, event.entity, bytes],
    );
  }

  /// Only exact bytes admitted to the caller's canonical receipt table may be
  /// removed, in the same transaction as those receipts and writer head.
  void retireInTransaction(String space, String writer, Uint8List bytes) {
    if (profile.database.autocommit) {
      throw StateError(
        'Retiring a text intent requires an active transaction.',
      );
    }
    final event = LogEvent.decode(utf8.decode(bytes));
    final saved = atSequence(space, writer, event.sequence);
    if (saved == null || !_sameBytes(saved, bytes)) {
      throw FormatFailure(
        'Canonical receipt differs from the protected text intent.',
      );
    }
    profile.database.execute(
      'DELETE FROM protected_text_intents WHERE space=? AND writer=? AND sequence=?',
      [space, writer, event.sequence],
    );
  }

  List<Uint8List> pending(String space, String writer) => profile.database
      .select(
        'SELECT sequence,id,entity,raw FROM protected_text_intents WHERE space=? AND writer=? ORDER BY sequence',
        [space, writer],
      )
      .map((row) => _boundBytes(space, writer, row))
      .toList(growable: false);

  Uint8List? atSequence(String space, String writer, int sequence) {
    final rows = profile.database.select(
      'SELECT sequence,id,entity,raw FROM protected_text_intents WHERE space=? AND writer=? AND sequence=?',
      [space, writer, sequence],
    );
    return rows.isEmpty ? null : _boundBytes(space, writer, rows.single);
  }

  static Uint8List _boundBytes(String space, String writer, Row row) {
    final bytes = Uint8List.fromList(row['raw'] as List<int>);
    final event = LogEvent.decode(utf8.decode(bytes));
    if (event.space != space ||
        event.writer != writer ||
        event.sequence != row['sequence'] ||
        event.id != row['id'] ||
        event.entity != row['entity'] ||
        !nativeTextIntentTypes.contains(event.type)) {
      throw FormatFailure(
        'Invalid private prepared text intent; evidence was retained.',
      );
    }
    return bytes;
  }

  static bool _sameBytes(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }
}
