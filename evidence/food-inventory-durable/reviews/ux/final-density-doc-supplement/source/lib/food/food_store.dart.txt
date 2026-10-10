import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import '../storage/local_profile_database.dart';
import '../storage/log_folder.dart';
import '../storage/profile_food_intents.dart';
import '../storage/writer_guard.dart';
import 'food_record.dart';
import 'inventory.dart';

/// Isolated canonical Food history/provider admission failure. Shared profile,
/// installation identity and manifest faults deliberately retain their own type.
class FoodHistoryFailure extends FormatException {
  const FoodHistoryFailure(super.message);
}

/// One module handle on the app-owned connection and queue. Canonical streams
/// remain in the selected folder; SQL stores recovery authority, never a second
/// canonical inventory. Projection publishes only after admission commits.
class FoodStore {
  FoodStore._(
    this.folder,
    this.profile,
    this.writer,
    this.space,
    this._lease,
    this.now,
  );
  final LogFolder folder;
  final LocalProfileDatabase profile;
  final String writer, space, _lease;
  final DateTime Function() now;
  FoodState state = FoodState([]);
  List<FoodRecord> _records = [];
  Map<String, FoodRecord> _births = {};
  Uint8List _remaining = Uint8List(0);
  bool _streamExists = false, _closed = false;
  Future<void> _operations = Future<void>.value();
  Future<void>? _closing;
  int pendingReferences = 0;
  int _totalBytes = 0, _ownedBytes = 0, _streamCount = 0;
  List<FoodRecord> lastPreparedRecords = [];
  bool isAdmitted(FoodRecord record) =>
      _readyIds.contains(record.id) &&
      _records.any((r) => r.id == record.id && r.hash == record.hash);
  bool get hasPreparedAppend => _remaining.isNotEmpty;
  List<String> get pendingOperationIds => List.unmodifiable(
    _records.where((r) => !_readyIds.contains(r.id)).map((r) => r.id),
  );
  Set<String> _readyIds = {};
  static const maximumStreams = 256,
      maximumStreamBytes = 16 * 1024 * 1024,
      maximumTotalBytes = 32 * 1024 * 1024,
      maximumRecords = 50000,
      maximumContainers = 100000;

  static Future<FoodStore> open(
    LogFolder folder, {
    required LocalProfileDatabase profile,
    required String installationWriter,
    required String space,
    DateTime Function()? now,
  }) async {
    if (!isCanonicalId(space)) {
      throw const FormatException('Invalid food workspace.');
    }
    final moduleWriter = foodWriter(installationWriter);
    final lease = 'food:${sha256.convert(utf8.encode(folder.location))}';
    profile.acquireWorkspace(lease);
    final store = FoodStore._(
      folder,
      profile,
      moduleWriter,
      space,
      lease,
      now ?? DateTime.now,
    );
    try {
      await store.refresh();
      return store;
    } catch (failure) {
      profile.releaseWorkspace(lease);
      if (failure is FoodHistoryFailure) {
        // A module-only error must never mask a simultaneous shared identity or
        // profile failure. This read performs no write or recovery append.
        await store._manifest();
      }
      rethrow;
    }
  }

  Future<T> _queue<T>(Future<T> Function() work) {
    if (_closed || _closing != null) {
      return Future.error(StateError('Food workspace is closed.'));
    }
    final result = profile.serialize(() async {
      if (_closed) throw StateError('Food workspace is closed.');
      return work();
    });
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// Drain this handle's already admitted work without requiring a healthy SQL
  /// owner. Poisoned profiles must still be able to release all handle leases.
  Future<void> close() {
    if (_closed) return Future<void>.value();
    return _closing ??= _operations.then((_) {
      _closed = true;
      profile.releaseWorkspace(_lease);
    });
  }

  Future<void> refresh() => _queue(_refresh);

  Future<void> _checkLocalFile(String name, {bool allowMissing = false}) async {
    final transport = folder;
    if (transport is! LocalLogFolder) return;
    final path = transport.file(name).path;
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        !(allowMissing && type == FileSystemEntityType.notFound)) {
      throw FormatException(
        'Food canonical path "$name" must be a regular file.',
      );
    }
  }

