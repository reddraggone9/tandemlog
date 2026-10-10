import 'dart:convert';
import 'dart:io';

import '../domain/event.dart';
import 'local_durability.dart';
import 'local_profile_database.dart';

class WriterGuardFailure extends FormatFailure {
  WriterGuardFailure(super.message);
  WriterGuardFailure.unresolvedAppend()
    : super(
        'An earlier append is unresolved. Unobserved prepared records remain reserved. Restore the exact prepared history before writing; preserve this profile and workspace before recovery.',
      );
}

/// Exact candidate records durably recorded before their canonical append.
class PreparedWriterRecord {
  final int sequence;
  final String hash;
  const PreparedWriterRecord(this.sequence, this.hash);
}

class WriterGuardState {
  final int sequence;
  final String hash;
  final List<PreparedWriterRecord> pending;
  WriterGuardState(
    this.sequence,
    this.hash, [
    Iterable<PreparedWriterRecord> pending = const [],
  ]) : pending = List.unmodifiable(pending);
}

/// Installation-owned safety metadata, independent of the data location/cache.
abstract class WriterGuard {
  Future<WriterGuardState?> load(String space, String writer);
  Future<void> prepare(
    String space,
    String writer,
    int sequence,
    String hash,
    List<PreparedWriterRecord> records,
  );
  Future<void> acknowledge(
    String space,
    String writer,
    int sequence,
    String hash,
  );
}

/// One atomic, durably replaced private file per workspace/writer identity.
/// The installation profile lock owns exclusion across application instances.
class FileWriterGuard implements WriterGuard {
  final String profileRoot;
  static final _queues = <String, Future<void>>{};
  FileWriterGuard(this.profileRoot);

  Future<T> _serialize<T>(Future<T> Function() action) {
    final key = Directory(profileRoot).absolute.path;
    final result = (_queues[key] ?? Future<void>.value()).then((_) => action());
    _queues[key] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  File _file(String space, String writer) {
    if (!isCanonicalId(space) || !isCanonicalId(writer)) {
      throw WriterGuardFailure('Invalid writer safety identity.');
    }
    return File('$profileRoot/writer-guards/$space.$writer.json');
  }

  @override
  Future<WriterGuardState?> load(String space, String writer) =>
      _serialize(() => _load(space, writer));

  Future<WriterGuardState?> _load(String space, String writer) async {
    final file = _file(space, writer);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      return decodeWriterGuardState(bytes, space, writer);
    } on FileSystemException {
      rethrow;
    }
  }

  Future<void> _save(
    String space,
    String writer,
    WriterGuardState state,
  ) async {
    final file = _file(space, writer);
    await ensureDirectoryDurable(file.parent);
    await writeAtomicDurable(file, _encodeGuard(space, writer, state));
  }

  @override
  Future<void> prepare(
    String space,
    String writer,
    int sequence,
    String hash,
    List<PreparedWriterRecord> records,
  ) => _serialize(() async {
    await _save(
      space,
      writer,
      _prepareGuard(
        space,
        writer,
        await _load(space, writer),
        sequence,
        hash,
        records,
      ),
    );
  });

  @override
  Future<void> acknowledge(
    String space,
    String writer,
    int sequence,
    String hash,
  ) => _serialize(() async {
    final current = await _load(space, writer);
    final next = _acknowledgeGuard(space, writer, current, sequence, hash);
    if (!identical(current, next)) await _save(space, writer, next);
  });
}

/// Protected profile authority, never cleared by projection replay. Each
/// mutation commits before returning, including before canonical append I/O.
/// Requires the profile owner's exclusive connection; no file lock sidecar.
class SqliteWriterGuard implements WriterGuard {
  SqliteWriterGuard(this.profile);
  final LocalProfileDatabase profile;

  WriterGuardState? _load(String space, String writer) {
    _guardIdentity(space, writer);
    final rows = profile.database.select(
      'SELECT raw FROM protected_writer_guards WHERE space=? AND writer=?',
      [space, writer],
    );
    return rows.isEmpty
        ? null
        : decodeWriterGuardState(
            rows.single['raw'] as List<int>,
            space,
            writer,
          );
  }

  void _save(String space, String writer, WriterGuardState state) {
    profile.database.execute(
      'INSERT INTO protected_writer_guards VALUES (?,?,?) ON CONFLICT(space,writer) DO UPDATE SET raw=excluded.raw',
      [space, writer, _encodeGuard(space, writer, state)],
    );
  }

  @override
  Future<WriterGuardState?> load(String space, String writer) async =>
      _load(space, writer);

  @override
  Future<void> prepare(
    String space,
    String writer,
    int sequence,
    String hash,
    List<PreparedWriterRecord> records,
  ) async {
    profile.transaction(
      () => prepareInTransaction(space, writer, sequence, hash, records),
    );
  }

  /// Reserve a canonical append with its immutable recovery bytes atomically.
  void prepareInTransaction(
    String space,
    String writer,
    int sequence,
    String hash,
    List<PreparedWriterRecord> records,
  ) {
    if (profile.database.autocommit) {
      throw StateError('Writer preparation requires an active transaction.');
    }
    _save(
      space,
      writer,
      _prepareGuard(
        space,
        writer,
        _load(space, writer),
        sequence,
        hash,
        records,
      ),
    );
  }

