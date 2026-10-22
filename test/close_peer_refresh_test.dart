import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/text/native_text_engine.dart';

class _PausedReadFolder extends LocalLogFolder {
  _PausedReadFolder(super.location);
  bool armed = false;
  final entered = Completer<void>(), released = Completer<void>();
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) async {
    if (armed && name.endsWith('.applog')) {
      armed = false;
      entered.complete();
      await released.future;
    }
    return super.readBounded(name, maximumBytes);
  }
}

Future<TaskTextCapture> _saveTitle(
  TaskStore store,
  String task,
  String title,
) async {
  final capture = await store.captureTaskText(task),
      field = capture.fields['title']!;
  final draft = field.document.captureDraft(actorClientId: field.actor)
    ..replaceText(title);
  final save = draft.prepareSave();
  OperationReceipt? receipt;
  await store.editNativeTask(task, {
    'title': {
      'context': field.context,
      'allocation': field.allocation,
      'actor': field.actor,
      'update': save.update.encoded,
    },
  }, onPrepared: (r) => receipt = r);
  save.commit(receiptUpdate: save.update);
  store.registerTextOperation(receipt!, capture);
  draft.cancel();
  return capture;
}

void main() {
  test(
    'close queues native owner disposal after an in-flight Food peer refresh',
    () async {
      final root = await Directory.systemTemp.createTemp('close-peer-refresh-');
      final folder = _PausedReadFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final profile = await LocalProfileDatabase.open('${root.path}/profile');
      TaskStore? tasks, peer;
      UnifiedHistory? history;
      FoodStore? food;
      Future<void>? closing, refreshing;
      try {
        await LocalSettings.initialize(profile);
        final writer =
            LocalSettings.protectedValues(profile)['writer'] as String;
        history = await UnifiedHistory.create(
          folder,
          profile: profile,
          writer: writer,
          textEngine: engine,
        );
        tasks = await TaskStore.openUnified(history);
        food = await FoodStore.openUnified(history);
        final user = const Uuid().v4(), task = const Uuid().v4();
        await tasks.command(user, 'user.created', {'name': 'Synthetic'});
        expect(
          (await tasks.createTasks({task: 'Initial task'}, user)).succeeded,
          isTrue,
        );
        final retained = await _saveTitle(tasks, task, 'Local saved title');
        final peerFolder = await Directory('${root.path}/peer-shared').create();
        for (final info in await folder.list()) {
          await File(
            '${folder.location}/${info.name}',
          ).copy('${peerFolder.path}/${info.name}');
        }
        peer = await TaskStore.open(
          LocalLogFolder(peerFolder.path),
          '${root.path}/peer-profile',
          textEngine: engine,
        );
        final peerCapture = await _saveTitle(peer, task, 'Incoming peer title');
        peer.releaseTextCapture(peerCapture);
        final peerName = '${peer.writer}.applog';
        await File(
          '${peerFolder.path}/$peerName',
        ).copy('${folder.location}/$peerName');
        await peer.close();
        peer = null;
        final canonicalBefore = {
          for (final info in await folder.list())
            info.name: base64Encode(await folder.read(info.name)),
        };
        folder.armed = true;
        refreshing = food.refresh();
        await folder.entered.future.timeout(const Duration(seconds: 3));
        closing = tasks.close();
        // Flush microtasks while the foreign refresh still owns the profile queue.
        await Future<void>.delayed(Duration.zero);
        expect(
          retained.fields['title']!.document.isClosed,
          isFalse,
          reason:
              'Native sessions remain alive until the queued detach can run.',
        );
        folder.released.complete();
        await refreshing;
        await closing;
        expect(retained.fields['title']!.document.isClosed, isTrue);
        expect(history.safetyFailure, isNull);
        final canonicalAfter = {
          for (final info in await folder.list())
            info.name: base64Encode(await folder.read(info.name)),
        };
        expect(
          canonicalAfter,
          canonicalBefore,
          reason: 'Refresh and close must append nothing.',
        );
        // The surviving module can continue refreshing after Task detachment.
        await food.refresh();
      } finally {
        if (!folder.released.isCompleted) folder.released.complete();
        await refreshing?.catchError((Object _) {});
        await closing?.catchError((Object _) {});
        await food?.close();
        await tasks?.close();
        await peer?.close();
        await history?.close();
        await profile.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
