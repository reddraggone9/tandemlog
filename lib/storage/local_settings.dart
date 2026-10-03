import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../domain/event.dart' show FormatFailure, isCanonicalId;
import 'local_durability.dart';

enum Appearance { system, light, dark }

/// Device preferences only. Canonical workspace records never live here.
class LocalSettings {
  LocalSettings(this.root, {LocalDurability? durability})
    : _durability = durability ?? LocalDurability.shared;
  final LocalDurability _durability;
  final String root;
  String? folder, user;
  Appearance appearance = Appearance.system;
  String? _writer;
  String get writer =>
      _writer ??
      (throw StateError('Load settings before opening a workspace.'));

  // Contains no UUID: a settings reset must create a new installation writer,
  // rather than resurrecting one of the retained legacy per-space identities.
  File get _migrationMarker => File('$root/writer-migration.json');

  /// Resolve only for explicit desktop Start without a saved folder selection.
  /// Retain an earlier default after a settings reset instead of hiding its data
  /// behind a newly created empty workspace. No files are created or moved here.
  Future<String> desktopDefaultFolder() async {
    final preferred = Directory('$root/shared-data');
    if (!await preferred.exists() || await preferred.list().isEmpty) {
      final legacy = Directory('$root/data');
      if (await legacy.exists() && !await legacy.list().isEmpty) {
        return legacy.path;
      }
    }
    return preferred.path;
  }

  Future<void> load() async {
    folder = user = _writer = null;
    appearance = Appearance.system;
    final file = File('$root/settings.json');
    if (await file.exists()) {
      final value =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // Existing installations stored only folder and user.
      folder = value['folder'] as String?;
      user = value['user'] as String?;
      final theme = value['appearance'] as String?;
      appearance = theme == null
          ? Appearance.system
          : Appearance.values.byName(theme);
      if (value.containsKey('writer')) {
        if (!isCanonicalId(value['writer'])) {
          throw FormatFailure(
            'Invalid installation writer identity in settings.',
          );
        }
        _writer = value['writer'] as String;
      }
    }
    await _ensureWriter();
    // Also complete a prior process's interrupted replacement of either local
    // authority file. This reads no canonical history.
    await _durability.syncParentAfterCreate(file);
  }

  Future<void> _ensureWriter() async {
    final migrated = await _migrationMarker.exists();
    if (migrated && await _migrationMarker.readAsString() != '{"v":1}') {
      throw FormatFailure('Invalid local writer migration marker.');
    }
    if (_writer == null) {
      _writer = migrated ? const Uuid().v4() : await _legacyWriter();
      _writer ??= const Uuid().v4();
      // Settings are the authority. Complete their atomic replacement first;
      // if interrupted before the marker, the saved UUID still wins on retry.
      try {
        await _writeSettings();
      } catch (_) {
        _writer = null;
        rethrow;
      }
    }
    if (!migrated) {
      await _durability.writeAtomicDurable(
        _migrationMarker,
        utf8.encode('{"v":1}'),
      );
    }
  }

  Future<String?> _legacyWriter() async {
    final spaces = Directory('$root/spaces');
    if (!await spaces.exists()) return null;
    final identities = <String, String>{};
    await for (final entry in spaces.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final identity = File('${entry.path}/writer-id');
      if (!await identity.exists()) continue;
      final value = (await identity.readAsString()).trim();
      if (!isCanonicalId(value)) {
        throw FormatFailure(
          'Invalid legacy writer identity at ${identity.path}.',
        );
      }
      // Match the cache key, not textual paths: Windows directory listings
      // use backslashes while callers can construct equivalent slash paths.
      final cacheKey = entry.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      );
      identities[cacheKey] = value;
    }
    if (identities.isEmpty) return null;
    if (folder != null) {
      final key = sha256.convert(utf8.encode(folder!)).toString();
      final selected = identities[key];
      if (selected != null) return selected;
    }
    // No selected identity: deterministic first cache directory, never mtime.
    final paths = identities.keys.toList()..sort();
    return identities[paths.first];
  }

  Future<void> save() async {
    await _durability.ensureDirectoryDurable(Directory(root));
    await _ensureWriter();
    await _writeSettings();
  }

  Future<void> _writeSettings() async {
    final file = File('$root/settings.json');
    await _durability.writeAtomicDurable(
      file,
      utf8.encode(
        jsonEncode({
          'folder': folder,
          'user': user,
          'appearance': appearance.name,
          'writer': writer,
        }),
      ),
    );
  }
}
