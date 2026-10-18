import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import '../text/native_text_engine.dart';
import 'local_durability.dart';
import 'local_profile_database.dart';
import 'local_profile_migration.dart';
import 'local_settings.dart';
import 'log_folder.dart';
import 'unified_history.dart';
import 'unified_manifest.dart';
import 'unified_record.dart';

/// Trial-only capability. It can create and resume its own direct system-temp
/// children; no API accepts a production workspace or profile for mutation.
class UnifiedTrial {
  UnifiedTrial._(
    this.root,
    this.journal,
    this.plan,
    this.conversion,
    this._state,
  );
  final Directory root;
  final LocalProfileDatabase journal;
  final UnifiedCutoverPlan plan;
  final UnifiedConversion conversion;
  final Map<String, dynamic> _state;
  LocalLogFolder get folder => LocalLogFolder('${root.path}/shared');
  String profileRoot(String writer) {
    if (!plan.participants.contains(writer)) {
      throw FormatFailure('Unknown trial participant.');
    }
    return '${root.path}/profile-$writer';
  }

  String get phase => _state['phase'] as String;
  String get outputDigest => bytesDigest(
    utf8.encode(
      canonicalDataJson({
        'manifest': conversion.manifest.encode(),
        'files': conversion.files.map(
          (name, bytes) => MapEntry(name, bytesDigest(bytes)),
        ),
      }),
    ),
  );

  static Future<UnifiedTrial> createSynthetic({
    required String space,
    required Set<String> owners,
    required Set<String> participants,
    required Map<String, List<int>> sources,
  }) async {
    if (participants.isEmpty) {
      throw FormatFailure('Trial requires a participant.');
    }
    final plan = UnifiedCutoverPlan.inspect(
      space: space,
      owners: owners,
      participants: participants,
      sources: sources,
      hasUnresolvedPreparedWrites: false,
    );
    final conversion = plan.convert(
      participants.map(
        (o) => CutoverAcknowledgement(
          o,
          plan.sourceDigest,
          quiesced: true,
          pendingResolved: true,
        ),
      ),
    );
    final nonce = const Uuid().v4();
    final root = await Directory.systemTemp.createTemp(
      'tandemlog-unified-trial-$nonce-',
    );
    await createFileDurable(
      File('${root.path}/trial.json'),
      utf8.encode(canonicalDataJson({'v': 1, 'nonce': nonce, 'space': space})),
    );
    final shared = await Directory('${root.path}/shared').create();
    final folder = LocalLogFolder(shared.path);
    await folder.create(
      'tandemlog-space.json',
      Uint8List.fromList(utf8.encode(canonicalDataJson({'v': 3, 'id': space}))),
    );
    for (final entry in sources.entries) {
      await folder.create(entry.key, Uint8List.fromList(entry.value));
    }
    final journal = await LocalProfileDatabase.open('${root.path}/journal');
    final state = <String, dynamic>{
      'v': 1,
      'space': space,
      'owners': owners.toList()..sort(),
      'participants': participants.toList()..sort(),
      'sources': sources.map((k, v) => MapEntry(k, base64Encode(v))),
      'sourceDigest': plan.sourceDigest,
      'manifest': conversion.manifest.encode(),
      'outputs': conversion.files.map((k, v) => MapEntry(k, base64Encode(v))),
      'input': <String>[],
      'output': <String>[],
      'retired': <String>[],
      'phase': 'input',
    };
    final result = UnifiedTrial._(root, journal, plan, conversion, state);
    result._save();
    return result;
  }

