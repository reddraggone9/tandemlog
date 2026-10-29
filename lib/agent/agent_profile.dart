import 'dart:convert';
import 'dart:io';

import '../storage/local_profile_database.dart';
import '../storage/profile_lock.dart';

/// Failure with a stable machine-readable kind (see design/agent-interface.md
/// section 7). Exit codes are part of the CLI contract.
class AgentFailure implements Exception {
  const AgentFailure(this.kind, this.message, {this.details});
  final String kind, message;
  final Object? details;

  int get exitCode => switch (kind) {
    'update_required' => 3,
    'profile_in_use' => 4,
    'history_damaged' => 5,
    'stale' || 'plan_changed' => 6,
    'write_pending' => 7,
    'not_found' || 'ambiguous_id' => 8,
    _ => 2,
  };

  Map<String, Object?> toJson() => {
    'kind': kind,
    'message': message,
    if (details != null) 'details': details,
  };

  @override
  String toString() => '$kind: $message';
}

/// One agent identity: a private profile directory, never a GUI profile.
/// The marker file distinguishes agent profiles; a directory without it is
/// refused so the CLI cannot borrow the app's installation identity.
class AgentProfile {
  AgentProfile(this.root);
  final String root;
  static const markerName = 'tandemlog-agent-profile.json';
  static const lockName = 'agent.lock';
  static const _marker = '{"role":"agent","v":1}';

  File get _markerFile => File('$root/$markerName');

  /// `TANDEMLOG_CLI_PROFILE` selects a profile by path or by name under the
  /// platform agent root. `TANDEMLOG_PROFILE` (the app's) is never consulted.
  static AgentProfile resolve({
    String? selection,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final chosen = selection ?? env['TANDEMLOG_CLI_PROFILE'] ?? 'default';
    if (chosen.isEmpty) {
      throw const AgentFailure('validation', 'Empty profile selection.');
    }
    if (chosen.contains('/') || chosen.contains(r'\')) {
      return AgentProfile(chosen);
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(chosen)) {
      throw AgentFailure('validation', 'Invalid profile name "$chosen".');
    }
    return AgentProfile('${agentRoot(env)}${Platform.pathSeparator}$chosen');
  }

  /// Linux (including Flatpak, whose XDG_DATA_HOME is per-app) uses the XDG
  /// data directory; Windows uses %APPDATA%. Sibling of, never inside, the
  /// app's own profile directory.
  static String agentRoot(Map<String, String> env) {
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw const AgentFailure('validation', 'APPDATA is not set.');
      }
      return '$appData\\com.reddraggone9\\tandemlog-agents';
    }
    final data = env['XDG_DATA_HOME'];
    final base = data != null && data.isNotEmpty
        ? data
        : '${env['HOME'] ?? (throw const AgentFailure('validation', 'HOME is not set.'))}/.local/share';
    return '$base/com.reddraggone9.tandemlog-agents';
  }

  Future<bool> get exists => _markerFile.exists();

  Future<void> requireAgentProfile() async {
    if (!await Directory(root).exists() || !await _markerFile.exists()) {
      throw AgentFailure(
        'validation',
        'No agent profile at $root. Run `tandemlog-cli init --workspace <folder> --name <name>`.',
      );
    }
    if ((await _markerFile.readAsString()).trim() != _marker) {
      throw AgentFailure(
        'update_required',
        'Unsupported agent profile marker at $root.',
      );
    }
  }

  /// A new profile directory must be absent or empty apart from its lock;
  /// init never adopts an existing (possibly GUI) profile. The caller holds
  /// [lock], so a concurrent init sees this marker and refuses.
  Future<void> createMarker() async {
    final dir = Directory(root);
    await dir.create(recursive: true);
    if ((await _entries()).isNotEmpty) {
      throw AgentFailure(
        'validation',
        'Profile directory $root is not empty; choose a new profile.',
      );
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['700', dir.path]);
    }
    await _markerFile.writeAsString(_marker, flush: true);
  }

  /// Everything in the profile directory except the identity lock.
  Future<List<FileSystemEntity>> _entries() => Directory(root)
      .list(followLinks: false)
      .where(
        (e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty) != lockName,
      )
      .toList();

  /// Undo a failed init under the held lock: remove what it created (the
  /// directory was empty apart from the lock), keeping the lock file.
  Future<void> removeCreated() async {
    for (final entry in await _entries()) {
      await entry.delete(recursive: true);
    }
  }

  /// Same-identity calls serialize on one OS lock; parallel agent calls wait
  /// up to [wait] and then fail with `profile_in_use`.
  Future<ProfileLock> lock(Duration wait) async {
    final deadline = DateTime.now().add(wait);
    while (true) {
      try {
        return await ProfileLock.acquire(
          root,
          fileName: lockName,
          message: 'Agent profile $root is in use.',
        );
      } on ProfileInUse catch (e) {
        if (DateTime.now().isAfter(deadline)) {
          throw AgentFailure('profile_in_use', e.message);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  /// Read commands work on a disposable copy so the durable profile stays
  /// byte-identical; the caller holds [lock] while copying.
  Future<Directory> readCopy() async {
    final copy = await Directory.systemTemp.createTemp('tandemlog-cli-read-');
    if (!Platform.isWindows) await Process.run('chmod', ['700', copy.path]);
    await for (final entry in Directory(root).list(followLinks: false)) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (name == lockName || entry is! File) continue;
      await entry.copy('${copy.path}${Platform.pathSeparator}$name');
    }
    return copy;
  }

  static Map<String, Object?> describe(LocalProfileDatabase profile) => {
    'root': profile.root,
    'schema': LocalProfileDatabase.schemaVersion,
  };

  static String encode(Object? value) => jsonEncode(value);
}