  Future<Uint8List> _read(String name, int limit) async {
    await _checkLocalFile(name);
    final transport = folder;
    final bytes = transport is BoundedLogFolder
        ? await (transport as BoundedLogFolder).readBounded(name, limit)
        : throw const FormatException(
            'This folder cannot enforce safe food read limits.',
          );
    await _checkLocalFile(name);
    if (bytes.length > limit) {
      throw const FormatException('Food input exceeds safe read limits.');
    }
    return bytes;
  }

  Future<void> _manifest() async {
    final raw = await _read('tandemlog-space.json', 4096);
    final j = jsonDecode(utf8.decode(raw));
    if (j is! Map || j.length != 2 || j['v'] != 3 || j['id'] != space) {
      throw const FormatException(
        'Food workspace identity changed or is invalid.',
      );
    }
    final rows = profile.database.select(
      'SELECT space FROM protected_food_locations WHERE location=?',
      [folder.location],
    );
    if (rows.isNotEmpty && rows.single['space'] != space) {
      throw const FormatException(
        'Food workspace identity changed at this location.',
      );
    }
  }

  Future<void> _refresh() async {
    try {
      await _admitRefresh();
    } on FoodHistoryFailure {
      // Every read path, including foreground refresh and pre-command refresh,
      // must classify a simultaneous shared identity/owner fault as hard.
      await _manifest();
      rethrow;
    }
  }

