import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/android_storage_fault/harness.dart';

void main() {
  test(
    'control rejects paths, unsupported cuts, modes and arbitrary roots',
    () {
      for (final bad in [
        {'case': '../live', 'mode': 'cut', 'cut': 'activation.committed'},
        {'case': 'safe', 'mode': 'cut', 'cut': 'typo'},
        {'case': 'safe', 'mode': 'delete'},
        {'case': 'safe', 'mode': 'resume', 'root': '/live'},
      ]) {
        expect(() => validateControl(bad), throwsArgumentError);
      }
    },
  );
  for (final mode in ['resume', 'sql-full']) {
    test(
      '$mode preserves pending and guarded legacy fixture with SQL evidence',
      () async {
        final documents = await Directory.systemTemp.createTemp(
          'android-storage-fault-host-',
        );
        final root = Directory('${documents.path}/storage-fault-cases/safe');
        await seedFixture(root);
        await durableJson(File('${root.path}/ready.json'), {
          'source': faultSource,
          'pid': -1,
          'boundary': 'activation.committed',
          'root': root.path,
        });
        final report = await runFaultCase(documents, {
          'case': 'safe',
          'mode': mode,
        });
        expect(report['passed'], true);
        expect(report['pendingExact'], true);
        expect(report['guardExact'], true);
        expect(report['injectedSqlResultCode'], mode == 'sql-full' ? 13 : null);
        expect(
          jsonDecode(
            await File('${root.path}/report.json').readAsString(),
          )['source'],
          faultSource,
        );
        // This synthetic host marker explicitly does not claim Android death.
        expect((report['cutMarker'] as Map)['pid'], -1);
        await documents.delete(recursive: true);
      },
    );
  }
  test(
    'resume refuses absent fixture and seed refuses retained fixture',
    () async {
      final documents = await Directory.systemTemp.createTemp(
        'android-storage-fault-host-',
      );
      await expectLater(
        runFaultCase(documents, {'case': 'missing', 'mode': 'resume'}),
        throwsStateError,
      );
      final root = Directory('${documents.path}/storage-fault-cases/retained');
      await seedFixture(root);
      await expectLater(seedFixture(root), throwsStateError);
      await documents.delete(recursive: true);
    },
  );
}
