import 'dart:convert';
import 'dart:io';

enum Appearance { system, light, dark }

/// Device preferences only. Canonical workspace records never live here.
class LocalSettings {
  LocalSettings(this.root);
  final String root;
  String? folder, user;
  Appearance appearance = Appearance.system;

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
