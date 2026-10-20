import 'dart:convert';
import 'dart:typed_data';

import '../domain/event.dart';
import 'local_profile_database.dart';
import 'local_settings.dart';
import 'log_folder.dart';
import 'unified_manifest.dart';

const _manifestName = 'tandemlog-space.json';
const _manifestLimit = 1024 * 1024;
const _journalLimit = 8 * 1024 * 1024;

enum WorkspaceCapabilityRole { initiator, adopter }

enum WorkspaceCapabilityPhase { prepared, replacing, adopting, complete }

/// Validated local authority, not permission to admit shared history by itself.
class WorkspaceCapabilityTransition {
  WorkspaceCapabilityTransition._({
    required this.space,
    required this.epoch,
    required this.writer,
    required this.location,
    required this.baseRaw,
    required this.targetRaw,
    required this.role,
    required this.phase,
    List<int> interruptedPrefixLengths = const [],
  }) : interruptedPrefixLengths = List<int>.unmodifiable(
         interruptedPrefixLengths,
       );

  /// Each length plus the fixed targetRaw reconstructs exact observed bytes.
  /// Keep these even after successful admission; they are local recovery evidence.
  final List<int> interruptedPrefixLengths;
  final String space, epoch, writer, location, baseRaw, targetRaw;
  final WorkspaceCapabilityRole role;
  final WorkspaceCapabilityPhase phase;
  bool get isComplete => phase == WorkspaceCapabilityPhase.complete;
  bool get isInitiator => role == WorkspaceCapabilityRole.initiator;
  bool get consented => isInitiator;

  WorkspaceCapabilityTransition _withPhase(WorkspaceCapabilityPhase value) =>
      WorkspaceCapabilityTransition._(
        space: space,
        epoch: epoch,
        writer: writer,
        location: location,
        baseRaw: baseRaw,
        targetRaw: targetRaw,
        role: role,
        phase: value,
        interruptedPrefixLengths: interruptedPrefixLengths,
      );

  WorkspaceCapabilityTransition _withInterruptedPrefix(int length) =>
      WorkspaceCapabilityTransition._(
        space: space,
        epoch: epoch,
        writer: writer,
        location: location,
        baseRaw: baseRaw,
        targetRaw: targetRaw,
        role: role,
        phase: phase,
        interruptedPrefixLengths: [...interruptedPrefixLengths, length],
      );

  Map<String, dynamic> _json() => {
    'v': 1,
    'kind': 'timezone-reader-floor-v1',
    'space': space,
    'epoch': epoch,
    'feature': additionalTimeZonesCapability,
    'writer': writer,
    'location': location,
    'role': role.name,
    'phase': phase.name,
    'consented': consented,
    'baseRaw': baseRaw,
    'targetRaw': targetRaw,
    'baseDigest': bytesDigest(utf8.encode(baseRaw)),
    'targetDigest': bytesDigest(utf8.encode(targetRaw)),
    'interruptedPrefixLengths': interruptedPrefixLengths,
  };

  Uint8List get _encoded =>
      Uint8List.fromList(utf8.encode(canonicalDataJson(_json())));
}

Never _invalid(String reason) => throw FormatFailure(
  '$reason Preserve the profile and workspace before recovery.',
);

void _identity(LocalProfileDatabase profile, String writer) {
  if (!isCanonicalId(writer) ||
      LocalSettings.protectedValues(profile)['writer'] != writer) {
    _invalid('Workspace capability installation identity differs.');
  }
}

void _outsideTransaction(LocalProfileDatabase profile) {
  if (!profile.database.autocommit) {
    throw StateError(
      'Provider operations cannot run inside a SQL transaction.',
    );
  }
}

SupportedTimeZoneExtension _extension(String base, String target) {
  if (utf8.encode(base).length > _manifestLimit ||
      utf8.encode(target).length > _manifestLimit) {
    _invalid('Workspace capability manifest exceeds safe limits.');
  }
  final extension = validateTimeZoneExtension(base, target);
  if (extension == null) {
    _invalid('Workspace capability transition is not the supported extension.');
  }
  return extension;
}

