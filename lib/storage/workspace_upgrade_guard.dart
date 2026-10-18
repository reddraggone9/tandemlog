import 'dart:convert';

import '../domain/event.dart';
import 'local_profile_database.dart';
import 'log_folder.dart';
import 'unified_manifest.dart' show bytesDigest, LegacySeal;
import '../food/food_record.dart';

/// Command admission shared by both v3 adapters. Migration inspection and
/// recovery of previously reserved exact bytes remain separate operations.
class WorkspaceUpgradeGuard {
  static bool isUpgradeArtifact(String name) =>
      name.contains('.applog') ||
      (name.startsWith('upgrade-') && name.endsWith('.json'));

  static Map<String, dynamic> decodeSession(List<int> raw, {String? space}) {
    try {
      final value = jsonDecode(utf8.decode(raw));
      const keys = {
        'v',
        'session',
        'space',
        'coordinator',
        'participants',
        'owners',
        'sourceDigest',
        'outputDigest',
        'manifestDigest',
        'manifest',
        'sources',
      };
      if (value is! Map<String, dynamic> ||
          value.length != keys.length ||
          !value.keys.toSet().containsAll(keys) ||
          value['v'] != 1 ||
          !isCanonicalId(value['session']) ||
          !isCanonicalId(value['space']) ||
          (space != null && value['space'] != space) ||
          !isCanonicalId(value['coordinator']) ||
          !isEventHash(value['sourceDigest']) ||
          !isEventHash(value['outputDigest']) ||
          !isEventHash(value['manifestDigest']) ||
          value['manifest'] is! String ||
          value['sources'] is! List ||
          canonicalDataJson(value) != utf8.decode(raw)) {
        throw const FormatException('Invalid upgrade session');
      }
      for (final key in ['participants', 'owners']) {
        final ids = value[key];
        if (ids is! List ||
            ids.isEmpty ||
            ids.length > 256 ||
            ids.any((id) => !isCanonicalId(id)) ||
            ids.toSet().length != ids.length) {
          throw const FormatException('Invalid upgrade roster');
        }
      }
      if (!(value['participants'] as List).contains(value['coordinator'])) {
        throw const FormatException('Unregistered upgrade coordinator');
      }
      final manifest = base64Decode(value['manifest'] as String);
      final original = jsonDecode(utf8.decode(manifest));
      if (base64Encode(manifest) != value['manifest'] ||
          bytesDigest(manifest) != value['manifestDigest'] ||
          original is! Map ||
          original.length != 2 ||
          original['v'] != 3 ||
          original['id'] != value['space']) {
        throw const FormatException('Invalid original manifest');
      }
      final names = <String>{};
      for (final row in value['sources'] as List) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid source seal');
        }
        final seal = LegacySeal.fromJson(row);
        if (!(value['owners'] as List).contains(seal.owner) ||
            !names.add(seal.name) ||
            seal.length < 0 ||
            seal.count < 0 ||
            !isEventHash(seal.digest) ||
            !isEventHash(seal.head) ||
            !{'legacy.task', 'legacy.food'}.contains(seal.kind) ||
            seal.name !=
                (seal.kind == 'legacy.task'
                    ? '${seal.owner}.jsonl'
                    : foodLogName(foodWriter(seal.owner)))) {
          throw const FormatException('Invalid source seal');
        }
      }
      return value;
    } catch (_) {
      throw FormatFailure(
        'Invalid shared upgrade session. Preserve the folder before recovery.',
      );
    }
  }

  static bool isFrozen(LocalProfileDatabase profile, String space) {
    for (final row in profile.database.select(
      'SELECT space,epoch,plan,state FROM protected_app_migrations WHERE space=?',
      [space],
    )) {
      final Object? plan;
      try {
        plan = jsonDecode(utf8.decode(row['plan'] as List<int>));
      } catch (_) {
        throw FormatFailure(
          'Workspace upgrade journal is unreadable. Preserve the profile before recovery.',
        );
      }
      if (plan is! Map<String, dynamic>) {
        throw FormatFailure('Workspace upgrade journal is invalid.');
      }
      if (plan['kind'] != 'workspace-upgrade-v1') {
        // The released synthetic trial journal predates this app-owned protocol.
        if (plan['kind'] == null &&
            plan['v'] == 1 &&
            plan['participants'] is List &&
            plan['sources'] is Map &&
            plan['phase'] is String) {
          continue;
        }
        throw FormatFailure(
          'Unknown workspace upgrade journal. Update the app before writing.',
        );
      }
      final session = plan['session'];
      if (session is! Map<String, dynamic> ||
          plan['phase'] != row['state'] ||
          plan['location'] is! String ||
          (plan['location'] as String).isEmpty ||
          plan['sources'] is! Map ||
          plan['consented'] is! bool ||
          plan['manifest'] != session['manifest'] ||
          session['session'] != row['epoch'] ||
          session['space'] != space) {
        throw FormatFailure('Protected upgrade journal binding differs.');
      }
      decodeSession(utf8.encode(canonicalDataJson(session)), space: space);
      final sealedNames = (session['sources'] as List)
          .map((s) => (s as Map)['name'])
          .toSet();
      final backups = plan['sources'] as Map;
      if (backups.keys.toSet().length != sealedNames.length ||
          !backups.keys.toSet().containsAll(sealedNames) ||
          backups.values.any((b) => b is! String) ||
          !{
            'frozen',
            'input',
            'staging',
            'staged',
            'output',
            'activating',
            'ready',
            'complete',
            'aborted',
            'invalidated',
          }.contains(row['state'])) {
        throw FormatFailure('Protected upgrade snapshot is incomplete.');
      }
      if (!{'complete', 'aborted'}.contains(row['state'])) return true;
    }
    return false;
  }

  static void assertLocalWritable(LocalProfileDatabase? profile, String space) {
    if (profile != null && isFrozen(profile, space)) {
      throw FormatFailure(
        'Workspace upgrade is in progress. Finish or resume it before editing.',
      );
    }
  }

  static Future<void> assertWritable({
    required LogFolder folder,
    required String space,
    LocalProfileDatabase? profile,
  }) async {
    if (profile != null && isFrozen(profile, space)) {
      throw FormatFailure(
        'Workspace upgrade is in progress. Finish or resume it before editing.',
      );
    }
    final names = (await folder.list()).map((f) => f.name).toList();
    if (!names.contains('tandemlog-upgrade.json')) {
      if (names.any(isUpgradeArtifact)) {
        throw FormatFailure(
          'Waiting for the complete shared upgrade files before editing.',
        );
      }
      return;
    }
    if (names.toSet().length != names.length || folder is! BoundedLogFolder) {
      throw FormatFailure(
        'Workspace upgrade files are ambiguous or cannot be read safely.',
      );
    }
    final bounded = folder as BoundedLogFolder;
    try {
      final raw = await bounded.readBounded(
        'tandemlog-upgrade.json',
        1024 * 1024,
      );
      final session = decodeSession(raw, space: space);
      final id = session['session'] as String;
      final abortName = 'upgrade-$id-aborted.json';
      if (names.contains(abortName) &&
          !names.contains('upgrade-$id-staging.json') &&
          !names.any((n) => n.contains('.applog'))) {
        final abort = jsonDecode(
          utf8.decode(await bounded.readBounded(abortName, 4096)),
        );
        final manifest = await bounded.readBounded(
          'tandemlog-space.json',
          1024 * 1024,
        );
        final expected = base64Decode(session['manifest'] as String);
        if (abort is Map<String, dynamic> &&
            abort.length == 4 &&
            abort['v'] == 1 &&
            abort['session'] == id &&
            abort['sessionDigest'] == bytesDigest(raw) &&
            abort['coordinator'] == session['coordinator'] &&
            bytesDigest(manifest) == bytesDigest(expected)) {
          return;
        }
      }
    } on FormatFailure {
      rethrow;
    } catch (_) {
      throw FormatFailure(
        'Workspace upgrade needs recovery. Preserve the profile and folder.',
      );
    }
    throw FormatFailure(
      'A shared workspace upgrade is in progress. Open the upgrade screen before editing.',
    );
  }
}

bool workspaceUpgradeFrozen(LocalProfileDatabase profile, String space) =>
    WorkspaceUpgradeGuard.isFrozen(profile, space);
