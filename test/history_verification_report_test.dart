import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  test(
    'history audit reports only Task events admitted by that audit',
    () async {
      final root = await Directory.systemTemp.createTemp('audit-new-events-');
      final shared = await Directory('${root.path}/shared').create();
      final folder = LocalLogFolder(shared.path);
      final first = await TaskStore.open(folder, '${root.path}/first');
      TaskStore? peer;
      try {
        await first.command(const Uuid().v4(), 'user.created', {
          'name': 'Initial',
        });
        await first.verifyHistory();
        expect(first.lastHistoryVerification!.importedEventCount, 0);
        peer = await TaskStore.open(folder, '${root.path}/peer');
        await peer.command(const Uuid().v4(), 'user.created', {
          'name': 'Incoming',
        });
        await first.verifyHistory();
        expect(first.lastHistoryVerification!.importedEventCount, 1);
        await first.verifyHistory();
        expect(first.lastHistoryVerification!.importedEventCount, 0);
        expect(
          first.lastHistoryVerification!.checkedRecordCount,
          greaterThan(1),
        );
      } finally {
        await peer?.close();
        await first.close();
        await root.delete(recursive: true);
      }
    },
  );
}