WorkspaceCapabilityTransition _decode(Map<String, Object?> row) {
  try {
    final bytes = row['journal'];
    if (bytes is! List<int> || bytes.length > _journalLimit) {
      _invalid('Workspace capability journal is not bounded canonical bytes.');
    }
    final raw = utf8.decode(bytes);
    final j = jsonDecode(raw);
    const keys = {
      'v',
      'kind',
      'space',
      'epoch',
      'feature',
      'writer',
      'location',
      'role',
      'phase',
      'consented',
      'baseRaw',
      'targetRaw',
      'baseDigest',
      'targetDigest',
      'interruptedPrefixLengths',
    };
    if (j is! Map<String, dynamic> ||
        j.length != keys.length ||
        !j.keys.toSet().containsAll(keys) ||
        canonicalDataJson(j) != raw ||
        j['v'] != 1 ||
        j['kind'] != 'timezone-reader-floor-v1' ||
        j['feature'] != additionalTimeZonesCapability ||
        row['feature'] != j['feature'] ||
        row['space'] != j['space'] ||
        row['epoch'] != j['epoch'] ||
        row['state'] != j['phase'] ||
        !isCanonicalId(j['writer']) ||
        j['location'] is! String ||
        (j['location'] as String).isEmpty ||
        j['baseRaw'] is! String ||
        j['targetRaw'] is! String) {
      _invalid('Workspace capability journal binding is invalid.');
    }
    final role = WorkspaceCapabilityRole.values.byName(j['role'] as String);
    final phase = WorkspaceCapabilityPhase.values.byName(j['phase'] as String);
    if (j['consented'] != (role == WorkspaceCapabilityRole.initiator) ||
        (role == WorkspaceCapabilityRole.initiator &&
            phase == WorkspaceCapabilityPhase.adopting) ||
        (role == WorkspaceCapabilityRole.adopter &&
            phase != WorkspaceCapabilityPhase.adopting &&
            phase != WorkspaceCapabilityPhase.complete)) {
      _invalid('Workspace capability consent or phase is invalid.');
    }
    final base = j['baseRaw'] as String, target = j['targetRaw'] as String;
    final extension = _extension(base, target);
    final prefixes = j['interruptedPrefixLengths'];
    final targetLength = utf8.encode(target).length;
    if (prefixes is! List ||
        prefixes.length > 1024 ||
        prefixes.any((n) => n is! int || n < 0 || n >= targetLength) ||
        prefixes.toSet().length != prefixes.length ||
        (prefixes.isNotEmpty &&
            (role != WorkspaceCapabilityRole.initiator ||
                (phase != WorkspaceCapabilityPhase.replacing &&
                    phase != WorkspaceCapabilityPhase.complete)))) {
      _invalid('Workspace capability interrupted-byte evidence is invalid.');
    }
    if (extension.space != j['space'] ||
        extension.epoch != j['epoch'] ||
        j['baseDigest'] != bytesDigest(utf8.encode(base)) ||
        j['targetDigest'] != bytesDigest(utf8.encode(target))) {
      _invalid('Workspace capability byte proof differs.');
    }
    return WorkspaceCapabilityTransition._(
      space: extension.space,
      epoch: extension.epoch,
      writer: j['writer'] as String,
      location: j['location'] as String,
      baseRaw: base,
      targetRaw: target,
      role: role,
      phase: phase,
      interruptedPrefixLengths: prefixes.cast<int>(),
    );
  } on FormatFailure {
    rethrow;
  } catch (_) {
    _invalid('Workspace capability journal is unreadable.');
  }
}

List<WorkspaceCapabilityTransition> _load(
  LocalProfileDatabase profile, {
  String? space,
}) {
  final where = space == null ? '' : ' WHERE space=?';
  final parameters = space == null ? <Object?>[] : <Object?>[space];
  // Check the size before asking SQLite to materialize a journal blob.
  for (final row in profile.database.select(
    'SELECT length(journal) AS n FROM protected_workspace_capabilities$where',
    parameters,
  )) {
    if (row['n'] is! int || (row['n'] as int) > _journalLimit) {
      _invalid('Workspace capability journal exceeds safe limits.');
    }
  }
  return [
    for (final row in profile.database.select(
      'SELECT space,epoch,feature,state,journal FROM protected_workspace_capabilities$where',
      parameters,
    ))
      _decode(Map<String, Object?>.from(row)),
  ];
}

String _protectedRaw(LocalProfileDatabase profile, String space, String epoch) {
  final rows = profile.database.select(
    'SELECT epoch,manifest FROM protected_app_workspaces WHERE space=?',
    [space],
  );
  if (rows.length != 1 ||
      rows.single['epoch'] != epoch ||
      rows.single['manifest'] is! String) {
    _invalid('Protected workspace capability authority is missing or changed.');
  }
  return rows.single['manifest'] as String;
}

