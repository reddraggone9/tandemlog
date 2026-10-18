import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import '../food/food_record.dart';
import '../text/native_text_engine.dart';
import 'local_profile_database.dart';
import 'local_settings.dart';
import 'log_folder.dart';
import 'unified_history.dart';
import 'unified_manifest.dart';
import 'unified_record.dart';
import 'workspace_upgrade_guard.dart';

const workspaceUpgradeSessionName = 'tandemlog-upgrade.json';

class WorkspaceUpgradeInventory {
  WorkspaceUpgradeInventory(
    this.space,
    this.owners,
    this.sourceNames,
    this.unresolvedFoodNames,
  );
  final String space;
  final Set<String> owners;
  final List<String> sourceNames, unresolvedFoodNames;
}

/// Explicit app-owned upgrade. Each locked profile attests only its own state.
/// Sync folders provide neither a distributed lock nor proof about absent clients.
class WorkspaceUpgrade {
  // This queue is separate from the profile SQL queue: preflight itself uses
  // that queue. It serializes only this app-owned protocol's control operations.
  static final _controls = Expando<Future<void>>();
  static Future<T> _control<T>(
    LocalProfileDatabase profile,
    Future<T> Function() operation,
  ) {
    final result = (_controls[profile] ?? Future<void>.value()).then(
      (_) => operation(),
    );
    _controls[profile] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  WorkspaceUpgrade._(
    this.folder,
    this.profile,
    this.writer,
    this.textEngine,
    this._session,
    this._state,
    this.plan,
    this.conversion,
  );
  final LogFolder folder;
  final LocalProfileDatabase profile;
  final String writer;
  final NativeTextEngine? textEngine;
  final Map<String, dynamic> _session, _state;
  final UnifiedCutoverPlan plan;
  final UnifiedConversion conversion;
  Set<String> _inputs = {}, _outputs = {};
  String _phase = 'input';
  String get phase => _phase;
  bool get canResumeStaging => isCoordinator && _state['phase'] == 'staging';
  bool get canResumeActivation =>
      isCoordinator && _state['phase'] == 'activating';
  bool get canAbort =>
      isCoordinator && {'input', 'invalidated'}.contains(phase);
  String get space => plan.space;
  String get coordinator => _session['coordinator'] as String;
  String get sessionId => _session['session'] as String;
  Set<String> get participants => plan.participants;
  Set<String> get owners => plan.owners;
  Set<String> get inputAcknowledged => Set.unmodifiable(_inputs);
  Set<String> get outputAcknowledged => Set.unmodifiable(_outputs);
  bool get isCoordinator => writer == coordinator;
  bool get isParticipant => participants.contains(writer);
  bool get hasLocalConsent => _state['consented'] == true;
  Future<void> consentToUpgrade() => _control(profile, () async {
    _participant();
    _state['consented'] = true;
    await _save(_state['phase'] as String);
  });
  String get sessionDigest =>
      bytesDigest(utf8.encode(canonicalDataJson(_session)));
  String get outputDigest => _conversionDigest(conversion);
  String get _abortName => 'upgrade-$sessionId-aborted.json';
  String get _stagingName => 'upgrade-$sessionId-staging.json';
  String get _invalidName => 'upgrade-$sessionId-invalid.json';

  static bool isFrozen(LocalProfileDatabase profile, String space) =>
      WorkspaceUpgradeGuard.isFrozen(profile, space);

  static Future<Uint8List> _read(
    LogFolder folder,
    String name,
    int limit,
  ) async {
    if (folder is LocalLogFolder &&
        await FileSystemEntity.type(
              folder.file(name).path,
              followLinks: false,
            ) !=
            FileSystemEntityType.file) {
      throw FormatFailure('Linked or missing upgrade input is unsafe.');
    }
    if (folder is! BoundedLogFolder) {
      throw FormatFailure('This folder cannot enforce upgrade read limits.');
    }
    return (folder as BoundedLogFolder).readBounded(name, limit);
  }

  static bool _equal(List<int> a, List<int> b) =>
      a.length == b.length && bytesDigest(a) == bytesDigest(b);
  static String _conversionDigest(UnifiedConversion c) => bytesDigest(
    utf8.encode(
      canonicalDataJson({
        'manifest': c.manifest.encode(),
        'files': c.files.map((n, b) => MapEntry(n, bytesDigest(b))),
      }),
    ),
  );
  static void _identity(LocalProfileDatabase profile, String writer) {
    if (!isCanonicalId(writer) ||
        LocalSettings.protectedValues(profile)['writer'] != writer) {
      throw FormatFailure(
        'Upgrade installation differs from protected identity.',
      );
    }
  }

  static Future<WorkspaceUpgradeInventory> inspect(
    LogFolder folder, {
    required String writer,
    Set<String> knownOwners = const {},
  }) async {
    if (!isCanonicalId(writer) || knownOwners.any((o) => !isCanonicalId(o))) {
      throw FormatFailure('Invalid installation identity.');
    }
    final raw = await _read(folder, 'tandemlog-space.json', 1024 * 1024);
    final j = jsonDecode(utf8.decode(raw));
    if (j is! Map || j.length != 2 || j['v'] != 3 || !isCanonicalId(j['id'])) {
      throw FormatFailure('Only an existing v3 workspace can be upgraded.');
    }
    if (folder is LocalLogFolder) {
      await for (final entry in Directory(
        folder.location,
      ).list(followLinks: false)) {
        final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (entry is Link &&
            (name.endsWith('.jsonl') ||
                name.endsWith('.foodlog') ||
                name.contains('.applog') ||
                name == workspaceUpgradeSessionName)) {
          throw FormatFailure('Linked canonical history is unsafe.');
        }
      }
    }
    final names = (await folder.list()).map((f) => f.name).toList()..sort();
    if (names.toSet().length != names.length) {
      throw FormatFailure('Ambiguous workspace filenames.');
    }
    final candidates = <String>{writer, ...knownOwners};
    final owners = <String>{}, sources = <String>[], unresolved = <String>[];
    for (final name in names) {
      if (name.endsWith('.jsonl')) {
        final id = name.substring(0, name.length - 6);
        if (!isCanonicalId(id)) {
          throw FormatFailure('Unrecognized legacy Task file $name');
        }
        owners.add(id);
        candidates.add(id);
        sources.add(name);
      } else if (name.endsWith('.foodlog')) {
        sources.add(name);
      } else if (name.contains('.applog') || name.contains('sync-conflict')) {
        throw FormatFailure(
          'Conflicting or pre-existing app history blocks upgrade.',
        );
      }
    }
    for (final name in sources.where((n) => n.endsWith('.foodlog'))) {
      final matches = candidates
          .where((o) => foodLogName(foodWriter(o)) == name)
          .toList();
      if (matches.length != 1) {
        unresolved.add(name);
      } else {
        owners.add(matches.single);
      }
    }
    // Empty workspaces still need one empty genesis owner; other active devices
    // are participants, not fabricated historical owners.
    if (owners.isEmpty && sources.isEmpty) owners.add(writer);
    return WorkspaceUpgradeInventory(
      j['id'] as String,
      Set.unmodifiable(owners),
      List.unmodifiable(sources),
      List.unmodifiable(unresolved),
    );
  }

  static Future<WorkspaceUpgrade> start({
    required LogFolder folder,
    required LocalProfileDatabase profile,
    required String writer,
    required Set<String> participants,
    Set<String> knownOwners = const {},
    NativeTextEngine? textEngine,
  }) => _control(
    profile,
    () => _start(
      folder: folder,
      profile: profile,
      writer: writer,
      participants: participants,
      knownOwners: knownOwners,
      textEngine: textEngine,
    ),
  );

  static Future<WorkspaceUpgrade> _start({
    required LogFolder folder,
    required LocalProfileDatabase profile,
    required String writer,
    required Set<String> participants,
    Set<String> knownOwners = const {},
    NativeTextEngine? textEngine,
  }) async {
    _identity(profile, writer);
    if (!participants.contains(writer) ||
        participants.isEmpty ||
        participants.length > 256 ||
        participants.any((o) => !isCanonicalId(o))) {
      throw FormatFailure(
        'Choose this installation and every participating device.',
      );
    }
    if (folder is! CheckedReplaceLogFolder) {
      throw FormatFailure(
        'This folder cannot safely replace the activation manifest.',
      );
    }
    await (folder as CheckedReplaceLogFolder).checkReplacementSupport(
      'tandemlog-space.json',
      1024 * 1024,
    );
    final names = (await folder.list()).map((f) => f.name).toSet();
    Uint8List? oldSession;
    if (names.contains(workspaceUpgradeSessionName)) {
      oldSession = await _read(
        folder,
        workspaceUpgradeSessionName,
        1024 * 1024,
      );
      final old = WorkspaceUpgradeGuard.decodeSession(oldSession);
      final abort = 'upgrade-${old['session'] as String}-aborted.json';
      if (!names.contains(abort)) {
        throw FormatFailure('An upgrade already exists. Resume it instead.');
      }
      await _validateAbort(folder, old);
    }
    final result = await profile.serialize(() async {
      final inventory = await inspect(
        folder,
        writer: writer,
        knownOwners: {...knownOwners, ...participants, writer},
      );
      if (WorkspaceUpgradeGuard.isFrozen(profile, inventory.space)) {
        throw FormatFailure(
          'An unfinished upgrade already owns this workspace in this profile. Resume or cancel it before starting another.',
        );
      }
      if (inventory.owners.length > 256 || inventory.sourceNames.length > 512) {
        throw FormatFailure(
          'The workspace exceeds safe upgrade inventory limits.',
        );
      }
      if (inventory.unresolvedFoodNames.isNotEmpty) {
        throw FormatFailure(
          'Some Food histories have no verified installation owner. '
          'Use their original device identity or trusted identity backup.',
        );
      }
      final manifest = await _read(folder, 'tandemlog-space.json', 1024 * 1024);
      final sources = <String, List<int>>{};
      final infos = await folder.list();
      var declaredBytes = 0;
      for (final info in infos.where(
        (f) => inventory.sourceNames.contains(f.name),
      )) {
        final size = info.size;
        if (size != null) {
          if (size < 0 || size > maximumUnifiedFileBytes) {
            throw FormatFailure(
              'Legacy source exceeds safe upgrade read limits.',
            );
          }
          declaredBytes += size;
          if (declaredBytes > maximumUnifiedWorkspaceBytes) {
            throw FormatFailure(
              'Legacy sources exceed the safe workspace budget.',
            );
          }
        }
      }
      var totalBytes = 0;
      for (final n in inventory.sourceNames) {
        final remaining = maximumUnifiedWorkspaceBytes - totalBytes;
        final limit = remaining < maximumUnifiedFileBytes
            ? remaining
            : maximumUnifiedFileBytes;
        final bytes = await _read(folder, n, limit);
        totalBytes += bytes.length;
        if (totalBytes > maximumUnifiedWorkspaceBytes) {
          throw FormatFailure(
            'Legacy sources exceed the safe workspace budget.',
          );
        }
        sources[n] = bytes;
      }
      final plan = UnifiedCutoverPlan.inspect(
        space: inventory.space,
        owners: inventory.owners,
        participants: participants,
        sources: sources,
        hasUnresolvedPreparedWrites: false,
      );
      final conversion = plan.prepareConversion();
      final session = <String, dynamic>{
        'v': 1,
        'session': const Uuid().v4(),
        'space': plan.space,
        'coordinator': writer,
        'participants': participants.toList()..sort(),
        'owners': plan.owners.toList()..sort(),
        'sourceDigest': plan.sourceDigest,
        'outputDigest': _conversionDigest(conversion),
        'manifestDigest': bytesDigest(manifest),
        'manifest': base64Encode(manifest),
        'sources': plan.seals.map((s) => s.toJson()).toList(),
      };
      if (utf8.encode(canonicalDataJson(session)).length > 1024 * 1024) {
        throw FormatFailure(
          'Upgrade coordination manifest exceeds safe limits.',
        );
      }
      WorkspaceUpgradeGuard.decodeSession(
        utf8.encode(canonicalDataJson(session)),
      );
      final state = <String, dynamic>{
        'kind': 'workspace-upgrade-v1',
        'session': session,
        'location': folder.location,
        'manifest': base64Encode(manifest),
        'sources': sources.map((n, b) => MapEntry(n, base64Encode(b))),
        'phase': 'frozen',
        'consented': true,
      };
      final prepared = WorkspaceUpgrade._(
        folder,
        profile,
        writer,
        textEngine,
        session,
        state,
        plan,
        conversion,
      );
      prepared._saveNow('frozen');
      return prepared;
    });
    // Freeze before queued commands can reserve new writes. A failed local
    // preflight has published nothing, so it can release only its own freeze.
    try {
      final snapshot = await result._preflight(actualOutputs: false);
      if (snapshot.incomplete || snapshot.pendingEffects) {
        throw FormatFailure(
          'Resolve incomplete history before starting upgrade.',
        );
      }
    } catch (_) {
      await result._save('aborted');
      rethrow;
    }
    await result._checkSources();
    final bytes = utf8.encode(canonicalDataJson(result._session));
    result._state['sessionPublication'] = {
      'expected': oldSession == null ? null : base64Encode(oldSession),
      'desired': base64Encode(bytes),
    };
    await result._save('frozen');
    if (oldSession == null) {
      await result._createExact(workspaceUpgradeSessionName, bytes);
    } else {
      await (folder as CheckedReplaceLogFolder).replaceOwned(
        workspaceUpgradeSessionName,
        oldSession,
        Uint8List.fromList(bytes),
      );
    }
    await result._refresh();
    return result;
  }

  static Future<WorkspaceUpgrade?> open({
    required LogFolder folder,
    required LocalProfileDatabase profile,
    required String writer,
    NativeTextEngine? textEngine,
  }) => _control(
    profile,
    () => _open(
      folder: folder,
      profile: profile,
      writer: writer,
      textEngine: textEngine,
    ),
  );

  static WorkspaceUpgrade _validatedRecovery({
    required LogFolder folder,
    required LocalProfileDatabase profile,
    required String writer,
    required NativeTextEngine? textEngine,
    required Map<String, dynamic> state,
    required String rowSpace,
    required String rowEpoch,
    required String rowPhase,
  }) {
    final session = WorkspaceUpgradeGuard.decodeSession(
      utf8.encode(canonicalDataJson(state['session'])),
      space: rowSpace,
    );
    if (state['kind'] != 'workspace-upgrade-v1' ||
        state['phase'] != rowPhase ||
        state['location'] != folder.location ||
        state['consented'] != true ||
        state['manifest'] != session['manifest'] ||
        session['session'] != rowEpoch ||
        session['coordinator'] != writer ||
        state['sources'] is! Map ||
        !{
          'frozen',
          'input',
          'staging',
          'staged',
          'output',
          'activating',
        }.contains(rowPhase)) {
      throw FormatFailure('Protected upgrade recovery binding is invalid.');
    }
    final sources = <String, List<int>>{};
    var total = 0;
    for (final entry in (state['sources'] as Map).entries) {
      if (entry.key is! String || entry.value is! String) {
        throw FormatFailure('Protected source backup is invalid.');
      }
      final bytes = base64Decode(entry.value as String);
      total += bytes.length;
      if (bytes.length > maximumUnifiedFileBytes ||
          total > maximumUnifiedWorkspaceBytes ||
          base64Encode(bytes) != entry.value) {
        throw FormatFailure(
          'Protected source backup exceeds its exact budget.',
        );
      }
      sources[entry.key as String] = bytes;
    }
    final plan = UnifiedCutoverPlan.inspect(
      space: rowSpace,
      owners: (session['owners'] as List).cast<String>().toSet(),
      participants: (session['participants'] as List).cast<String>().toSet(),
      sources: sources,
      hasUnresolvedPreparedWrites: false,
    );
    final conversion = plan.prepareConversion();
    if (plan.sourceDigest != session['sourceDigest'] ||
        _conversionDigest(conversion) != session['outputDigest'] ||
        canonicalDataJson(plan.seals.map((s) => s.toJson()).toList()) !=
            canonicalDataJson(session['sources'])) {
      throw FormatFailure(
        'Protected recovery snapshot differs from its session.',
      );
    }
    final publication = state['sessionPublication'];
    if (publication != null) {
      if (publication is! Map ||
          publication.length != 2 ||
          publication['desired'] !=
              base64Encode(utf8.encode(canonicalDataJson(session))) ||
          (publication['expected'] != null &&
              publication['expected'] is! String)) {
        throw FormatFailure('Protected session publication intent differs.');
      }
      if (publication['expected'] is String) {
        final old = base64Decode(publication['expected'] as String);
        final oldSession = WorkspaceUpgradeGuard.decodeSession(
          old,
          space: rowSpace,
        );
        if (base64Encode(old) != publication['expected'] ||
            oldSession['session'] == session['session']) {
          throw FormatFailure('Protected previous session is invalid.');
        }
      }
    }
    return WorkspaceUpgrade._(
      folder,
      profile,
      writer,
      textEngine,
      session,
      state,
      plan,
      conversion,
    );
  }

  static Future<WorkspaceUpgrade?> _open({
    required LogFolder folder,
    required LocalProfileDatabase profile,
    required String writer,
    NativeTextEngine? textEngine,
  }) async {
    _identity(profile, writer);
    final names = (await folder.list()).map((f) => f.name).toSet();
    if (!names.contains(workspaceUpgradeSessionName)) {
      final orphaned = names.any(WorkspaceUpgradeGuard.isUpgradeArtifact);
      for (final row in profile.database.select(
        'SELECT space,epoch,plan,state FROM protected_app_migrations',
      )) {
        final state = jsonDecode(utf8.decode(row['plan'] as List<int>));
        if (state is Map &&
            state['kind'] == 'workspace-upgrade-v1' &&
            state['location'] == folder.location &&
            row['state'] != 'complete' &&
            row['state'] != 'aborted') {
          final session = Map<String, dynamic>.from(state['session'] as Map);
          if (session['coordinator'] != writer) {
            throw FormatFailure('The coordinated upgrade session is missing.');
          }
          final recovery = _validatedRecovery(
            folder: folder,
            profile: profile,
            writer: writer,
            textEngine: textEngine,
            state: Map<String, dynamic>.from(state),
            rowSpace: row['space'] as String,
            rowEpoch: row['epoch'] as String,
            rowPhase: row['state'] as String,
          );
          await recovery._checkRecoveryManifest();
          await recovery._checkSources();
          if (state['sessionPublication'] == null) {
            final snapshot = await recovery._preflight(actualOutputs: false);
            if (snapshot.incomplete || snapshot.pendingEffects) {
              throw FormatFailure(
                'Resolve incomplete history before resuming publication.',
              );
            }
          }
          await folder.create(
            workspaceUpgradeSessionName,
            Uint8List.fromList(utf8.encode(canonicalDataJson(session))),
          );
          return _open(
            folder: folder,
            profile: profile,
            writer: writer,
            textEngine: textEngine,
          );
        }
      }
      if (orphaned) {
        final rawManifest = await _read(
          folder,
          'tandemlog-space.json',
          1024 * 1024,
        );
        final manifest = UnifiedManifest.decode(utf8.decode(rawManifest));
        if (manifest.ready &&
            !WorkspaceUpgradeGuard.isFrozen(profile, manifest.space)) {
          return null; // Released v4 workspace; its ordinary reader verifies logs.
        }
      }
      if (orphaned) {
        throw FormatFailure(
          'Upgrade files arrived before their session. Wait for folder sync or resume on the initiating device.',
        );
      }
      return null;
    }
    var raw = await _read(folder, workspaceUpgradeSessionName, 1024 * 1024);
    Object? preliminary;
    try {
      preliminary = jsonDecode(utf8.decode(raw));
    } catch (_) {
      /* Journal repair below. */
    }
    final needsSessionRepair =
        preliminary is! Map ||
        preliminary['session'] is! String ||
        names.contains(
          'upgrade-${preliminary['session'] as String}-aborted.json',
        );
    if (needsSessionRepair) {
      for (final row in profile.database.select(
        'SELECT space,epoch,plan,state FROM protected_app_migrations',
      )) {
        final candidate = jsonDecode(utf8.decode(row['plan'] as List<int>));
        if (candidate is! Map ||
            candidate['kind'] != 'workspace-upgrade-v1' ||
            candidate['location'] != folder.location ||
            {'complete', 'aborted'}.contains(row['state'])) {
          continue;
        }
        final intendedSession = candidate['session'] as Map;
        final publication = candidate['sessionPublication'];
        if (intendedSession['coordinator'] != writer || publication is! Map) {
          continue;
        }
        final recovery = _validatedRecovery(
          folder: folder,
          profile: profile,
          writer: writer,
          textEngine: textEngine,
          state: Map<String, dynamic>.from(candidate),
          rowSpace: row['space'] as String,
          rowEpoch: row['epoch'] as String,
          rowPhase: row['state'] as String,
        );
        await recovery._checkRecoveryManifest();
        await recovery._checkSources();
        final desired = base64Decode(publication['desired'] as String);
        if (_equal(raw, desired)) break;
        final expected = publication['expected'] == null
            ? null
            : base64Decode(publication['expected'] as String);
        final partial =
            raw.length < desired.length &&
            _equal(raw, desired.take(raw.length).toList());
        if (!partial && (expected == null || !_equal(raw, expected))) continue;
        if (folder is! CheckedReplaceLogFolder) {
          throw FormatFailure(
            'Resume this interrupted upgrade on a capable folder provider.',
          );
        }
        if (folder is RecoverableReplaceLogFolder) {
          await (folder as RecoverableReplaceLogFolder).recoverOwned(
            workspaceUpgradeSessionName,
            raw,
            desired,
          );
        } else {
          await (folder as CheckedReplaceLogFolder).replaceOwned(
            workspaceUpgradeSessionName,
            raw,
            desired,
          );
        }
        raw = await _read(folder, workspaceUpgradeSessionName, 1024 * 1024);
        break;
      }
    }
    final session = WorkspaceUpgradeGuard.decodeSession(raw);
    final participants = (session['participants'] as List)
        .cast<String>()
        .toSet();
    final owners = (session['owners'] as List).cast<String>().toSet();
    final space = session['space'] as String, id = session['session'] as String;
    for (final prior in profile.database.select(
      'SELECT epoch,state FROM protected_app_migrations WHERE space=?',
      [space],
    )) {
      if (prior['epoch'] != id &&
          !{'complete', 'aborted'}.contains(prior['state'])) {
        throw FormatFailure(
          'A different protected upgrade owns this workspace. Preserve both sessions.',
        );
      }
    }
    final completed = profile.database.select(
      'SELECT state FROM protected_app_migrations WHERE space=? AND epoch=?',
      [space, id],
    );
    if (completed.isNotEmpty && completed.single['state'] == 'complete') {
      final receiptRows = profile.database.select(
        'SELECT value FROM profile_metadata WHERE key=?',
        ['upgrade.complete:$space:$id'],
      );
      if (receiptRows.isNotEmpty) {
        final receipt = jsonDecode(receiptRows.single['value'] as String);
        if (receipt is! Map ||
            receipt.length != 5 ||
            receipt['v'] != 1 ||
            receipt['writer'] != writer ||
            receipt['location'] != folder.location ||
            receipt['sessionDigest'] != bytesDigest(raw) ||
            receipt['manifest'] is! String ||
            utf8.decode(
                  await _read(folder, 'tandemlog-space.json', 1024 * 1024),
                ) !=
                receipt['manifest']) {
          throw FormatFailure(
            'Completed upgrade differs from protected activation.',
          );
        }
        if (WorkspaceUpgradeGuard.isFrozen(profile, space)) {
          throw FormatFailure(
            'Another unfinished upgrade must be recovered first.',
          );
        }
        return null;
      }
    }
    if (names.contains('upgrade-$id-aborted.json')) {
      await _validateAbort(folder, session);
      final prior = profile.database.select(
        'SELECT plan FROM protected_app_migrations WHERE space=? AND epoch=?',
        [space, id],
      );
      if (prior.isNotEmpty) {
        final state = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(prior.single['plan'] as List<int>)) as Map,
        );
        state['phase'] = 'aborted';
        await profile.serialize(() async {
          profile.transaction(
            () => profile.database.execute(
              'UPDATE protected_app_migrations SET plan=?,state=? WHERE space=? AND epoch=?',
              [utf8.encode(canonicalDataJson(state)), 'aborted', space, id],
            ),
          );
        });
      }
      return null;
    }
    final rows = profile.database.select(
      'SELECT plan,state FROM protected_app_migrations WHERE space=? AND epoch=?',
      [space, id],
    );
    Map<String, dynamic> state;
    if (rows.isNotEmpty) {
      state = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(rows.single['plan'] as List<int>)) as Map,
      );
      if (state['kind'] != 'workspace-upgrade-v1' ||
          state['location'] != folder.location ||
          canonicalDataJson(state['session']) != canonicalDataJson(session) ||
          state['phase'] != rows.single['state']) {
        throw FormatFailure(
          'Protected upgrade journal differs from the shared session.',
        );
      }
    } else {
      final sources = <String, String>{};
      var totalBytes = 0;
      for (final item in session['sources'] as List) {
        final seal = LegacySeal.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        totalBytes += seal.length;
        if (seal.length < 0 ||
            seal.length > maximumUnifiedFileBytes ||
            totalBytes > maximumUnifiedWorkspaceBytes ||
            sources.containsKey(seal.name)) {
          throw FormatFailure('Upgrade source snapshot exceeds safe limits.');
        }
        final bytes = await _read(folder, seal.name, maximumUnifiedFileBytes);
        if (bytes.length != seal.length || bytesDigest(bytes) != seal.digest) {
          throw FormatFailure(
            'This device has not received the sealed source snapshot.',
          );
        }
        sources[seal.name] = base64Encode(bytes);
      }
      state = {
        'kind': 'workspace-upgrade-v1',
        'session': session,
        'location': folder.location,
        'manifest': session['manifest'],
        'sources': sources,
        'phase': 'frozen',
        'consented': false,
      };
    }
    final manifest = base64Decode(state['manifest'] as String);
    final original = jsonDecode(utf8.decode(manifest));
    if (bytesDigest(manifest) != session['manifestDigest'] ||
        original is! Map ||
        original['v'] != 3 ||
        original['id'] != space) {
      throw FormatFailure('Original manifest backup differs.');
    }
    final plan = UnifiedCutoverPlan.inspect(
      space: space,
      owners: owners,
      participants: participants,
      sources: (state['sources'] as Map).map(
        (n, b) => MapEntry(n as String, base64Decode(b as String)),
      ),
      hasUnresolvedPreparedWrites: false,
    );
    final conversion = plan.prepareConversion();
    if (plan.sourceDigest != session['sourceDigest'] ||
        _conversionDigest(conversion) != session['outputDigest'] ||
        canonicalDataJson(plan.seals.map((s) => s.toJson()).toList()) !=
            canonicalDataJson(session['sources'])) {
      throw FormatFailure('Upgrade plan differs from sealed conversion.');
    }
    final result = WorkspaceUpgrade._(
      folder,
      profile,
      writer,
      textEngine,
      session,
      state,
      plan,
      conversion,
    );
    if (participants.contains(writer)) {
      await result._save(state['phase'] as String);
    }
    await result._refresh();
    return result;
  }

  static Future<void> _validateAbort(
    LogFolder folder,
    Map<String, dynamic> session,
  ) async {
    final id = session['session'] as String;
    final names = (await folder.list()).map((f) => f.name).toSet();
    final expected = canonicalDataJson({
      'v': 1,
      'session': id,
      'sessionDigest': bytesDigest(utf8.encode(canonicalDataJson(session))),
      'coordinator': session['coordinator'],
    });
    final raw = await _read(folder, 'upgrade-$id-aborted.json', 16384);
    if (utf8.decode(raw) != expected ||
        names.contains('upgrade-$id-staging.json') ||
        names.any((n) => n.contains('.applog')) ||
        !_equal(
          await _read(folder, 'tandemlog-space.json', 1024 * 1024),
          base64Decode(session['manifest'] as String),
        )) {
      throw FormatFailure(
        'Upgrade cancellation is not safe; preserve the folder.',
      );
    }
  }

  Future<void> _save(String phase) => profile.serialize(() async {
    _saveNow(phase);
  });

  void _saveNow(String phase) {
    final durableState = {..._state, 'phase': phase};
    profile.transaction(() {
      profile.database.execute(
        'INSERT OR REPLACE INTO protected_app_migrations VALUES (?,?,?,?)',
        [space, sessionId, utf8.encode(canonicalDataJson(durableState)), phase],
      );
      if (phase == 'complete') {
        profile.database.execute(
          'INSERT OR REPLACE INTO profile_metadata VALUES (?,?)',
          [
            'upgrade.complete:$space:$sessionId',
            canonicalDataJson({
              'v': 1,
              'writer': writer,
              'location': folder.location,
              'sessionDigest': sessionDigest,
              'manifest': conversion.manifest.encode(),
            }),
          ],
        );
      }
    });
    _state['phase'] = phase;
  }

  Future<void> _checkRecoveryManifest() async {
    final actual = await _read(folder, 'tandemlog-space.json', 1024 * 1024);
    final original = base64Decode(_state['manifest'] as String);
    final staged = utf8.encode(conversion.manifest.staged().encode());
    final ready = utf8.encode(conversion.manifest.encode());
    if (_equal(actual, original) ||
        _equal(actual, staged) ||
        _equal(actual, ready)) {
      return;
    }
    final phase = _state['phase'];
    final expected = phase == 'staging' ? original : staged;
    final desired = phase == 'staging' ? staged : ready;
    final intent = _state['replacement'];
    if ({'staging', 'activating'}.contains(phase) &&
        intent is Map &&
        intent.length == 2 &&
        intent['expected'] == base64Encode(expected) &&
        intent['desired'] == base64Encode(desired) &&
        actual.length < desired.length &&
        _equal(actual, desired.take(actual.length).toList())) {
      return;
    }
    throw FormatFailure(
      'The workspace manifest differs from this protected upgrade. '
      'Preserve both before recovery.',
    );
  }

  Future<void> _checkSession({bool allowInvalid = false}) async {
    if (!_equal(
      await _read(folder, workspaceUpgradeSessionName, 1024 * 1024),
      utf8.encode(canonicalDataJson(_session)),
    )) {
      throw FormatFailure('The shared upgrade coordinator/session changed.');
    }
    final names = (await folder.list()).map((f) => f.name).toSet();
    if (names.contains(_abortName)) {
      throw FormatFailure('This upgrade was cancelled.');
    }
    if (!allowInvalid && names.contains(_invalidName)) {
      throw FormatFailure(
        'The sealed source changed. Previous acknowledgements are invalid.',
      );
    }
  }

  Future<void> _checkSources() async {
    final names = (await folder.list()).map((f) => f.name).toSet();
    var changed = false;
    for (final seal in plan.seals) {
      if (!names.contains(seal.name)) {
        changed = true;
        break;
      }
      final bytes = await _read(folder, seal.name, maximumUnifiedFileBytes);
      if (bytes.length != seal.length || bytesDigest(bytes) != seal.digest) {
        changed = true;
        break;
      }
    }
    if (names.any(
          (n) =>
              (n.endsWith('.jsonl') || n.endsWith('.foodlog')) &&
              !plan.seals.any((s) => s.name == n),
        ) ||
        names.any((n) => n.contains('sync-conflict'))) {
      changed = true;
    }
    if (changed) {
      if (names.contains(workspaceUpgradeSessionName)) {
        await _createExact(
          _invalidName,
          utf8.encode(
            canonicalDataJson({
              'v': 1,
              'session': sessionId,
              'snapshot': plan.sourceDigest,
            }),
          ),
        );
      }
      throw FormatFailure(
        'Late legacy writes changed the coordinated snapshot. '
        'Previous acknowledgements cannot activate it.',
      );
    }
  }

  Future<void> _createExact(String name, List<int> bytes) async {
    final names = (await folder.list()).map((f) => f.name).toSet();
    if (!names.contains(name)) {
      await folder.create(name, Uint8List.fromList(bytes));
    }
    if (!_equal(await _read(folder, name, maximumUnifiedFileBytes), bytes)) {
      throw FormatFailure(
        'Conflicting upgrade file $name; preserve both histories.',
      );
    }
  }

  String _receiptName(String w, String kind) =>
      'upgrade-$sessionId-$w-$kind.json';
  Map<String, dynamic> _receipt(String w, String kind) => {
    'v': 1,
    'upgradeProtocol': 1,
    'session': sessionId,
    'sessionDigest': sessionDigest,
    'space': space,
    'coordinator': coordinator,
    'writer': w,
    'snapshot': plan.sourceDigest,
    'output': outputDigest,
    'manifest': _session['manifestDigest'],
    'phase': kind,
    'reader': unifiedProtocol,
  };
  Future<Set<String>> _receipts(String kind) async {
    final names = (await folder.list()).map((f) => f.name).toSet();
    final result = <String>{};
    for (final w in participants) {
      final n = _receiptName(w, kind);
      if (!names.contains(n)) continue;
      if (utf8.decode(await _read(folder, n, 16384)) !=
          canonicalDataJson(_receipt(w, kind))) {
        throw FormatFailure(
          'Participant acknowledgement belongs to another snapshot.',
        );
      }
      if (w == writer && !_ownReceiptBacked(kind)) continue;
      result.add(w);
    }
    return result;
  }

  bool _ownReceiptBacked(String kind) {
    final rows = profile.database.select(
      'SELECT plan,state FROM protected_app_migrations WHERE space=? AND epoch=?',
      [space, sessionId],
    );
    if (rows.length != 1) return false;
    final saved = jsonDecode(utf8.decode(rows.single['plan'] as List<int>));
    if (saved is! Map ||
        saved['consented'] != true ||
        saved['phase'] != rows.single['state'] ||
        saved['location'] != folder.location ||
        canonicalDataJson(saved['session']) != canonicalDataJson(_session)) {
      return false;
    }
    final phases = kind == 'input'
        ? {
            'input',
            'staging',
            'staged',
            'output',
            'activating',
            'ready',
            'complete',
          }
        : {'output', 'activating', 'ready', 'complete'};
    return phases.contains(rows.single['state']);
  }

  Future<UnifiedSnapshot> _preflight({required bool actualOutputs}) =>
      UnifiedHistory.preflight(
        _UpgradePreview(folder, conversion, actualOutputs),
        profile: profile,
        writer: writer,
        textEngine: textEngine,
      );

  Future<void> refresh() => _control(profile, _refresh);

  Future<void> _refresh() async {
    await _checkSession(allowInvalid: true);
    if ((await folder.list()).any((f) => f.name == _invalidName)) {
      _phase = 'invalidated';
      return;
    }
    try {
      await _checkSources();
    } on FormatFailure {
      if ((await folder.list()).any((f) => f.name == _invalidName)) {
        _phase = 'invalidated';
        return;
      }
      rethrow;
    }
    _inputs = await _receipts('input');
    _outputs = await _receipts('output');
    final actual = await _read(folder, 'tandemlog-space.json', 1024 * 1024);
    if (_equal(actual, utf8.encode(conversion.manifest.encode()))) {
      _phase = isParticipant && _state['phase'] != 'complete'
          ? 'ready'
          : 'complete';
    } else if (_equal(
      actual,
      utf8.encode(conversion.manifest.staged().encode()),
    )) {
      _phase = 'staged';
    } else if (_equal(actual, base64Decode(_state['manifest'] as String))) {
      _phase = 'input';
    } else if (isCoordinator &&
        {'staging', 'activating'}.contains(_state['phase'])) {
      _phase = _state['phase'] as String;
    } else {
      throw FormatFailure(
        'Activation manifest is incomplete or changed; '
        'resume on the initiating device.',
      );
    }
  }

  void _participant() {
    _identity(profile, writer);
    if (!isParticipant) {
      throw FormatFailure(
        'This device is not in the confirmed upgrade roster.',
      );
    }
    if (_state['phase'] == 'complete' || _state['phase'] == 'aborted') {
      throw FormatFailure('This installation already finished this upgrade.');
    }
  }

  Future<void> acknowledgeInput() => _control(profile, _acknowledgeInput);

  Future<void> _acknowledgeInput() async {
    _participant();
    await _refresh();
    if (!{'input', 'staged'}.contains(phase)) {
      throw FormatFailure(
        'The sealed input cannot be validated in this upgrade phase.',
      );
    }
    if (!hasLocalConsent) {
      throw FormatFailure(
        'Confirm joining this upgrade before pausing this device.',
      );
    }
    final snapshot = await _preflight(actualOutputs: false);
    if (snapshot.incomplete || snapshot.pendingEffects) {
      throw FormatFailure(
        'Resolve incomplete history and pending writes first.',
      );
    }
    await _save('input');
    await _checkSources();
    await _checkSession();
    await _createExact(
      _receiptName(writer, 'input'),
      utf8.encode(canonicalDataJson(_receipt(writer, 'input'))),
    );
    await _refresh();
  }

  Future<void> _outputsExact() async {
    final names = (await folder.list()).map((f) => f.name).toSet();
    if (names.any(
      (n) => n.contains('.applog') && !conversion.files.containsKey(n),
    )) {
      throw FormatFailure('Uncoordinated app history appeared during upgrade.');
    }
    for (final e in conversion.files.entries) {
      if (!names.contains(e.key) ||
          !_equal(
            await _read(folder, e.key, maximumUnifiedFileBytes),
            e.value,
          )) {
        throw FormatFailure(
          'Converted output is missing or differs from sealed bytes.',
        );
      }
    }
  }

  Future<void> _replaceManifest(List<int> expected, List<int> desired) async {
    if (folder is! CheckedReplaceLogFolder) {
      throw FormatFailure('Folder cannot replace the manifest.');
    }
    final actual = await _read(folder, 'tandemlog-space.json', 1024 * 1024);
    if (_equal(actual, desired)) return;
    final intent = _state['replacement'];
    final authorized =
        intent is Map &&
        intent['expected'] == base64Encode(expected) &&
        intent['desired'] == base64Encode(desired);
    final partial =
        authorized &&
        actual.length < desired.length &&
        _equal(actual, desired.take(actual.length).toList());
    if (!_equal(actual, expected) && !partial) {
      throw FormatFailure('Manifest changed outside this journaled upgrade.');
    }
    _state['replacement'] = {
      'expected': base64Encode(expected),
      'desired': base64Encode(desired),
    };
    await _save(_state['phase'] as String);
    if (authorized && folder is RecoverableReplaceLogFolder) {
      await (folder as RecoverableReplaceLogFolder).recoverOwned(
        'tandemlog-space.json',
        Uint8List.fromList(actual),
        Uint8List.fromList(desired),
      );
    } else {
      await (folder as CheckedReplaceLogFolder).replaceOwned(
        'tandemlog-space.json',
        Uint8List.fromList(actual),
        Uint8List.fromList(desired),
      );
    }
    if (!_equal(
      await _read(folder, 'tandemlog-space.json', 1024 * 1024),
      desired,
    )) {
      throw FormatFailure('Manifest replacement was not confirmed.');
    }
  }

  Future<void> stage({Future<void> Function(String)? checkpoint}) =>
      _control(profile, () => _stage(checkpoint: checkpoint));

  Future<void> _stage({Future<void> Function(String)? checkpoint}) async {
    _participant();
    if (!isCoordinator) {
      throw FormatFailure('Only the initiating device stages upgrade.');
    }
    await _refresh();
    if (!{'input', 'staging', 'staged'}.contains(phase) ||
        !_inputs.containsAll(participants)) {
      throw FormatFailure(
        'Wait for every participating device to pause and validate input.',
      );
    }
    plan.convert(
      _inputs.map(
        (w) => CutoverAcknowledgement(
          w,
          plan.sourceDigest,
          quiesced: true,
          pendingResolved: true,
        ),
      ),
    );
    await _save('staging');
    await _createExact(
      _stagingName,
      utf8.encode(
        canonicalDataJson({
          'v': 1,
          'session': sessionId,
          'sessionDigest': sessionDigest,
        }),
      ),
    );
    await _checkSession();
    await checkpoint?.call('before-manifest');
    await _replaceManifest(
      base64Decode(_state['manifest'] as String),
      utf8.encode(conversion.manifest.staged().encode()),
    );
    await checkpoint?.call('after-manifest');
    for (final e in conversion.files.entries) {
      await _checkSession();
      await _checkSources();
      final names = (await folder.list()).map((f) => f.name).toSet();
      if (!names.contains(e.key)) {
        await folder.create(e.key, Uint8List.fromList(e.value));
      } else {
        final actual = await _read(folder, e.key, maximumUnifiedFileBytes);
        if (actual.length > e.value.length ||
            !_equal(actual, e.value.take(actual.length).toList())) {
          throw FormatFailure(
            'Staged app history differs; no bytes were replaced.',
          );
        }
        if (actual.length < e.value.length) {
          await folder.append(
            e.key,
            Uint8List.fromList(e.value.skip(actual.length).toList()),
          );
        }
      }
      await checkpoint?.call('after-output:${e.key}');
    }
    await _outputsExact();
    await _checkSources();
    await _save('staged');
    await _refresh();
  }

  Future<void> acknowledgeOutput() => _control(profile, _acknowledgeOutput);

  Future<void> _acknowledgeOutput() async {
    _participant();
    await _refresh();
    if (phase != 'staged' || !_inputs.contains(writer)) {
      throw FormatFailure(
        'Acknowledge the exact input before validating staged output.',
      );
    }
    await _outputsExact();
    final snapshot = await _preflight(actualOutputs: true);
    if (snapshot.incomplete || snapshot.pendingEffects) {
      throw FormatFailure('Converted history is not ready.');
    }
    await _save('output');
    await _checkSources();
    await _checkSession();
    await _createExact(
      _receiptName(writer, 'output'),
      utf8.encode(canonicalDataJson(_receipt(writer, 'output'))),
    );
    await _refresh();
  }

  Future<void> activate({Future<void> Function(String)? checkpoint}) =>
      _control(profile, () => _activate(checkpoint: checkpoint));

  Future<void> _activate({Future<void> Function(String)? checkpoint}) async {
    _participant();
    if (!isCoordinator) {
      throw FormatFailure('Only the initiating device activates upgrade.');
    }
    await _refresh();
    if (phase == 'ready') return; // Published activation is irreversible.
    if (!{'staged', 'activating'}.contains(phase) ||
        !_inputs.containsAll(participants) ||
        !_outputs.containsAll(participants)) {
      throw FormatFailure(
        'Every participating device must validate the exact staged output.',
      );
    }
    await _outputsExact();
    final snapshot = await _preflight(actualOutputs: true);
    if (snapshot.incomplete || snapshot.pendingEffects) {
      throw FormatFailure('Converted history is not ready.');
    }
    await _save('activating');
    await checkpoint?.call('before-activation');
    await _checkSession();
    await _checkSources();
    await _outputsExact();
    await _replaceManifest(
      utf8.encode(conversion.manifest.staged().encode()),
      utf8.encode(conversion.manifest.encode()),
    );
    await checkpoint?.call('after-activation');
    await _refresh();
  }

  /// Ready publication allows peers to append. Preflight validates sealed
  /// migration prefixes AND valid descendants, rather than whole-file equality.
  Future<void> complete() => _control(profile, _complete);

  Future<void> _complete() async {
    if (_state['phase'] == 'complete') {
      await _refresh();
      if (phase != 'complete') {
        throw FormatFailure('Completed activation changed.');
      }
      return;
    }
    _participant();
    await _refresh();
    if (phase != 'ready' ||
        !_inputs.containsAll(participants) ||
        !_outputs.containsAll(participants)) {
      throw FormatFailure('The coordinated upgrade has not activated.');
    }
    final snapshot = await _preflight(actualOutputs: true);
    if (snapshot.incomplete || snapshot.pendingEffects) {
      throw FormatFailure('Activated history is not ready.');
    }
    await _checkSession();
    await _checkSources();
    await _save('complete');
    _phase = 'complete';
  }

  /// Before staging begins, cancel without editing canonical data. Peers release
  /// their own durable freeze only after independently validating this marker.
  Future<void> abort() => _control(profile, _abort);

  Future<void> _abort() async {
    _participant();
    if (!isCoordinator) {
      throw FormatFailure('Only the initiating device cancels upgrade.');
    }
    final names = (await folder.list()).map((f) => f.name).toSet();
    if (names.contains(_stagingName) ||
        names.any((n) => n.contains('.applog')) ||
        !_equal(
          await _read(folder, 'tandemlog-space.json', 1024 * 1024),
          base64Decode(_state['manifest'] as String),
        )) {
      throw FormatFailure(
        'Staging has begun. Resume this upgrade instead of cancelling.',
      );
    }
    // Source changes invalidate acknowledgements but do not prevent safe abort.
    final actual = await _read(
      folder,
      workspaceUpgradeSessionName,
      1024 * 1024,
    );
    if (!_equal(actual, utf8.encode(canonicalDataJson(_session)))) {
      throw FormatFailure('Another upgrade owns this folder.');
    }
    await _createExact(
      _abortName,
      utf8.encode(
        canonicalDataJson({
          'v': 1,
          'session': sessionId,
          'sessionDigest': sessionDigest,
          'coordinator': coordinator,
        }),
      ),
    );
    await _validateAbort(folder, _session);
    await _save('aborted');
    _phase = 'aborted';
  }
}

class _UpgradePreview implements LogFolder, BoundedLogFolder {
  _UpgradePreview(this.inner, this.conversion, this.actualOutputs);
  final LogFolder inner;
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
    if (name == 'tandemlog-space.json' ||
        (!actualOutputs && conversion.files.containsKey(name))) {
      final bytes = await read(name);
      if (bytes.length > maximumBytes) {
        throw FormatFailure('Upgrade read budget exceeded.');
      }
      return bytes;
    }
    return WorkspaceUpgrade._read(inner, name, maximumBytes);
  }

  @override
  Future<void> append(String name, Uint8List bytes) =>
      throw UnsupportedError('Read-only upgrade validation');
  @override
  Future<void> create(String name, Uint8List bytes) =>
      throw UnsupportedError('Read-only upgrade validation');
}
