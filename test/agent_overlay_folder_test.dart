import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/agent/overlay_folder.dart';

void main() {
  test(
    'recovery archives only shadow temporary, never base evidence',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'agent-overlay-recovery-',
      );
      addTearDown(() => root.delete(recursive: true));
      final base = await Directory('${root.path}/base').create();
      final shadow = await Directory('${root.path}/shadow').create();
      final expected = Uint8List.fromList([1, 2]);
      final replacement = Uint8List.fromList([3, 4, 5]);
      await File('${base.path}/owner.applog').writeAsBytes(expected);
      await File('${base.path}/owner.applog.tmp').writeAsBytes([3]);
      final overlay = OverlayLogFolder(shadow.path, base.path);
      await overlay.recoverOwned('owner.applog', expected, replacement);
      expect(await File('${base.path}/owner.applog').readAsBytes(), expected);
      expect(await File('${base.path}/owner.applog.tmp').readAsBytes(), [3]);
      expect(await overlay.read('owner.applog'), replacement);
      expect(await File('${shadow.path}/owner.applog.tmp').exists(), false);
      final archives = await shadow
          .list()
          .where((f) => f.path.contains('.recovery-'))
          .toList();
      expect(archives, hasLength(1));
      expect(await File(archives.single.path).readAsBytes(), [3]);
    },
  );
}
