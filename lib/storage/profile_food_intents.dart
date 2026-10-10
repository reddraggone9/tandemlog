import 'dart:convert';
import 'dart:typed_data';
import '../food/food_record.dart';
import 'local_profile_database.dart';

/// Immutable recovery authority; no provider I/O or accepted projection here.
class ProfileFoodIntents {
  ProfileFoodIntents(this.profile);
  final LocalProfileDatabase profile;
  static const maximumPendingRecords = 1000;
  static const maximumPendingBytes = 8 * 1024 * 1024;

  void _transaction() {
    if (profile.database.autocommit) {
      throw StateError('Food receipt mutation requires an active transaction.');
    }
  }

  void stageInTransaction(FoodRecord record, Uint8List bytes) {
    _transaction();
    _bind(record, bytes);
    final prior = atSequence(record.space, record.writer, record.sequence);
    if (prior != null) {
      if (!_same(prior, bytes)) {
        throw const FormatException('Food receipt differs.');
      }
      return;
    }
    final totals = _totals(record.space, record.writer);
    if ((totals['n'] as int) >= maximumPendingRecords ||
        (totals['bytes'] as int) + bytes.length > maximumPendingBytes) {
      throw const FormatException(
        'Prepared food batch exceeds recovery limits.',
      );
    }
    profile.database.execute(
      'INSERT INTO protected_food_intents VALUES (?,?,?,?,?)',
      [record.space, record.writer, record.sequence, record.id, bytes],
    );
  }

  void _bind(FoodRecord record, Uint8List bytes) {
    if (bytes.length > maximumFoodRecordBytes) {
      throw const FormatException('Prepared food record exceeds limits.');
    }
    final decoded = FoodRecord.decode(utf8.decode(bytes));
    if (decoded.id != record.id ||
        decoded.hash != record.hash ||
        decoded.space != record.space) {
      throw const FormatException('Prepared food bytes differ.');
    }
  }

  void retireInTransaction(FoodRecord record, Uint8List bytes) {
    _transaction();
    _bind(record, bytes);
    final saved = atSequence(record.space, record.writer, record.sequence);
    if (saved == null || !_same(saved, bytes)) {
      throw const FormatException(
        'Food admission differs from protected bytes.',
      );
    }
    profile.database.execute(
      'DELETE FROM protected_food_intents WHERE space=? AND writer=? AND sequence=?',
      [record.space, record.writer, record.sequence],
    );
  }

  Uint8List? atSequence(String space, String writer, int sequence) {
    _totals(space, writer);
    final rows = profile.database.select(
      'SELECT sequence,id,raw FROM protected_food_intents WHERE space=? AND writer=? AND sequence=?',
      [space, writer, sequence],
    );
    return rows.isEmpty ? null : _bound(space, writer, rows.single);
  }

  List<Uint8List> pending(String space, String writer) {
    _totals(space, writer);
    final rows = profile.database.select(
      'SELECT sequence,id,raw FROM protected_food_intents WHERE space=? AND writer=? ORDER BY sequence',
      [space, writer],
    );
    if (rows.length > maximumPendingRecords) {
      throw const FormatException('Too many food receipts.');
    }
    var size = 0;
    return rows
        .map((row) {
          final bytes = _bound(space, writer, row);
          size += bytes.length;
          if (size > maximumPendingBytes) {
            throw const FormatException('Food receipts exceed limit.');
          }
          return bytes;
        })
        .toList(growable: false);
  }

  Uint8List _bound(String space, String writer, Map<String, dynamic> row) {
    final raw = row['raw'] as List<int>;
    if (raw.length > maximumFoodRecordBytes) {
      throw const FormatException('Protected food record exceeds limits.');
    }
    final bytes = Uint8List.fromList(raw),
        record = FoodRecord.decode(utf8.decode(raw));
    if (record.space != space ||
        record.writer != writer ||
        record.sequence != row['sequence'] ||
        record.id != row['id']) {
      throw const FormatException(
        'Food receipt metadata differs from its bytes.',
      );
    }
    return bytes;
  }

  Map<String, dynamic> _totals(String space, String writer) {
    final totals = profile.database.select(
      'SELECT COUNT(*) AS n,COALESCE(SUM(length(raw)),0) AS bytes,COALESCE(MAX(length(raw)),0) AS largest FROM protected_food_intents WHERE space=? AND writer=?',
      [space, writer],
    ).single;
    if ((totals['n'] as int) > maximumPendingRecords ||
        (totals['bytes'] as int) > maximumPendingBytes ||
        (totals['largest'] as int) > maximumFoodRecordBytes) {
      throw const FormatException(
        'Protected food receipts exceed safe limits.',
      );
    }
    return totals;
  }

  static bool _same(List<int> a, List<int> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
}