  static Future<UnifiedTrial> resume(String rootPath) async {
    final root = Directory(rootPath).absolute;
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    if (root.parent.path != temp ||
        !root.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('tandemlog-unified-trial-')) {
      throw FormatFailure('Only owned direct system-temp trials can resume.');
    }
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await root.resolveSymbolicLinks() != root.path) {
      throw FormatFailure('Linked trial root is unsafe.');
    }
    final markerFile = File('${root.path}/trial.json');
    if (await FileSystemEntity.type(markerFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FormatFailure('Trial ownership marker is missing.');
    }
    final marker =
        jsonDecode(await markerFile.readAsString()) as Map<String, dynamic>;
    if (marker.length != 3 ||
        marker['v'] != 1 ||
        !isCanonicalId(marker['nonce']) ||
        !root.path.contains(
          'tandemlog-unified-trial-${marker['nonce'] as String}-',
        )) {
      throw FormatFailure('Invalid trial ownership marker.');
    }
    await _guardRoot(root);
    final journal = await LocalProfileDatabase.open('${root.path}/journal');
    try {
      final row = journal.database
          .select('SELECT * FROM protected_app_migrations')
          .single;
      final state =
          jsonDecode(utf8.decode(row['plan'] as List<int>))
              as Map<String, dynamic>;
      final plan = UnifiedCutoverPlan.inspect(
        space: state['space'] as String,
        owners: (state['owners'] as List).cast<String>().toSet(),
        participants: (state['participants'] as List).cast<String>().toSet(),
        sources: (state['sources'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, base64Decode(v as String)),
        ),
        hasUnresolvedPreparedWrites: false,
      );
      final conversion = plan.convert(
        plan.participants.map(
          (o) => CutoverAcknowledgement(
            o,
            plan.sourceDigest,
            quiesced: true,
            pendingResolved: true,
          ),
        ),
      );
      final outputs = (state['outputs'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, base64Decode(v as String)),
      );
      if (marker['space'] != plan.space ||
          state['v'] != 1 ||
          row['space'] != plan.space ||
          row['epoch'] != conversion.manifest.epoch ||
          row['state'] != state['phase'] ||
          state['sourceDigest'] != plan.sourceDigest ||
          state['manifest'] != conversion.manifest.encode() ||
          canonicalDataJson(
                outputs.map((k, v) => MapEntry(k, bytesDigest(v))),
              ) !=
              canonicalDataJson(
                conversion.files.map((k, v) => MapEntry(k, bytesDigest(v))),
              )) {
        throw FormatFailure('Trial journal differs from its exact conversion.');
      }
      for (final key in ['input', 'output']) {
        final values = (state[key] as List).cast<String>();
        if (values.toSet().length != values.length ||
            !plan.participants.containsAll(values)) {
          throw FormatFailure('Invalid participant acknowledgements.');
        }
      }
      if (!{
        'input',
        'staging',
        'staged',
        'activating',
        'active',
        'retiring',
        'complete',
      }.contains(state['phase'])) {
        throw FormatFailure('Invalid trial phase.');
      }
      return UnifiedTrial._(root, journal, plan, conversion, state);
    } catch (_) {
      await journal.close();
      rethrow;
    }
  }

  void _save() {
    journal.transaction(
      () => journal.database.execute(
        'INSERT OR REPLACE INTO protected_app_migrations VALUES (?,?,?,?)',
        [
          plan.space,
          conversion.manifest.epoch,
          utf8.encode(canonicalDataJson(_state)),
          phase,
        ],
      ),
    );
  }

  void _phase(String value) {
    _state['phase'] = value;
    _save();
  }

  static Future<void> _guardRoot(Directory root) async {
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    if (root.parent.path != temp ||
        await FileSystemEntity.type(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await root.resolveSymbolicLinks() != root.path) {
      throw FormatFailure('Trial root is no longer owned.');
    }
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is Link) throw FormatFailure('Linked trial content is unsafe.');
    }
    final markerFile = File('${root.path}/trial.json');
    if (await FileSystemEntity.type(markerFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FormatFailure('Trial marker is missing.');
    }
    final marker =
        jsonDecode(await markerFile.readAsString()) as Map<String, dynamic>;
    if (marker.length != 3 ||
        marker['v'] != 1 ||
        !isCanonicalId(marker['nonce']) ||
        !root.path.contains(
          'tandemlog-unified-trial-${marker['nonce'] as String}-',
        )) {
      throw FormatFailure('Trial marker differs.');
    }
  }

  Future<void> _owned() => _guardRoot(root);

