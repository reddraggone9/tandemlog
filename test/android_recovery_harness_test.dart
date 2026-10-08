import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';
import '../tool/android_recovery/harness.dart';

void main() {
  final library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  test(
    'populated shared folder is rejected before native initialization',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'recovery-reject-test-',
      );
      try {
        final existing = File('${root.path}/existing.txt');
        await existing.writeAsString('retain this evidence');
        await expectLater(
          runRecoveryHarness(root, sharedFolder: LocalLogFolder(root.path)),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'SAF folder must be empty',
            ),
          ),
        );
        expect(await existing.readAsString(), 'retain this evidence');
        expect(await Directory(root.path).list().length, 1);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'bounded recovery harness passes all six synthetic cases',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'recovery-harness-test-',
      );
      try {
        final report = await runRecoveryHarness(root, libraryPath: library);
        expect(report['passed'], true, reason: '${report['cases']}');
        expect(report['cases'], hasLength(6));
        expect(await File('${root.path}/report.json').exists(), true);
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: library == null
        ? 'Set TANDEMLOG_TEXT_LIBRARY to the reviewed native engine'
        : false,
  );
}
