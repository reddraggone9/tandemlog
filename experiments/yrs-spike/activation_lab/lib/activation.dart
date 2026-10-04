// Disposable synthetic coordinator. NOT an adopted app protocol or transport.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/projection.dart';
import '../../editor_lab/lib/native_bridge.dart';

String _json(Object? value) {
  Object? normalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: normalize(value[key])};
    }
    if (value is List) return value.map(normalize).toList();
    return value;
  }

  return jsonEncode(normalize(value));
}

String _digest(Object? value) =>
    sha256.convert(utf8.encode(_json({'value': value}))).toString();
String _key(String entity, String field) => '$entity:$field';
int _serial = 0;

class LabConfig {
  const LabConfig({
    required this.space,
    required this.issuer,
    required this.activationRef,
  });
  final String space, issuer, activationRef;
}

class DraftValue {
  const DraftValue(
    this.text, {
    this.selectionStart = -1,
    this.selectionEnd = -1,
    this.composingStart = -1,
    this.composingEnd = -1,
  });
  final String text;
  final int selectionStart, selectionEnd, composingStart, composingEnd;
  bool get composing => composingStart >= 0 && composingEnd > composingStart;
}

class LabDraft {
  LabDraft._(
    this.owner,
    this.entity,
    this.field,
    this.batch,
    this.value, {
    this.nativeName,
    this.nativeContext,
    this.capturedScalarBase,
  });
  final ActivationLab owner;
  final String entity, field, batch;
  final String? nativeName, nativeContext, capturedScalarBase;
  DraftValue value;
  String? prepared;
  bool closed = false;
  void change(DraftValue next) {
    if (closed || prepared != null) {
      throw StateError('Draft is closed or prepared');
    }
    if (nativeName != null) {
      owner._ensureWritable(entity, field);
      final old = value.text;
      var prefix = 0;
      while (prefix < old.length &&
          prefix < next.text.length &&
          old.codeUnitAt(prefix) == next.text.codeUnitAt(prefix)) {
        prefix++;
      }
      while (!_boundary(old, prefix) || !_boundary(next.text, prefix)) {
        prefix--;
      }
      var suffix = 0;
      while (suffix < old.length - prefix &&
          suffix < next.text.length - prefix &&
          old.codeUnitAt(old.length - 1 - suffix) ==
              next.text.codeUnitAt(next.text.length - 1 - suffix)) {
        suffix++;
      }
      while (!_boundary(old, old.length - suffix) ||
          !_boundary(next.text, next.text.length - suffix)) {
        suffix--;
      }
      if (old != next.text) {
        owner._bridge.call('edit', {
          'name': nativeName,
          'index': prefix,
          'delete': old.length - prefix - suffix,
          'insert': next.text.substring(prefix, next.text.length - suffix),
        });
      }
      owner._bridge.call('composition', {
        'name': nativeName,
        'active': next.composing,
      });
    }
    value = next;
  }

  static bool _boundary(String s, int n) =>
      n == 0 ||
      n == s.length ||
      !(s.codeUnitAt(n - 1) >= 0xd800 &&
          s.codeUnitAt(n - 1) <= 0xdbff &&
          s.codeUnitAt(n) >= 0xdc00 &&
          s.codeUnitAt(n) <= 0xdfff);
}

class _Field {
  _Field(this.name, this.context);
  String name;
  final String context;
  final Set<String> applied = {};
}

class _PreparedUndo {
  const _PreparedUndo(this.name, this.token, this.update);
  final String name, token, update;
}