  Future<LocalProfileDatabase> openParticipant(String writer) async {
    await _owned();
    final p = await LocalProfileDatabase.open(profileRoot(writer));
    if (p.database.select('SELECT 1 FROM protected_settings').isEmpty) {
      p.transaction(() {
        p.database.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
          writer,
          utf8.encode(jsonEncode({'writer': writer, 'appearance': 'system'})),
        ]);
        p.database.execute(
          "INSERT INTO profile_metadata VALUES ('migration.writer',?)",
          [writer],
        );
      });
    }
    if (LocalSettings.protectedValues(p)['writer'] != writer) {
      await p.close();
      throw FormatFailure('Trial participant identity changed.');
    }
    try {
      await LocalProfileMigration(p).run();
      return p;
    } catch (_) {
      await p.close();
      rethrow;
    }
  }

  Future<void> _sources({bool allowRetired = false}) async {
    final names = (await folder.list()).map((i) => i.name).toSet();
    final retired = (_state['retired'] as List).cast<String>().toSet();
    for (final seal in plan.seals) {
      if (allowRetired &&
          retired.contains(seal.name) &&
          !names.contains(seal.name)) {
        continue;
      }
      if (!names.contains(seal.name) ||
          await FileSystemEntity.type(
                folder.file(seal.name).path,
                followLinks: false,
              ) !=
              FileSystemEntityType.file) {
        throw FormatFailure('Expected trial source is missing or linked.');
      }
      final bytes = await folder.readBounded(
        seal.name,
        maximumUnifiedFileBytes,
      );
      if (bytes.length != seal.length || bytesDigest(bytes) != seal.digest) {
        throw FormatFailure(
          'Late legacy write changed the coordinated snapshot.',
        );
      }
    }
    for (final name in names) {
      if ((name.endsWith('.jsonl') || name.endsWith('.foodlog')) &&
          !plan.seals.any((s) => s.name == name)) {
        throw FormatFailure('Unknown legacy writer appeared during cutover.');
      }
    }
  }

  Future<void> acknowledgeInput(
    String writer, {
    NativeTextEngine? textEngine,
  }) async {
    if (phase != 'input') {
      throw FormatFailure('Input acknowledgements are sealed.');
    }
    await _owned();
    await _sources();
    final p = await openParticipant(writer);
    try {
      await UnifiedHistory.preflight(
        _ProspectiveFolder(folder, conversion),
        profile: p,
        writer: writer,
        textEngine: textEngine,
      );
    } finally {
      await p.close();
    }
    if (!(_state['input'] as List).contains(writer)) {
      (_state['input'] as List).add(writer);
      _save();
    }
  }

  bool _all(String key) => (_state[key] as List)
      .cast<String>()
      .toSet()
      .containsAll(plan.participants);
  Future<void> stage({Future<void> Function(String)? checkpoint}) async {
    if (!{'input', 'staging', 'staged'}.contains(phase) || !_all('input')) {
      throw FormatFailure('All quiescent input acknowledgements are required.');
    }
    await _owned();
    await _sources();
    _phase('staging');
    await checkpoint?.call('before-manifest');
    final manifest = folder.file('tandemlog-space.json');
    final raw = await manifest.readAsString();
    final staged = conversion.manifest.staged().encode();
    if (raw != staged) {
      if (raw != canonicalDataJson({'v': 3, 'id': plan.space})) {
        throw FormatFailure('Trial manifest changed.');
      }
      await folder.replaceOwned(
        'tandemlog-space.json',
        Uint8List.fromList(utf8.encode(raw)),
        Uint8List.fromList(utf8.encode(staged)),
      );
    }
    await checkpoint?.call('after-manifest');
    for (final entry in conversion.files.entries) {
      await _owned();
      final file = folder.file(entry.key);
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        await folder.create(entry.key, Uint8List.fromList(entry.value));
      } else {
        if (type != FileSystemEntityType.file) {
          throw FormatFailure('Linked conversion output.');
        }
        final bytes = await folder.readBounded(
          entry.key,
          maximumUnifiedFileBytes,
        );
        if (bytes.length > entry.value.length ||
            bytesDigest(bytes) !=
                bytesDigest(entry.value.take(bytes.length).toList())) {
          throw FormatFailure(
            'Staged output differs from immutable conversion bytes.',
          );
        }
        if (bytes.length < entry.value.length) {
          await folder.append(
            entry.key,
            Uint8List.fromList(entry.value.skip(bytes.length).toList()),
          );
        }
      }
      await checkpoint?.call('after-output:${entry.key}');
    }
    await _sources();
    await _outputs();
    _phase('staged');
  }

  Future<void> _outputs() async {
    for (final info in await folder.list()) {
      if (info.name.contains('.applog') &&
          !conversion.files.containsKey(info.name)) {
        throw FormatFailure(
          'Uncoordinated app history appeared during cutover.',
        );
      }
    }
    for (final entry in conversion.files.entries) {
      if (await FileSystemEntity.type(
                folder.file(entry.key).path,
                followLinks: false,
              ) !=
              FileSystemEntityType.file ||
          bytesDigest(
                await folder.readBounded(entry.key, maximumUnifiedFileBytes),
              ) !=
              bytesDigest(entry.value)) {
        throw FormatFailure('Converted output is missing or changed.');
      }
    }
  }

  Future<void> acknowledgeOutput(
    String writer, {
    NativeTextEngine? textEngine,
  }) async {
    if (phase != 'staged') {
      throw FormatFailure('Complete staged output is required.');
    }
    await _owned();
    await _sources();
    await _outputs();
    final p = await openParticipant(writer);
    try {
      final snapshot = await UnifiedHistory.preflight(
        _ProspectiveFolder(folder, conversion, actualOutputs: true),
        profile: p,
        writer: writer,
        textEngine: textEngine,
      );
      if (snapshot.incomplete || snapshot.pendingEffects) {
        throw FormatFailure('Participant output is not ready.');
      }
    } finally {
      await p.close();
    }
    if (!(_state['output'] as List).contains(writer)) {
      (_state['output'] as List).add(writer);
      _save();
    }
  }

  Future<void> activate({
    NativeTextEngine? textEngine,
    Future<void> Function(String)? checkpoint,
  }) async {
    if (!{'staged', 'activating', 'active'}.contains(phase) ||
        !_all('input') ||
        !_all('output')) {
      throw FormatFailure(
        'Every participant must acknowledge exact staged output.',
      );
    }
    await _owned();
    await _sources();
    await _outputs();
    for (final writer in plan.participants) {
      final p = await openParticipant(writer);
      try {
        await UnifiedHistory.preflight(
          _ProspectiveFolder(folder, conversion, actualOutputs: true),
          profile: p,
          writer: writer,
          textEngine: textEngine,
        );
      } finally {
        await p.close();
      }
    }
    _phase('activating');
    await checkpoint?.call('before-activation');
    await _owned();
    await _sources();
    await _outputs();
    final staged = utf8.encode(conversion.manifest.staged().encode()),
        ready = utf8.encode(conversion.manifest.encode());
    final actual = await folder.read('tandemlog-space.json');
    if (bytesDigest(actual) != bytesDigest(ready)) {
      if (bytesDigest(actual) != bytesDigest(staged)) {
        throw FormatFailure('Activation manifest differs.');
      }
      await folder.replaceOwned(
        'tandemlog-space.json',
        Uint8List.fromList(staged),
        Uint8List.fromList(ready),
      );
    }
    await checkpoint?.call('after-activation');
    await _sources();
    await _outputs();
    _phase('active');
  }

  Future<void> retireSyntheticSources({
    Future<void> Function(String)? checkpoint,
  }) async {
    if (!{'active', 'retiring', 'complete'}.contains(phase) ||
        !_all('output')) {
      throw FormatFailure('Trial is not active.');
    }
    await _owned();
    await _sources(allowRetired: true);
    await _outputs();
    if (await folder.file('tandemlog-space.json').readAsString() !=
        conversion.manifest.encode()) {
      throw FormatFailure('Ready manifest changed before trial cleanup.');
    }
    _phase('retiring');
    for (final seal in plan.seals) {
      await _owned();
      await _sources(allowRetired: true);
      if (!(_state['retired'] as List).contains(seal.name)) {
        (_state['retired'] as List).add(seal.name);
        _save();
      }
      await checkpoint?.call('before-delete:${seal.name}');
      final file = folder.file(seal.name);
      if (await file.exists()) {
        if (bytesDigest(
              await folder.readBounded(seal.name, maximumUnifiedFileBytes),
            ) !=
            seal.digest) {
          throw FormatFailure('Late write blocks cleanup.');
        }
        await file.delete();
        await syncParentAfterCreate(file);
      }
      await checkpoint?.call('after-delete:${seal.name}');
    }
    await _sources(allowRetired: true);
    _phase('complete');
  }

  Future<void> close() => journal.close();
}