  Future<void> _admitRefresh() async {
    await _manifest();
    // Validate private recovery authority before a remote Food failure can be
    // classified as isolated. No canonical comparison or write occurs here.
    final trusted = profile.database.select(
      'SELECT writer,sequence,hash FROM protected_food_heads WHERE space=?',
      [space],
    );
    for (final head in trusted) {
      final seq = head['sequence'];
      if (!isCanonicalId(head['writer']) ||
          seq is! int ||
          seq < 0 ||
          seq > 9007199254740991 ||
          head['hash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(head['hash'] as String) ||
          (seq == 0 &&
              (head['writer'] != writer ||
                  head['hash'] != eventGenesisHash(space, writer)))) {
        throw const FormatException('Food protected head is invalid.');
      }
    }
    final intents = ProfileFoodIntents(profile),
        guard = SqliteWriterGuard(profile);
    final receipts = intents.pending(space, writer);
    final guarded = await guard.load(space, writer);
    if (guarded == null && trusted.any((head) => head['writer'] == writer)) {
      throw const FormatException(
        'Initialized food writer has lost its safety reservation.',
      );
    }
    final ownHead = trusted
        .where((head) => head['writer'] == writer)
        .firstOrNull;
    if (guarded != null &&
        (ownHead == null ||
            guarded.sequence != ownHead['sequence'] ||
            guarded.hash != ownHead['hash'])) {
      throw const FormatException(
        'Food writer safety reservation differs from its trusted head.',
      );
    }
    final protected = <int, Uint8List>{};
    for (final bytes in receipts) {
      final r = FoodRecord.decode(utf8.decode(bytes));
      protected[r.sequence] = bytes;
    }
    if (guarded == null && receipts.isNotEmpty) {
      throw const FormatException('Food receipts have no writer reservation.');
    }
    final expectedPending = guarded?.pending ?? <PreparedWriterRecord>[];
    if (expectedPending.length != receipts.length ||
        expectedPending.any(
          (p) =>
              protected[p.sequence] == null ||
              FoodRecord.decode(utf8.decode(protected[p.sequence]!)).hash !=
                  p.hash,
        )) {
      throw const FormatException(
        'Food recovery bytes differ from their reservation.',
      );
    }
    final streams = <String, List<FoodRecord>>{};
    final records = <FoodRecord>[];
    Uint8List tail = Uint8List(0);
    var total = 0, ownBytes = 0, ownExists = false;
    final names = <String>{};
    try {
      final infos = await folder.list();
      final transport = folder;
      if (transport is LocalLogFolder) {
        await for (final entry in Directory(
          transport.location,
        ).list(followLinks: false)) {
          if (entry.path.toLowerCase().endsWith('.foodlog') && entry is! File) {
            throw const FormatException('Linked food streams are ambiguous.');
          }
        }
      }
      final pattern = RegExp(
        r'^food-([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})\.foodlog$',
      );
      for (final info in infos) {
        if (isFoodConflictName(info.name)) {
          throw const FormatException(
            'Food folder-sync conflict copy needs recovery.',
          );
        }
        if (!info.name.toLowerCase().endsWith('.foodlog')) continue;
        final match = pattern.firstMatch(info.name);
        if (match == null ||
            !names.add(info.name) ||
            names.length > maximumStreams) {
          throw const FormatException(
            'Ambiguous or excessive food stream names.',
          );
        }
        if (info.size != null && info.size! > maximumStreamBytes) {
          throw const FormatException('Food stream exceeds safe read limits.');
        }
        final streamWriter = match[1]!;
        final bytes = await _read(info.name, maximumStreamBytes);
        total += bytes.length;
        if (total > maximumTotalBytes) {
          throw const FormatException('Food history exceeds safe read limits.');
        }
        var start = 0, sequence = 0;
        var hash = eventGenesisHash(space, streamWriter);
        EventClock? clock;
        final stream = <FoodRecord>[];
        for (var i = 0; i < bytes.length; i++) {
          if (bytes[i] != 10) {
            if (i - start >= maximumFoodRecordBytes) {
              throw const FormatException('Food record is too large.');
            }
            continue;
          }
          final record = FoodRecord.decode(
            utf8.decode(Uint8List.sublistView(bytes, start, i)),
          );
          if (record.space != space ||
              record.writer != streamWriter ||
              record.sequence != sequence + 1 ||
              record.previousHash != hash ||
              (clock != null && record.clock <= clock)) {
            throw const FormatException(
              'Food stream chain, identity or clock differs.',
            );
          }
          sequence++;
          hash = record.hash;
          clock = record.clock;
          stream.add(record);
          records.add(record);
          if (records.length > maximumRecords) {
            throw const FormatException('Too many food records.');
          }
          start = i + 1;
        }
        if (streamWriter == writer) {
          ownExists = true;
          ownBytes = bytes.length;
          tail = Uint8List.fromList(bytes.sublist(start));
        } else if (start != bytes.length) {
          throw const FormatException(
            'A food stream is incomplete; wait for folder sync then retry.',
          );
        }
        streams[streamWriter] = stream;
      }
    } on FormatException catch (failure) {
      throw FoodHistoryFailure(failure.message);
    } on FolderAccessFailure catch (failure) {
      throw FoodHistoryFailure(failure.message);
    } on FileSystemException catch (failure) {
      throw FoodHistoryFailure(failure.toString());
    }
    for (final head in trusted) {
      final stream = streams[head['writer']];
      final seq = head['sequence'];
      if (!isCanonicalId(head['writer']) ||
          seq is! int ||
          seq < 0 ||
          seq > 9007199254740991 ||
          head['hash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(head['hash'] as String)) {
        throw const FormatException('Food protected head is invalid.');
      }
      if (seq == 0) {
        if (head['writer'] != writer ||
            head['hash'] != eventGenesisHash(space, writer)) {
          throw const FormatException(
            'Food initialization witness is invalid.',
          );
        }
        continue;
      }
      if (stream == null ||
          stream.length < seq ||
          stream[seq - 1].hash != head['hash']) {
        throw const FoodHistoryFailure(
          'Previously admitted food history is missing or changed.',
        );
      }
    }
    final own = streams[writer] ?? <FoodRecord>[];
    final sequence = own.length,
        hash = own.isEmpty ? eventGenesisHash(space, writer) : own.last.hash;
    if (guarded != null &&
        (sequence < guarded.sequence ||
            (guarded.sequence > 0 &&
                own[guarded.sequence - 1].hash != guarded.hash))) {
      throw const FoodHistoryFailure(
        'Owned food history differs from its safety checkpoint.',
      );
    }
    for (final entry in protected.entries) {
      if (entry.key <= sequence &&
          own[entry.key - 1].encode() != utf8.decode(entry.value)) {
        throw const FormatException(
          'Owned food append differs from immutable prepared bytes.',
        );
      }
    }
    // If a local reservation exists, every extra owned record must be one of
    // those exact reserved records, including before SQL acknowledgement.
    if (guarded != null &&
        guarded.pending.isNotEmpty &&
        sequence > guarded.sequence + guarded.pending.length) {
      throw const FormatException(
        'Owned food history exceeds its pending reservation.',
      );
    }
    final builder = BytesBuilder(copy: false);
    for (final entry in protected.entries) {
      if (entry.key > sequence) {
        builder.add(entry.value);
        builder.addByte(10);
      }
    }
    final expected = builder.takeBytes();
    if (tail.length > expected.length || !_prefix(expected, tail)) {
      throw const FormatException(
        'Incomplete food append has no exact protected recovery bytes.',
      );
    }
    final remaining = Uint8List.fromList(expected.sublist(tail.length));
    final _FoodAdmission admission;
    try {
      admission = _project(records);
    } on FormatException catch (failure) {
      throw FoodHistoryFailure(failure.message);
    }
    await _manifest();
    profile.transaction(() {
      profile.database.execute(
        'INSERT OR IGNORE INTO protected_food_locations VALUES (?,?)',
        [folder.location, space],
      );
      for (final entry in streams.entries) {
        if (entry.value.isEmpty) continue;
        final last = entry.value.last;
        profile.database.execute(
          'INSERT INTO protected_food_heads VALUES (?,?,?,?) ON CONFLICT(space,writer) DO UPDATE SET sequence=excluded.sequence,hash=excluded.hash',
          [space, entry.key, last.sequence, last.hash],
        );
      }
      // The zero/genesis head is an initialization witness even before this
      // installation has its first admitted physical container.
      profile.database.execute(
        'INSERT OR IGNORE INTO protected_food_heads VALUES (?,?,?,?)',
        [space, writer, 0, eventGenesisHash(space, writer)],
      );
      guard.acknowledgeInTransaction(space, writer, sequence, hash);
      for (final entry in protected.entries) {
        if (entry.key <= sequence) {
          intents.retireInTransaction(own[entry.key - 1], entry.value);
        }
      }
    });
    state = admission.state;
    _births = admission.births;
    _readyIds = admission.readyIds;
    pendingReferences = records.length - admission.readyIds.length;
    _records = records;
    _remaining = remaining;
    _streamExists = ownExists;
    _totalBytes = total;
    _streamCount = names.length;
    _ownedBytes = ownBytes;
    if (lastPreparedRecords.isEmpty && protected.isNotEmpty) {
      lastPreparedRecords = List.unmodifiable(
        protected.values.map((b) => FoodRecord.decode(utf8.decode(b))),
      );
    }
  }

  _FoodAdmission _project(List<FoodRecord> records) {
    final byId = {for (final r in records) r.id: r};
    final targetSets = {
      for (final r in records) r.id: r.operation.targets.toSet(),
    };
    final births = <String, FoodRecord>{};
    for (final record in records) {
      if (record.operation.action != FoodAction.add) continue;
      for (final id in record.operation.targets) {
        if (births.containsKey(id)) {
          throw const FormatException(
            'A physical food container has different creation records.',
          );
        }
        births[id] = record;
      }
      if (births.length > maximumContainers) {
        throw const FormatException('Too many food containers.');
      }
    }
    final dependencies = <String, List<String>>{};
    for (final r in records) {
      final refs = <String>{
        ...r.createdWith.values,
        ...r.operation.observedDeletes,
        ...r.operation.observedEdits,
      };
      for (final entry in r.createdWith.entries) {
        final basis = byId[entry.value];
        if (basis != null &&
            (basis.operation.action != FoodAction.add ||
                !targetSets[basis.id]!.contains(entry.key) ||
                basis.clock >= r.clock ||
                births[entry.key]?.id != basis.id)) {
          throw const FormatException('Food target creation basis is invalid.');
        }
      }
      for (final (refs, kind) in [
        (r.operation.observedDeletes, FoodAction.remove),
        (r.operation.observedEdits, FoodAction.edit),
      ]) {
        for (final ref in refs) {
          final basis = byId[ref];
          if (basis == null) continue;
          if (basis.operation.action != kind ||
              basis.clock >= r.clock ||
              !r.operation.targets.every(targetSets[basis.id]!.contains) ||
              (kind == FoodAction.edit && basis.operation.contents == null)) {
            throw const FormatException(
              'Food observed reference has wrong kind, target or clock.',
            );
          }
        }
      }
      dependencies[r.id] = refs.toList();
    }
    final ordered = records.toList()
      ..sort((a, b) {
        final clock = a.clock.compareTo(b.clock);
        if (clock != 0) return clock;
        final writer = a.writer.compareTo(b.writer);
        return writer != 0 ? writer : a.sequence.compareTo(b.sequence);
      });
    final ready = <String>{}, operations = <FoodOperation>[];
    for (final r in ordered) {
      if (dependencies[r.id]!.every(ready.contains)) {
        ready.add(r.id);
        operations.add(r.operation);
      }
    }
    return _FoodAdmission(projectFood(operations), births, ready);
  }

  static bool _prefix(List<int> bytes, List<int> prefix) =>
      prefix.length <= bytes.length &&
      Iterable<int>.generate(prefix.length).every((i) => bytes[i] == prefix[i]);

  Future<void> recoverPrepared() => _queue(() async {
    await _refresh();
    if (_remaining.isEmpty) return;
    await _append(_remaining);
    await _refresh();
  });
  Future<void> _append(Uint8List bytes) async {
    if (_records.length + bytes.where((byte) => byte == 10).length >
            maximumRecords ||
        _ownedBytes + bytes.length > maximumStreamBytes ||
        _totalBytes + bytes.length > maximumTotalBytes ||
        (!_streamExists && _streamCount >= maximumStreams)) {
      throw const FormatException(
        'Food append exceeds safe storage limits; recovery bytes were retained.',
      );
    }
    final name = foodLogName(writer);
    await _checkLocalFile(name, allowMissing: !_streamExists);
    await _manifest();
    if (_streamExists) {
      await folder.append(name, bytes);
    } else {
      await folder.create(name, bytes);
    }
  }

  Future<List<FoodRecord>> _command(List<_FoodChange> changes) =>
      _queue(() => _commandLocked(changes));
  Future<List<FoodRecord>> _commandLocked(List<_FoodChange> changes) async {
    await _refresh();
    if (hasPreparedAppend || pendingReferences > 0) {
      throw const FormatException(
        'Food history needs recovery or folder sync before another change.',
      );
    }
    final own = _records.where((r) => r.writer == writer).toList();
    var seq = own.length,
        previous = own.isEmpty
            ? eventGenesisHash(space, writer)
            : own.last.hash;
    EventClock? clock = _records.isEmpty
        ? null
        : _records.map((r) => r.clock).reduce((a, b) => a > b ? a : b);
    final batch = <FoodRecord>[];
    for (final change in changes) {
      clock = EventClock.next(
        BigInt.from(now().microsecondsSinceEpoch) * BigInt.from(1000),
        clock,
      );
      final operation = FoodOperation(
        id: '$writer:${++seq}',
        order: clock.value.toInt(),
        action: change.action,
        targets: change.targets,
        details: change.details,
        contents: change.contents,
        createdAt: change.action == FoodAction.add
            ? now().toUtc().toIso8601String()
            : null,
        observedDeletes: change.deletes,
        observedEdits: [
          ...change.edits,
          if (change.observePreviousEdit) batch.last.id,
        ],
        fields: change.fields,
      );
      final basis = <String, String>{};
      if (change.action != FoodAction.add) {
        for (final id in change.targets) {
          if (!_births.containsKey(id) ||
              !_readyIds.contains(_births[id]!.id)) {
            throw const FormatException(
              'Food target is not an admitted container.',
            );
          }
          basis[id] = _births[id]!.id;
        }
      }
      final record = FoodRecord(
        space: space,
        writer: writer,
        sequence: seq,
        clock: clock,
        operation: operation,
        previousHash: previous,
        createdWith: basis,
      );
      previous = record.hash;
      batch.add(record);
    }
    if (batch.isEmpty) return [];
    _project([
      ..._records,
      ...batch,
    ]); // Validate before reserving or appending.
    final encoded = BytesBuilder(copy: false);
    for (final r in batch) {
      encoded.add(utf8.encode(r.encode()));
      encoded.addByte(10);
    }
    final appendBytes = encoded.takeBytes();
    if (_records.length + batch.length > maximumRecords ||
        _ownedBytes + appendBytes.length > maximumStreamBytes ||
        _totalBytes + appendBytes.length > maximumTotalBytes ||
        (!_streamExists && _streamCount >= maximumStreams)) {
      throw const FormatException(
        'Food history is at its safe storage limit; no change was appended.',
      );
    }
    final intents = ProfileFoodIntents(profile),
        guard = SqliteWriterGuard(profile);
    profile.transaction(() {
      guard.prepareInTransaction(
        space,
        writer,
        own.length,
        own.isEmpty ? eventGenesisHash(space, writer) : own.last.hash,
        batch.map((r) => PreparedWriterRecord(r.sequence, r.hash)).toList(),
      );
      for (final r in batch) {
        intents.stageInTransaction(
          r,
          Uint8List.fromList(utf8.encode(r.encode())),
        );
      }
    });
    lastPreparedRecords = List.unmodifiable(batch);
    _remaining = appendBytes;
    await _append(appendBytes);
    await _refresh();
    return batch;
  }

  Future<void> add(FoodDetails details, int count) {
    if (count < 1 || count > 100) {
      return Future.error(
        const FormatException('Choose between 1 and 100 physical containers.'),
      );
    }
    return _command([
      _FoodChange(
        FoodAction.add,
        List.generate(count, (_) => const Uuid().v4()),
        details: details,
        contents: const Contents.fraction(1, 1),
      ),
    ]);
  }

  Future<List<FoodRecord>> remove(List<String> ids) => _command(
    _batches(
      ids,
    ).map((batch) => _FoodChange(FoodAction.remove, batch)).toList(),
  );
  Future<void> restore(List<FoodContainer> observed) async {
    _batches(observed.map((item) => item.id).toList());
    final changes = <_FoodChange>[];
    for (final item in observed) {
      final refs = item.deletions.toList();
      for (var i = 0; i < refs.length; i += 1000) {
        changes.add(
          _FoodChange(FoodAction.restore, [
            item.id,
          ], deletes: refs.sublist(i, (i + 1000).clamp(0, refs.length))),
        );
      }
    }
    await _command(changes);
  }

  Future<void> changeDetails(
    List<String> ids,
    FoodDetails details,
    List<String> fields,
  ) async {
    await _command(
      _batches(ids)
          .map(
            (batch) => _FoodChange(
              FoodAction.edit,
              batch,
              details: details,
              fields: fields,
            ),
          )
          .toList(),
    );
  }

  Future<void> changeContents(FoodContainer observed, Contents contents) async {
    final refs = observed.contentsEdits.keys.toList(),
        changes = <_FoodChange>[];
    if (refs.isEmpty) {
      changes.add(
        _FoodChange(FoodAction.edit, [observed.id], contents: contents),
      );
    }
    for (var i = 0; i < refs.length; i += 999) {
      changes.add(
        _FoodChange(
          FoodAction.edit,
          [observed.id],
          contents: contents,
          edits: refs.sublist(i, (i + 999).clamp(0, refs.length)),
          observePreviousEdit: i > 0,
        ),
      );
    }
    await _command(changes);
  }

  Future<void> undoRemovals(List<FoodRecord> removals) => _queue(() async {
    await _refresh();
    final changes = <_FoodChange>[];
    for (final remove in removals) {
      if (remove.writer != writer ||
          remove.operation.action != FoodAction.remove ||
          !_readyIds.contains(remove.id) ||
          !_records.any((r) => r.id == remove.id && r.hash == remove.hash)) {
        throw const FormatException(
          'Undo requires an admitted local food removal.',
        );
      }
      changes.add(
        _FoodChange(
          FoodAction.restore,
          remove.operation.targets,
          deletes: [remove.id],
        ),
      );
    }
    await _commandLocked(changes);
  });
  static List<List<String>> _batches(List<String> ids) {
    if (ids.isEmpty || ids.toSet().length != ids.length || ids.length > 10000) {
      throw const FormatException('Invalid food selection.');
    }
    return [
      for (var i = 0; i < ids.length; i += 100)
        ids.sublist(i, (i + 100).clamp(0, ids.length)),
    ];
  }
}

class _FoodChange {
  _FoodChange(
    this.action,
    this.targets, {
    this.details,
    this.contents,
    this.fields,
    this.deletes = const [],
    this.edits = const [],
    this.observePreviousEdit = false,
  });
  final FoodAction action;
  final List<String> targets;
  final FoodDetails? details;
  final Contents? contents;
  final List<String>? fields;
  final List<String> deletes, edits;
  final bool observePreviousEdit;
}

class _FoodAdmission {
  _FoodAdmission(this.state, this.births, this.readyIds);
  final FoodState state;
  final Map<String, FoodRecord> births;
  final Set<String> readyIds;
}