  @override
  Future<void> acknowledge(
    String space,
    String writer,
    int sequence,
    String hash,
  ) async {
    profile.transaction(
      () => acknowledgeInTransaction(space, writer, sequence, hash),
    );
  }

  /// The profile owner's ingestion transaction commits this acknowledgement
  /// with the exact canonical receipts and trusted stream checkpoints.
  void acknowledgeInTransaction(
    String space,
    String writer,
    int sequence,
    String hash,
  ) {
    if (profile.database.autocommit) {
      throw StateError(
        'Writer acknowledgement requires an active transaction.',
      );
    }
    final current = _load(space, writer);
    final next = _acknowledgeGuard(space, writer, current, sequence, hash);
    if (!identical(current, next)) _save(space, writer, next);
  }
}

void _guardIdentity(String space, String writer) {
  if (!isCanonicalId(space) || !isCanonicalId(writer)) {
    throw WriterGuardFailure('Invalid writer safety identity.');
  }
}

/// Shared validation for legacy imports and both durable adapters.
WriterGuardState decodeWriterGuardState(
  List<int> bytes,
  String space,
  String writer,
) {
  _guardIdentity(space, writer);
  try {
    if (bytes.length > 16 * 1024 * 1024) throw const FormatException();
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (data.length != 6 ||
        data['v'] != 1 ||
        data['space'] != space ||
        data['writer'] != writer ||
        data['sequence'] is! int ||
        data['sequence'] < 0 ||
        data['sequence'] > 9007199254740991 ||
        !isEventHash(data['hash']) ||
        data['pending'] is! List ||
        (data['sequence'] == 0 &&
            data['hash'] != eventGenesisHash(space, writer))) {
      throw const FormatException();
    }
    var seq = data['sequence'] as int;
    final pending = <PreparedWriterRecord>[];
    for (final candidate in data['pending'] as List) {
      if (candidate is! Map ||
          candidate.length != 2 ||
          candidate['sequence'] is! int ||
          candidate['sequence'] != seq + 1 ||
          candidate['sequence'] > 9007199254740991 ||
          !isEventHash(candidate['hash'])) {
        throw const FormatException();
      }
      seq++;
      pending.add(PreparedWriterRecord(seq, candidate['hash'] as String));
    }
    return WriterGuardState(
      data['sequence'] as int,
      data['hash'] as String,
      pending,
    );
  } catch (_) {
    throw WriterGuardFailure(
      'The private writer safety checkpoint is invalid. Preserve the profile and workspace before recovery.',
    );
  }
}

List<int> _encodeGuard(String space, String writer, WriterGuardState state) =>
    utf8.encode(
      jsonEncode({
        'v': 1,
        'space': space,
        'writer': writer,
        'sequence': state.sequence,
        'hash': state.hash,
        'pending': [
          for (final record in state.pending)
            {'sequence': record.sequence, 'hash': record.hash},
        ],
      }),
    );

WriterGuardState _prepareGuard(
  String space,
  String writer,
  WriterGuardState? current,
  int sequence,
  String hash,
  List<PreparedWriterRecord> records,
) {
  _guardIdentity(space, writer);
  if (records.isEmpty ||
      !isEventHash(hash) ||
      sequence < 0 ||
      (sequence == 0 && hash != eventGenesisHash(space, writer)) ||
      (current != null &&
          (current.sequence != sequence || current.hash != hash))) {
    throw WriterGuardFailure(
      'The writer safety checkpoint changed. Restore the acknowledged history before writing; preserve this profile and workspace before recovery.',
    );
  }
  if (current != null && current.pending.isNotEmpty) {
    throw WriterGuardFailure.unresolvedAppend();
  }
  var next = sequence;
  for (final record in records) {
    if (record.sequence != ++next ||
        next > 9007199254740991 ||
        !isEventHash(record.hash)) {
      throw WriterGuardFailure('Invalid prepared writer sequence.');
    }
  }
  return WriterGuardState(sequence, hash, records);
}

WriterGuardState _acknowledgeGuard(
  String space,
  String writer,
  WriterGuardState? current,
  int sequence,
  String hash,
) {
  _guardIdentity(space, writer);
  if (!isEventHash(hash) ||
      sequence < 0 ||
      sequence > 9007199254740991 ||
      (sequence == 0 && hash != eventGenesisHash(space, writer)) ||
      (current != null &&
          (sequence < current.sequence ||
              (sequence == current.sequence && hash != current.hash)))) {
    throw WriterGuardFailure(
      'The owned writer history is behind or differs from its safety checkpoint. Restore the acknowledged history before writing.',
    );
  }
  if (current != null &&
      current.pending.isNotEmpty &&
      sequence > current.sequence) {
    final index = sequence - current.sequence - 1;
    if (index >= current.pending.length ||
        current.pending[index].hash != hash) {
      throw WriterGuardFailure(
        'The owned writer history differs from the prepared append. Preserve the profile and workspace before recovery.',
      );
    }
  }
  final remaining =
      current?.pending.where((record) => record.sequence > sequence).toList() ??
      const <PreparedWriterRecord>[];
  if (current != null &&
      current.sequence == sequence &&
      current.hash == hash &&
      current.pending.length == remaining.length) {
    return current;
  }
  return WriterGuardState(sequence, hash, remaining);
}