/// Prospective reads use exact planned bytes only after the caller has checked
/// actual sources/output. It never writes or binds an installation.
class _ProspectiveFolder implements LogFolder, BoundedLogFolder {
  _ProspectiveFolder(this.inner, this.conversion, {this.actualOutputs = false});
  final LocalLogFolder inner;
  final UnifiedConversion conversion;
  final bool actualOutputs;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() async => [
    ...(await inner.list()).where(
      (f) =>
          f.name != 'tandemlog-space.json' &&
          (actualOutputs || !f.name.endsWith('.applog')),
    ),
    LogFileInfo('tandemlog-space.json', 'prospective'),
    if (!actualOutputs)
      ...conversion.files.keys.map((n) => LogFileInfo(n, 'prospective')),
  ];
  @override
  Future<Uint8List> read(String name) async {
    if (name == 'tandemlog-space.json') {
      return Uint8List.fromList(utf8.encode(conversion.manifest.encode()));
    }
    if (!actualOutputs && conversion.files.containsKey(name)) {
      return Uint8List.fromList(conversion.files[name]!);
    }
    return inner.read(name);
  }

  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) async {
    final bytes = await read(name);
    if (bytes.length > maximumBytes) {
      throw FormatFailure('Prospective history exceeds read budget.');
    }
    return bytes;
  }

  @override
  Future<void> append(String name, Uint8List bytes) =>
      throw UnsupportedError('Read-only preflight');
  @override
  Future<void> create(String name, Uint8List bytes) =>
      throw UnsupportedError('Read-only preflight');
}