void _binding(
  LocalProfileDatabase profile,
  WorkspaceCapabilityTransition transition,
  String writer,
  String location,
) {
  if (transition.writer != writer || transition.location != location) {
    _invalid(
      'Workspace capability journal belongs to another installation or folder.',
    );
  }
  final protected = _protectedRaw(profile, transition.space, transition.epoch);
  if (protected !=
      (transition.isComplete ? transition.targetRaw : transition.baseRaw)) {
    _invalid('Protected workspace capability bytes differ from their journal.');
  }
}

WorkspaceCapabilityTransition? _matching(
  LocalProfileDatabase profile,
  SupportedTimeZoneExtension extension,
  String writer,
  String location,
) {
  final rows = _load(profile)
      .where((row) => row.space == extension.space || row.location == location)
      .toList();
  if (rows.isEmpty) return null;
  if (rows.length != 1) {
    _invalid('Conflicting workspace capability transitions remain.');
  }
  final result = rows.single;
  _binding(profile, result, writer, location);
  if (result.epoch != extension.epoch ||
      result.baseRaw != extension.baseRaw ||
      result.targetRaw != extension.targetRaw) {
    _invalid('Workspace capability transition differs from its saved intent.');
  }
  return result;
}

void _writeInTransaction(
  LocalProfileDatabase profile,
  WorkspaceCapabilityTransition next, {
  WorkspaceCapabilityTransition? previous,
}) {
  if (profile.database.autocommit) {
    throw StateError(
      'Capability journal writes require the caller SQL transaction.',
    );
  }
  if (previous == null) {
    profile.database.execute(
      'INSERT INTO protected_workspace_capabilities VALUES (?,?,?,?,?)',
      [
        next.space,
        next.epoch,
        additionalTimeZonesCapability,
        next.phase.name,
        next._encoded,
      ],
    );
  } else {
    profile.database.execute(
      'UPDATE protected_workspace_capabilities SET state=?,journal=? '
      'WHERE space=? AND epoch=? AND feature=? AND state=? AND journal=?',
      [
        next.phase.name,
        next._encoded,
        next.space,
        next.epoch,
        additionalTimeZonesCapability,
        previous.phase.name,
        previous._encoded,
      ],
    );
    if (profile.database.updatedRows != 1) {
      _invalid('Workspace capability journal changed before commit.');
    }
  }
}

void _save(
  LocalProfileDatabase profile,
  WorkspaceCapabilityTransition next, {
  WorkspaceCapabilityTransition? previous,
}) => profile.transaction(
  () => _writeInTransaction(profile, next, previous: previous),
);

