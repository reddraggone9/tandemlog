import 'dart:convert';
import 'dart:io';

enum Appearance { system, light, dark }

/// Device preferences only. Canonical workspace records never live here.
class LocalSettings {
  LocalSettings(this.root);
  final String root;
  String? folder, user;
  Appearance appearance = Appearance.system;

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
    final file = File('$root/settings.json');
    if (!await file.exists()) return;
    final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    // Existing installations stored only folder and user.
    folder = value['folder'] as String?;
    user = value['user'] as String?;
    final theme = value['appearance'] as String?;
    appearance = theme == null
        ? Appearance.system
        : Appearance.values.byName(theme);
  }

  Future<void> save() async {
    final file = File('$root/settings.json');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'folder': folder,
        'user': user,
        'appearance': appearance.name,
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