class ActivationLab {
  ActivationLab({
    required this.name,
    required this.writer,
    required this.config,
    this.directory,
    required this.nowNs,
  }) {
    directory?.createSync(recursive: true);
    if (directory != null) {
      for (final f in directory!.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.prepared'),
      )) {
        final raw = f.readAsStringSync();
        _outbox[_packetId(raw)] = raw;
      }
      final journal = File('${directory!.path}/records.jsonl');
      if (journal.existsSync()) {
        // Complete-line only; do not truncate interrupted evidence.
        final lines = journal.readAsStringSync().split('\n');
        final tail = lines.removeLast();
        if (tail.isNotEmpty) isBlocked = true;
        for (final raw in lines) {
          if (raw.isNotEmpty) {
            try {
              _ingest(raw, persist: false);
            } catch (_) {
              /* retain blocked evidence */
            }
          }
        }
      }
    }
  }
  final String name, writer;
  final LabConfig? config;
  final Directory? directory;
  final BigInt Function() nowNs;
  final _bridge = NativeBridge();
  final Map<String, String> _records = {}, _outbox = {};
  final Map<String, _PreparedUndo> _preparedUndos = {};
  final List<String> evidence = [];
  final Map<String, LogEvent> _legacy = {};
  final Map<String, LogEvent> _nativeCreations = {};
  String? _spaceId;
  final Map<String, Map<String, dynamic>> _updates = {};
  final Map<String, _Field> _fields = {};
  final List<LabDraft> _drafts = [];
  Map<String, dynamic>? _activation;
  Map<String, String> _seeds = {};
  int cacheRestoreCount = 0;
  bool isActive = false, isBlocked = false, _closed = false;
  List<String> get records => _records.values.toList();
  List<String> get outboxRecords => _outbox.values.toList();
  BigInt get maximumObserved {
    var maximum = BigInt.zero;
    for (final e in _verifiedLegacy()) {
      if (e.clock.value > maximum) maximum = e.clock.value;
    }
    for (final p in [_activation, ..._updates.values]) {
      if (p == null) continue;
      final clock = EventClock.fromJson(p['clock']).value;
      if (clock > maximum) maximum = clock;
    }
    return maximum;
  }

  Set<String> get excludedTextEvents => !isActive
      ? {}
      : _verifiedLegacy()
            .where(
              (e) =>
                  e.type == 'task.edited' &&
                  (e.data.containsKey('title') ||
                      e.data.containsKey('description')) &&
                  !_included(e),
            )
            .map((e) => e.id)
            .toSet();
  static String seal(Map<String, dynamic> packet) {
    final body = Map<String, dynamic>.from(packet)..remove('checksum');
    return _json({...body, 'checksum': _digest(body)});
  }

  static String _packetId(String raw) {
    final p = jsonDecode(raw) as Map<String, dynamic>;
    return p['v'] == 3 ? LogEvent.decode(raw).id : p['id'] as String;
  }

  void ingest(String raw) => _ingest(raw);
  void ingestAll(Iterable<String> raws) {
    for (final raw in raws) {
      ingest(raw);
    }
  }

  void _append(String raw) {
    if (directory == null) return;
    final file = File('${directory!.path}/records.jsonl');
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      if (bytes.isNotEmpty && bytes.last != 10) {
        isBlocked = true;
        throw StateError(
          'Incomplete owned journal tail; original bytes retained',
        );
      }
    }
    final f = file.openSync(mode: FileMode.append);
    try {
      f.writeStringSync('$raw\n');
      f.flushSync();
    } finally {
      f.closeSync();
    }
  }

  void _ingest(String raw, {bool persist = true, bool localReceipt = false}) {
    if (_closed) throw StateError('Lab closed');
    if (!evidence.contains(raw)) {
      evidence.add(raw);
    }
    String? id;
    try {
      final p = jsonDecode(raw) as Map<String, dynamic>;
      id = _packetId(raw);
      if (_records.containsKey(id)) {
        if (_records[id] != raw) {
          throw StateError('Conflicting immutable record');
        }
        return;
      }
      if (persist) _append(raw);
      if (p['v'] == 3) {
        final e = LogEvent.decode(raw);
        if (config != null && e.space != config!.space) {
          throw StateError('Wrong space');
        }
        if (_spaceId != null && e.space != _spaceId) {
          throw StateError('Wrong space');
        }
        _spaceId = e.space;
        _legacy[id] = e;
      } else {
        final body = Map<String, dynamic>.from(p)..remove('checksum');
        if (p['checksum'] != _digest(body) || _json(p) != raw) {
          throw StateError('Bad lab checksum/encoding');
        }
        final nativeCreationUpdate =
            p['kind'] == 'lab.update' &&
            p['activation'] is String &&
            (p['activation'] as String).startsWith('creation:');
        if (nativeCreationUpdate) {
          if (!isCanonicalId(p['space']) ||
              (config != null && p['space'] != config!.space) ||
              (_spaceId != null && p['space'] != _spaceId)) {
            throw StateError('Wrong native creation space');
          }
          _spaceId = p['space'] as String;
        } else {
          if (config == null ||
              p['space'] != config!.space ||
              p['activation'] != config!.activationRef) {
            throw StateError('Unknown bootstrap context');
          }
        }
        EventClock.fromJson(p['clock']);
        if (p['kind'] == 'lab.activation') {
          if (p['issuer'] != config!.issuer || id != config!.activationRef) {
            throw StateError('Wrong bootstrap issuer');
          }
          if (_activation != null && _digest(_activation) != _digest(p)) {
            throw StateError('Incompatible root');
          }
          _activation = p;
        } else if (p['kind'] == 'lab.update') {
          if (!isCanonicalId(p['writer']) ||
              !isCanonicalId(p['entity']) ||
              !['title', 'description'].contains(p['field']) ||
              p['update'] is! String) {
            throw StateError('Invalid native packet');
          }
          _updates[id] = p;
        } else {
          throw StateError('Unknown required lab meaning');
        }
      }
      _records[id] = raw;
      _reconcile(localId: localReceipt ? id : null);
    } catch (_) {
      isBlocked = true;
      rethrow;
    }
  }

  List<LogEvent> _verifiedLegacy() {
    final result = <LogEvent>[];
    final writers = _legacy.values.map((e) => e.writer).toSet();
    for (final w in writers) {
      var previous = eventGenesisHash(
        _legacy.values.firstWhere((e) => e.writer == w).space,
        w,
      );
      BigInt? clock;
      final entries = _legacy.values.where((e) => e.writer == w).toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      var next = 1;
      for (final e in entries) {
        if (e.sequence != next) break;
        if (e.previousHash != previous ||
            (clock != null && e.clock.value <= clock)) {
          throw StateError('Invalid legacy chain/order');
        }
        result.add(e);
        previous = e.hash!;
        clock = e.clock.value;
        next++;
      }
    }
    return result..sort(compareEvents);
  }

  bool _included(LogEvent e) {
    final head = (_activation!['frontiers'] as Map)[e.writer] as Map?;
    return head != null && e.sequence <= (head['seq'] as int);
  }

  Map<String, Map<String, dynamic>> _rows(List<LogEvent> events) {
    final grouped = <String, List<LogEvent>>{};
    for (final e in events) {
      grouped.putIfAbsent(e.entity, () => []).add(e);
    }
    final derived = <String, List<LogEvent>>{};
    for (final e in events.where(
      (e) => e.type == 'task.completed' && e.data['successor'] != null,
    )) {
      final child = (e.data['successor'] as Map)['id'] as String;
      derived.putIfAbsent(child, () => []).add(e);
    }
    for (final entry in derived.entries) {
      final protected =
          grouped.containsKey(entry.key) ||
          events.any(
            (e) => e.type == 'task.moved' && e.data['before'] == entry.key,
          );
      final selected = selectSuccessor(
        entry.value,
        events.where((e) => e.entity == entry.value.first.entity),
        protected: protected,
      );
      if (!selected.suppressed) {
        grouped
            .putIfAbsent(entry.key, () => [])
            .insert(0, successorCreation(selected.seed));
      }
    }
    final result = <String, Map<String, dynamic>>{};
    for (final entry in grouped.entries) {
      final row = project([...entry.value]);
      if (row != null) result[entry.key] = row;
    }
    return result;
  }

  bool _dependenciesComplete(List<LogEvent> events) {
    final ids = {for (final e in events) e.id: e};
    final created = {
      for (final e in events.where(
        (e) =>
            e.type == 'task.created' ||
            e.type == 'task.createdWithText' ||
            e.type == 'user.created',
      ))
        e.entity: e.type,
    };
    for (final e in events.where(
      (e) => e.type == 'task.completed' && e.data['successor'] != null,
    )) {
      created[(e.data['successor'] as Map)['id'] as String] = 'task.created';
    }
    for (final e in events) {
      if (e.type != 'task.created' &&
          e.type != 'user.created' &&
          !created.containsKey(e.entity)) {
        return false;
      }
      if (e.data['assignee'] != null) {
        final kind = created[e.data['assignee']];
        if (kind == null) return false;
        if (kind != 'user.created') {
          throw StateError('Invalid assignee dependency');
        }
      }
      final reference = e.type == 'task.operationUndone'
          ? e.data['operation']
          : e.data['completion'];
      if (reference != null) {
        final target = ids[reference];
        if (target == null) return false;
        if (target.entity != e.entity || target.clock.compareTo(e.clock) >= 0) {
          throw StateError('Invalid historical dependency');
        }
      }
    }
    return true;
  }

  String prepareActivation() {
    if (config == null || writer != config!.issuer) {
      throw StateError('Explicit issuer required');
    }
    if (_activation != null) return _records[config!.activationRef]!;
    final events = _verifiedLegacy();
    if (!_dependenciesComplete(events)) {
      throw StateError(
        'Missing historical dependency; activation not prepared',
      );
    }
    final frontiers = <String, dynamic>{};
    for (final e in events) {
      frontiers[e.writer] = {'seq': e.sequence, 'hash': e.hash};
    }
    final seeds = _deriveSeeds(events);
    return seal({
      'kind': 'lab.activation',
      'id': config!.activationRef,
      'activation': config!.activationRef,
      'issuer': writer,
      'space': config!.space,
      'clock': EventClock.next(nowNs(), EventClock(maximumObserved)).toJson(),
      'frontiers': frontiers,
      'seedDigest': _digest(seeds),
    });
  }

  String activate() {
    final raw = prepareActivation();
    ingest(raw);
    return raw;
  }

  Map<String, String> _deriveSeeds(List<LogEvent> events) {
    final seeds = <String, String>{};
    for (final row in _rows(events).values.where((r) => r['kind'] == 'task')) {
      for (final field in ['title', 'description']) {
        seeds[_key(row['id'] as String, field)] = row[field] as String;
      }
    }
    return seeds;
  }

  void _reconcile({String? localId}) {
    final verified = _verifiedLegacy();
    _reconcileLegacy(verified);
    for (final creation in verified.where(
      (e) => e.type == 'task.createdWithText',
    )) {
      final user = verified
          .where(
            (e) =>
                e.entity == creation.data['assignee'] &&
                e.type == 'user.created',
          )
          .firstOrNull;
      if (user == null) continue;
      final previous = _nativeCreations[creation.entity];
      if (previous != null && previous.id != creation.id) {
        throw StateError('Duplicate native entity creation');
      }
      for (final field in ['title', 'description']) {
        final seed =
            _bridge.call('seed', {'text': creation.data[field]})['update']
                as String;
        final hash = sha256.convert(base64Decode(seed)).toString();
        if (((creation.data['text'] as Map)['seeds'] as Map)[field] != hash) {
          throw StateError('Native seed mismatch; original record retained');
        }
        _seeds[_key(creation.entity, field)] = creation.data[field] as String;
      }
      _nativeCreations[creation.entity] = creation;
    }
    final updates = _updates.values.toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    for (final p in updates) {
      final entity = p['entity'] as String, field = p['field'] as String;
      final key = _key(entity, field);
      if (!_seeds.containsKey(key)) continue;
      if (p['context'] != context(entity, field) ||
          p['activation'] != _basis(entity)) {
        throw StateError('Wrong field/seed routing');
      }
      final native = _field(entity, field);
      if (native.applied.contains(p['id'])) continue;
      final owned = localId == p['id'] || _outbox[p['id']] == _records[p['id']];
      final undo = _preparedUndos[p['id']];
      if (owned && undo != null) {
        if (undo.name != native.name || undo.update != p['update']) {
          throw StateError('Prepared Undo ownership mismatch');
        }
        _bridge.call('commit_undo', {
          'name': native.name,
          'token': undo.token,
          'receipt': {'update': undo.update},
        });
      } else {
        // A compensation after restart replays as immutable remote history;
        // session Undo ownership is intentionally not reconstructed there.
        _bridge.call(owned && p['intent'] != 'undo' ? 'apply_local' : 'apply', {
          'name': native.name,
          'update': p['update'],
        });
      }
      native.applied.add(p['id'] as String);
    }
  }

  void _reconcileLegacy(List<LogEvent> verified) {
    if (_activation == null) return;
    final prefixes = _activation!['frontiers'] as Map;
    for (final entry in prefixes.entries) {
      final head = entry.value as Map;
      final e = verified
          .where((e) => e.writer == entry.key && e.sequence == head['seq'])
          .firstOrNull;
      if (e == null) return;
      if (e.hash != head['hash']) throw StateError('Baseline head mismatch');
    }
    final basis = verified.where(_included).toList();
    if (!_dependenciesComplete(basis)) return;
    final seeds = _deriveSeeds(basis);
    if (_digest(seeds) != _activation!['seedDigest']) {
      throw StateError('Historical seed mismatch');
    }
    _seeds = seeds;
    // Post-cut new fields initialize from unique production creation context.
    for (final row in _rows(
      verified,
    ).values.where((r) => r['kind'] == 'task')) {
      final entity = row['id'] as String;
      if (!_seeds.containsKey(_key(entity, 'title'))) {
        final creates = verified
            .where((e) => e.entity == entity && e.type == 'task.created')
            .toList();
        if (creates.length == 1) {
          for (final f in ['title', 'description']) {
            _seeds[_key(entity, f)] = creates.single.data[f] as String;
          }
        }
      }
    }
    isActive = true;
  }

  String _basis(String entity) => _nativeCreations.containsKey(entity)
      ? 'creation:${_nativeCreations[entity]!.id}'
      : config!.activationRef;

  String context(String entity, String field) {
    if (!_seeds.containsKey(_key(entity, field))) {
      throw StateError('Field baseline unavailable');
    }
    return _digest({
      'space': config?.space ?? _spaceId,
      'entity': entity,
      'field': field,
      'activation': _basis(entity),
      'codec': 'yrs-v1',
      'seed': _seeds[_key(entity, field)],
    });
  }

  _Field _field(String entity, String field) {
    final key = _key(entity, field);
    return _fields.putIfAbsent(key, () {
      final native = _Field('$name-field-${_serial++}', context(entity, field));
      final seed = _bridge.call('seed', {'text': _seeds[key]})['update'];
      _bridge.call('new', {
        'name': native.name,
        'client': _serial++ + 10000,
        'seed': seed,
      });
      _tryCache(key, native);
      return native;
    });
  }

  Map<String, dynamic> row(String entity) {
    final row = _rows(_verifiedLegacy())[entity];
    if (row == null) throw StateError('Missing entity');
    final result = Map<String, dynamic>.from(row);
    if (_seeds.containsKey(_key(entity, 'title')) && row['kind'] == 'task') {
      for (final f in ['title', 'description']) {
        result[f] = text(entity, f);
      }
    }
    return result;
  }

  String text(String entity, String field) {
    if (!_seeds.containsKey(_key(entity, field))) {
      return _rows(_verifiedLegacy())[entity]?[field] as String? ?? '';
    }
    return _bridge.call('read', {'name': _field(entity, field).name})['text']
        as String;
  }

  bool fieldPending(String entity, String field) =>
      _bridge.call('read', {'name': _field(entity, field).name})['pending'] ==
      true;
  void _ensureWritable([String? entity, String? field]) {
    final available = entity == null
        ? isActive
        : _seeds.containsKey(_key(entity, field!));
    if (!available || isBlocked || _closed) {
      throw StateError('Verified shared baseline required');
    }
  }

  LabDraft begin(String entity, String field, {required String batch}) {
    _ensureWritable(entity, field);
    final native = _field(entity, field);
    final actor =
        (int.parse(
              _digest([context(entity, field), writer, batch]).substring(0, 13),
              radix: 16,
            ) %
            ((1 << 53) - 2)) +
        2;
    final name = 'draft-${_serial++}';
    _bridge.call('draft', {
      'name': name,
      'source': native.name,
      'client': actor,
    });
    final d = LabDraft._(
      this,
      entity,
      field,
      batch,
      DraftValue(text(entity, field)),
      nativeName: name,
      nativeContext: native.context,
    );
    _drafts.add(d);
    return d;
  }

  LabDraft captureLegacyDraft(
    String entity,
    String field, {
    required String base,
    required DraftValue value,
  }) {
    final d = LabDraft._(
      this,
      entity,
      field,
      'legacy-private',
      value,
      capturedScalarBase: base,
    );
    _drafts.add(d);
    return d;
  }

  String _wrap(
    String id,
    String entity,
    String field,
    String update, {
    String? intent,
  }) => seal({
    'kind': 'lab.update',
    'id': '$writer:$id',
    'writer': writer,
    'space': config?.space ?? _spaceId,
    'activation': _basis(entity),
    'entity': entity,
    'field': field,
    'context': context(entity, field),
    'clock': EventClock.next(nowNs(), EventClock(maximumObserved)).toJson(),
    'update': update,
    if (intent != null) 'intent': intent,
  });
  String prepareSave(LabDraft d) {
    _ensureWritable(d.entity, d.field);
    if (d.owner != this ||
        d.nativeContext == null ||
        d.nativeContext != context(d.entity, d.field) ||
        d.closed) {
      throw StateError('Explicit native captured base required');
    }
    if (d.value.composing) throw StateError('Composition active');
    if (d.prepared != null) return d.prepared!;
    final update =
        _bridge.call('prepare', {
              'name': d.nativeName,
              'target': _field(d.entity, d.field).name,
            })['update']
            as String;
    final raw = _wrap(d.batch, d.entity, d.field, update);
    _outbox[_packetId(raw)] = raw;
    if (directory != null) {
      File(
        '${directory!.path}/${_digest(_packetId(raw))}.prepared',
      ).writeAsStringSync(raw, flush: true);
    }
    d.prepared = raw;
    return raw;
  }

  String save(LabDraft draft, {bool failAfterAppend = false}) {
    final raw = prepareSave(draft);
    final result = retryPrepared(raw, failAfterAppend: failAfterAppend);
    if (draft.nativeName != null) {
      _bridge.call('cancel', {'name': draft.nativeName});
    }
    draft.closed = true;
    return result;
  }

  String retryPrepared(String raw, {bool failAfterAppend = false}) {
    final packet = jsonDecode(raw) as Map<String, dynamic>;
    _ensureWritable(packet['entity'] as String, packet['field'] as String);
    _refreshJournal();
    final id = _packetId(raw);
    if (_records[id] == raw) {
      _finishOutbox(id);
      return raw;
    }
    if (_outbox[id] != raw) throw StateError('Unknown prepared bytes');
    _append(raw);
    if (failAfterAppend) throw StateError('Interrupted before receipt');
    _ingest(raw, persist: false, localReceipt: true);
    if (_records[id] != raw) throw StateError('Missing exact receipt');
    _finishOutbox(id);
    return raw;
  }

  void _refreshJournal() {
    if (directory == null) return;
    final f = File('${directory!.path}/records.jsonl');
    if (!f.existsSync()) return;
    final lines = f.readAsStringSync().split('\n');
    final tail = lines.removeLast();
    for (final raw in lines.where((line) => line.isNotEmpty)) {
      _ingest(
        raw,
        persist: false,
        localReceipt: _outbox[_packetId(raw)] == raw,
      );
    }
    if (tail.isNotEmpty) {
      isBlocked = true;
      throw StateError(
        'Incomplete owned journal tail; original bytes retained',
      );
    }
  }

  void _finishOutbox(String id) {
    _outbox.remove(id);
    _preparedUndos.remove(id);
    if (directory != null) {
      final file = File('${directory!.path}/${_digest(id)}.prepared');
      if (file.existsSync()) file.deleteSync();
    }
  }

  String prepareUndo(String entity, String field) {
    _ensureWritable(entity, field);
    final native = _field(entity, field);
    for (final entry in _preparedUndos.entries) {
      if (entry.value.name == native.name) return _outbox[entry.key]!;
    }
    final prepared = _bridge.call('prepare_undo', {'name': native.name});
    final update = prepared['update'] as String;
    final raw = _wrap(
      'undo-${_serial++}',
      entity,
      field,
      update,
      intent: 'undo',
    );
    final id = _packetId(raw);
    _outbox[id] = raw;
    _preparedUndos[id] = _PreparedUndo(
      native.name,
      prepared['token'] as String,
      update,
    );
    if (directory != null) {
      File(
        '${directory!.path}/${_digest(id)}.prepared',
      ).writeAsStringSync(raw, flush: true);
    }
    return raw;
  }

  String undo(String entity, String field) =>
      retryPrepared(prepareUndo(entity, field));

  void writeCache() {
    if (directory == null) throw StateError('No private journal');
    final fields = <String, dynamic>{};
    for (final entry in _fields.entries) {
      final ids = entry.value.applied.toList()..sort();
      final native = _bridge.call('checkpoint', {
        'name': entry.value.name,
      })['checkpoint'];
      fields[entry.key] = {
        'context': entry.value.context,
        'ids': ids,
        'frontierHash': _digest(ids.map((id) => _records[id]).toList()),
        'native': native,
        'nativeHash': _digest(native),
      };
    }
    File('${directory!.path}/cache.json').writeAsStringSync(
      _json({
        'cacheVersion': 1,
        'activationHash': _digest(_activation),
        'fields': fields,
      }),
      flush: true,
    );
  }

  void _tryCache(String key, _Field field) {
    if (directory == null) return;
    final f = File('${directory!.path}/cache.json');
    if (!f.existsSync()) return;
    try {
      final c = jsonDecode(f.readAsStringSync()) as Map;
      final p = (c['fields'] as Map)[key] as Map?;
      if (c['cacheVersion'] != 1 ||
          c['activationHash'] != _digest(_activation) ||
          p == null ||
          p['context'] != field.context ||
          p['nativeHash'] != _digest(p['native'])) {
        return;
      }
      final ids = (p['ids'] as List).cast<String>();
      if (ids.any((id) => !_records.containsKey(id)) ||
          p['frontierHash'] !=
              _digest(ids.map((id) => _records[id]).toList())) {
        return;
      }
      final restored = 'restore-${_serial++}';
      _bridge.call('restore', {
        'name': restored,
        'client': _serial++ + 10000,
        'checkpoint': p['native'],
      });
      _bridge.call('cancel', {'name': field.name});
      // Replace the field handle only after complete validation succeeds.
      field.name = restored;
      field.applied.addAll(ids);
      cacheRestoreCount++;
    } catch (_) {
      /* cache is disposable; original canonical journal retained */
    }
  }

  void close() {
    if (_closed) return;
    for (final d in _drafts) {
      if (!d.closed && d.nativeName != null) {
        try {
          _bridge.call('cancel', {'name': d.nativeName});
        } catch (_) {}
      }
    }
    for (final f in _fields.values) {
      try {
        _bridge.call('cancel', {'name': f.name});
      } catch (_) {}
    }
    _closed = true;
  }
}