bool _same(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

Future<Uint8List> _actual(LogFolder folder) async {
  if (folder is! BoundedLogFolder) {
    _invalid('Folder provider cannot bound the capability manifest read.');
  }
  final names = (await folder.list()).map((f) => f.name).toList();
  if (names.toSet().length != names.length ||
      names.where((n) => n == _manifestName).length != 1) {
    _invalid('Workspace capability manifest is missing or ambiguous.');
  }
  return (folder as BoundedLogFolder).readBounded(
    _manifestName,
    _manifestLimit,
  );
}

void _noOwnPending(
  LocalProfileDatabase profile,
  WorkspaceCapabilityTransition transition,
) {
  if (profile.database.select(
    'SELECT 1 FROM protected_app_outbox WHERE space=? AND epoch=? AND writer=? LIMIT 1',
    [transition.space, transition.epoch, transition.writer],
  ).isNotEmpty) {
    _invalid(
      'Finish the exact pending save before enabling additional time zones.',
    );
  }
}

Future<void> _replace(
  LocalProfileDatabase profile,
  LogFolder folder,
  WorkspaceCapabilityTransition transition,
) async {
  if (!transition.isInitiator ||
      !transition.consented ||
      transition.isComplete) {
    _invalid('Only a pending initiating installation may repair the manifest.');
  }
  _noOwnPending(profile, transition);
  final expected = Uint8List.fromList(utf8.encode(transition.baseRaw));
  final desired = Uint8List.fromList(utf8.encode(transition.targetRaw));
  final actual = await _actual(folder);
  if (_same(actual, desired)) return;
  final recovering = transition.phase == WorkspaceCapabilityPhase.replacing;
  final prefix =
      recovering &&
      actual.length < desired.length &&
      _same(actual, desired.sublist(0, actual.length));
  if (!_same(actual, expected) && !prefix) {
    _invalid('Manifest changed outside this exact capability intent.');
  }
  if (folder is! CheckedReplaceLogFolder) {
    _invalid('This provider cannot safely replace the capability manifest.');
  }
  final checked = folder as CheckedReplaceLogFolder;
  await checked.checkReplacementSupport(_manifestName, _manifestLimit);
  if (prefix && !transition.interruptedPrefixLengths.contains(actual.length)) {
    if (transition.interruptedPrefixLengths.length >= 1024) {
      _invalid(
        'Interrupted-byte evidence is full; preserve the workspace before recovery.',
      );
    }
    // A byte count is sufficient only after exact prefix comparison above.
    // Commit this evidence BEFORE any provider can overwrite the observed bytes.
    final witnessed = transition._withInterruptedPrefix(actual.length);
    _save(profile, witnessed, previous: transition);
    transition = witnessed;
  }
  if (!recovering) {
    final replacing = transition._withPhase(WorkspaceCapabilityPhase.replacing);
    _save(profile, replacing, previous: transition);
  }
  if (recovering && folder is RecoverableReplaceLogFolder) {
    await (folder as RecoverableReplaceLogFolder).recoverOwned(
      _manifestName,
      actual,
      desired,
    );
  } else {
    await checked.replaceOwned(_manifestName, actual, desired);
  }
  if (!_same(await _actual(folder), desired)) {
    _invalid('Capability manifest replacement was not confirmed.');
  }
}

/// Caller owns the actual profile queue. This never promotes protected raw.
Future<void> replaceOwnedTimeZoneCapabilityInProfileQueue({
  required LocalProfileDatabase profile,
  required LogFolder folder,
  required String writer,
  required String expectedRaw,
  required String targetRaw,
  required bool confirmed,
}) async {
  if (!confirmed) {
    throw ArgumentError('Explicit confirmation is required before activation.');
  }
  _outsideTransaction(profile);
  _identity(profile, writer);
  final extension = _extension(expectedRaw, targetRaw);
  var transition = _matching(profile, extension, writer, folder.location);
  if (transition != null) {
    if (transition.isComplete ||
        transition.role == WorkspaceCapabilityRole.adopter) {
      if (!_same(await _actual(folder), utf8.encode(targetRaw))) {
        _invalid(
          'Only the initiating installation can recover this transition.',
        );
      }
      return;
    }
  } else {
    if (_protectedRaw(profile, extension.space, extension.epoch) !=
        expectedRaw) {
      _invalid(
        'The protected base manifest differs from the activation request.',
      );
    }
    transition = WorkspaceCapabilityTransition._(
      space: extension.space,
      epoch: extension.epoch,
      writer: writer,
      location: folder.location,
      baseRaw: expectedRaw,
      targetRaw: targetRaw,
      role: WorkspaceCapabilityRole.initiator,
      phase: WorkspaceCapabilityPhase.prepared,
    );
    _noOwnPending(profile, transition);
    final actual = await _actual(folder);
    if (!_same(actual, utf8.encode(expectedRaw)) &&
        !_same(actual, utf8.encode(targetRaw))) {
      _invalid('The activation manifest changed before preparing the intent.');
    }
    if (!_same(actual, utf8.encode(targetRaw))) {
      if (folder is! CheckedReplaceLogFolder) {
        _invalid(
          'This provider cannot safely replace the capability manifest.',
        );
      }
      await (folder as CheckedReplaceLogFolder).checkReplacementSupport(
        _manifestName,
        _manifestLimit,
      );
    }
    _save(profile, transition);
  }
  await _replace(profile, folder, transition);
}

/// Core must first validate every pending receipt under the OLD permission.
/// Adopters save local evidence only, never physical replacement authority.
Future<void> prepareTimeZoneCapabilityAdoptionInProfileQueue({
  required LocalProfileDatabase profile,
  required LogFolder folder,
  required String writer,
  required String expectedRaw,
  required String targetRaw,
}) async {
  _outsideTransaction(profile);
  _identity(profile, writer);
  final extension = _extension(expectedRaw, targetRaw);
  if (_matching(profile, extension, writer, folder.location) != null) return;
  if (_protectedRaw(profile, extension.space, extension.epoch) != expectedRaw) {
    _invalid('The protected base manifest differs from the adoption request.');
  }
  _save(
    profile,
    WorkspaceCapabilityTransition._(
      space: extension.space,
      epoch: extension.epoch,
      writer: writer,
      location: folder.location,
      baseRaw: expectedRaw,
      targetRaw: targetRaw,
      role: WorkspaceCapabilityRole.adopter,
      phase: WorkspaceCapabilityPhase.adopting,
    ),
  );
}

/// Validate even terminal journals. No file I/O, adoption or repair occurs here.
WorkspaceCapabilityTransition?
validateCurrentWorkspaceCapabilitiesInProfileQueue({
  required LocalProfileDatabase profile,
  required String writer,
  required String location,
  required String actualRaw,
}) {
  _identity(profile, writer);
  final current = UnifiedManifest.decode(actualRaw);
  final rows = _load(profile)
      .where((row) => row.space == current.space || row.location == location)
      .toList();
  if (rows.isEmpty) return null;
  if (rows.length != 1) _invalid('Conflicting workspace capability journals.');
  final transition = rows.single;
  _binding(profile, transition, writer, location);
  if (transition.epoch != current.epoch || actualRaw != transition.targetRaw) {
    _invalid(
      'Resume the exact capability transition before opening this workspace.',
    );
  }
  return transition;
}

/// Full admission must call this within its successful projection transaction.
void validateTimeZoneCapabilityTransitionInTransaction({
  required LocalProfileDatabase profile,
  required String space,
  required String epoch,
  required String writer,
  required String location,
  required String expectedRaw,
  required String targetRaw,
}) {
  if (profile.database.autocommit) {
    throw StateError(
      'Capability promotion requires the full admission transaction.',
    );
  }
  _identity(profile, writer);
  final extension = _extension(expectedRaw, targetRaw);
  if (extension.space != space || extension.epoch != epoch) {
    _invalid('Capability promotion identity differs.');
  }
  if (_matching(profile, extension, writer, location) == null) {
    _invalid('Capability promotion has no retained local transition intent.');
  }
}

/// No provider calls: protected raw and completion commit with full admission.
/// The caller must stage/validate every fallible projection in this transaction.
void completeTimeZoneCapabilityTransitionInTransaction({
  required LocalProfileDatabase profile,
  required String space,
  required String epoch,
  required String writer,
  required String location,
  required String expectedRaw,
  required String targetRaw,
}) {
  validateTimeZoneCapabilityTransitionInTransaction(
    profile: profile,
    space: space,
    epoch: epoch,
    writer: writer,
    location: location,
    expectedRaw: expectedRaw,
    targetRaw: targetRaw,
  );
  final extension = _extension(expectedRaw, targetRaw);
  final transition = _matching(profile, extension, writer, location)!;
  if (transition.isComplete) return;
  profile.database.execute(
    'UPDATE protected_app_workspaces SET manifest=? '
    'WHERE space=? AND epoch=? AND manifest=?',
    [targetRaw, space, epoch, expectedRaw],
  );
  if (profile.database.updatedRows != 1) {
    _invalid('Protected capability manifest changed before admission commit.');
  }
  _writeInTransaction(
    profile,
    transition._withPhase(WorkspaceCapabilityPhase.complete),
    previous: transition,
  );
}

/// Startup/explicit Resume owns one queue entry; ordinary Read Retry never calls
/// this. Physical repair cannot complete the SQL admission or a peer's intent.
Future<void> resumeOwnedWorkspaceCapabilitiesBeforeOpen({
  required LocalProfileDatabase profile,
  required LogFolder folder,
  required String writer,
}) => profile.serialize(() async {
  _identity(profile, writer);
  for (final transition in _load(profile)) {
    if (transition.location != folder.location) continue;
    _binding(profile, transition, writer, folder.location);
    if (!transition.isInitiator || transition.isComplete) continue;
    await _replace(profile, folder, transition);
  }
});

/// Settings awaits this outside widget build. It reads no provider files and
/// never hides malformed retained authority as a false "no recovery" result.
Future<bool> hasOwnedPendingWorkspaceCapabilities({
  required LocalProfileDatabase profile,
  required String writer,
  required String location,
}) => profile.serialize(() async {
  _identity(profile, writer);
  var pending = false;
  for (final transition in _load(profile)) {
    if (transition.location != location) continue;
    _binding(profile, transition, writer, location);
    pending |= transition.isInitiator && !transition.isComplete;
  }
  return pending;
});
