import 'dart:io';

import '../application/workspace_session.dart';
import '../domain/event.dart' show FormatFailure;
import '../food/food_store.dart';
import '../storage/local_profile_database.dart';
import '../storage/local_settings.dart';
import '../storage/log_folder.dart';
import '../storage/profile_lock.dart';
import '../storage/task_store.dart' show StaleTaskSnapshot;
import '../text/native_text_engine.dart';
import 'agent_profile.dart';

/// Creates the native text engine; tests and alternate packagings may point
/// it at a specific library. The default resolves beside the executable.
NativeTextEngine Function() agentTextEngine = NativeTextEngine.new;

/// An open agent workspace for one command (or one MCP call). Reads run on a
/// disposable profile copy and a write-refusing folder; writes use the real
/// profile under the identity lock.
class AgentWorkspace {
  AgentWorkspace._(
    this.profile,
    this.settings,
    this.session,
    this._lock,
    this._engine,
    this._copy,
    this.readOnly,
  );
  final LocalProfileDatabase profile;
  final LocalSettings settings;
  final WorkspaceSession session;
  final ProfileLock? _lock;
  final NativeTextEngine _engine;
  final Directory? _copy;
  final bool readOnly;

  String get writer => settings.writer;
  NativeTextEngine get textEngine => _engine;

  static Future<AgentWorkspace> open(
    AgentProfile agent, {
    required bool readOnly,
    Duration wait = const Duration(seconds: 30),
    NativeTextEngine Function()? engineFactory,
    ProfileLock? held,
  }) async {
    await agent.requireAgentProfile();
    // A caller already holding the identity lock keeps ownership of it.
    ProfileLock? lock = held ?? await agent.lock(wait);
    final owned = held == null;
    Directory? copy;
    LocalProfileDatabase? profile;
    NativeTextEngine? engine;
    try {
      if (readOnly) {
        copy = await agent.readCopy();
        if (owned) await lock.close();
        lock = null;
      }
      profile = await LocalProfileDatabase.open(copy?.path ?? agent.root);
      final settings = LocalSettings(profile.root, profileDatabase: profile);
      await settings.load();
      final location = settings.folder;
      if (location == null) {
        throw const AgentFailure(
          'validation',
          'This agent profile has no workspace. Run init.',
        );
      }
      final LogFolder base = LocalLogFolder(location);
      engine = (engineFactory ?? agentTextEngine)();
      final session = await WorkspaceSession.open(
        readOnly ? ReadOnlyLogFolder(base) : base,
        profile: profile,
        writer: settings.writer,
        textEngine: engine,
        readOnly: readOnly,
      );
      return AgentWorkspace._(
        profile,
        settings,
        session!,
        owned ? lock : null,
        engine,
        copy,
        readOnly,
      );
    } catch (e) {
      await profile?.close();
      engine?.dispose();
      if (owned) await lock?.close();
      await copy?.delete(recursive: true);
      throw translate(e);
    }
  }

  Future<void> close() async {
    try {
      await session.close();
    } finally {
      try {
        await profile.close();
      } finally {
        _engine.dispose();
        await _lock?.close();
        await _copy?.delete(recursive: true);
      }
    }
  }

  /// Map storage failures to the stable error kinds.
  static Object translate(Object e) {
    if (e is AgentFailure) return e;
    if (e is ReadOnlyWorkspaceWrite) {
      return AgentFailure('write_pending', e.message);
    }
    if (e is ProfileInUse) return AgentFailure('profile_in_use', e.message);
    if (e is StaleTaskSnapshot || e is StaleFoodState) {
      return const AgentFailure(
        'stale',
        'The item changed before the write. Read it again.',
      );
    }
    if (e is LocalDatabaseFailure &&
        e.message.startsWith('Unsupported local database')) {
      return AgentFailure('update_required', e.message);
    }
    final message = e.toString();
    if (message.contains('Update the app') ||
        message.contains('Update TandemLog')) {
      return AgentFailure('update_required', message);
    }
    if (e is FormatFailure || e is FoodHistoryFailure) {
      return AgentFailure('history_damaged', message);
    }
    return e;
  }
}
