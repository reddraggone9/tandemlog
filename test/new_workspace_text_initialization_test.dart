import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

const _writer = '00000000-0000-4000-8000-000000000001';

class _FaultFolder
    implements LogFolder, BoundedLogFolder, TailTruncateLogFolder {
  _FaultFolder(this.inner);
  final LocalLogFolder inner;
  int? failAfterBytes;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      inner.readBounded(name, maximumBytes);
  @override
  Future<void> truncateOwnedTail(String name, Uint8List expected, int length) =>
      inner.truncateOwnedTail(name, expected, length);
  Future<void> _write(String name, Uint8List bytes, bool create) async {
    final cut = failAfterBytes;
    failAfterBytes = null;
    final actual = cut == null
        ? bytes
        : Uint8List.sublistView(bytes, 0, cut.clamp(0, bytes.length));
    if (create) {
      await inner.create(name, actual);
    } else {
      await inner.append(name, actual);
    }
    if (cut != null) throw StateError('Synthetic uncertain bootstrap append');
  }

  @override
  Future<void> create(String name, Uint8List bytes) =>
      _write(name, bytes, true);
  @override
  Future<void> append(String name, Uint8List bytes) =>
      _write(name, bytes, false);
}

void main() {
  late Directory root;
  late LocalProfileDatabase profile;
  late NativeTextEngine engine;
  late _FaultFolder folder;
  TaskStore? store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('new-workspace-text-');
    profile = await LocalProfileDatabase.open('${root.path}/profile');
    engine = NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    folder = _FaultFolder(
      LocalLogFolder((await Directory('${root.path}/shared').create()).path),
    );
  });
  tearDown(() async {
    await store?.close();
    store = null;
    await profile.close();
    engine.dispose();
    await root.delete(recursive: true);
  });
  Future<TaskStore> open({bool initialize = true, bool native = true}) =>
      TaskStore.open(
        folder,
        profile.root,
        profileDatabase: profile,
        writerIdentity: _writer,
        textEngine: native ? engine : null,
        initializeNewWorkspaceText: initialize,
      );

  test(
    'genuine new workspace initializes once and cold replay preserves bytes',
    () async {
      store = await open();
      expect(store!.sharedTextInitialized, isTrue);
      final bytes = await folder.read('$_writer.applog');
      final event = UnifiedRecord.decode(
        utf8.decode(bytes).trim(),
      ).effect.task!;
      expect(event.type, 'text.baselineInitialized');
      expect(event.entity, store!.space);
      expect(event.data['frontiers'], isEmpty);
      expect(store!.rows, isEmpty);
      await store!.close();
      store = null;
      await profile.close();
      profile = await LocalProfileDatabase.open('${root.path}/cold-profile');
      store = await open();
      expect(store!.sharedTextInitialized, isTrue);
      expect(await folder.read('$_writer.applog'), bytes);
      expect(store!.pendingTextOperations, isEmpty);
    },
  );

  test(
    'selecting an existing uninitialized workspace never activates it',
    () async {
      store = await open(initialize: false);
      await store!.command(
        '00000000-0000-4000-8000-000000000003',
        'user.created',
        {'name': 'Historical user'},
      );
      await store!
          .command('00000000-0000-4000-8000-000000000002', 'task.created', {
            'title': 'Historical scalar',
            'description': '',
            'assignee': '00000000-0000-4000-8000-000000000003',
          });
      final bytes = await folder.read('$_writer.applog');
      final manifest = await folder.read('tandemlog-space.json');
      await store!.close();
      store = null;
      await expectLater(
        open().then((value) => store = value),
        throwsA(isA<FormatFailure>()),
      );
      await store?.close();
      store = await open(initialize: false);
      expect(store!.sharedTextInitialized, isFalse);
      expect(
        store!.rows.singleWhere((row) => row['kind'] == 'task')['title'],
        'Historical scalar',
      );
      expect(await folder.read('$_writer.applog'), bytes);
      expect(await folder.read('tandemlog-space.json'), manifest);
    },
  );

  test(
    'an empty current workspace initializes without private bootstrap state',
    () async {
      store = await open(initialize: false);
      final manifest = await folder.read('tandemlog-space.json');
      await store!.close();
      store = null;
      store = await open();
      expect(store!.sharedTextInitialized, isTrue);
      expect(await folder.read('tandemlog-space.json'), manifest);
      expect(store!.unified!.physicalSequence, 1);
    },
  );

  test(
    'food history without its manifest cannot become a fresh workspace',
    () async {
      final name = 'food-$_writer.foodlog';
      final bytes = Uint8List.fromList(
        utf8.encode('retained synthetic food history\n'),
      );
      await folder.create(name, bytes);
      await expectLater(
        open().then((value) => store = value),
        throwsA(isA<FormatFailure>()),
      );
      expect(await folder.read(name), bytes);
      expect(await folder.list(), hasLength(1));
    },
  );

  test(
    'fresh initialized workspace preserves offline peer edits through cold replay',
    () async {
      store = await open();
      const user = '00000000-0000-4000-8000-000000000003';
      const task = '00000000-0000-4000-8000-000000000004';
      await store!.command(user, 'user.created', {'name': 'Synthetic'});
      await store!.command(task, 'task.createdWithText', {
        'title': 'Base',
        'description': '',
        'assignee': user,
        'text': {
          'codec': 'yrs-v1',
          'adapter': 1,
          'seeds': {
            'title': sha256.convert(engine.seedText('Base').bytes).toString(),
            'description': sha256.convert(engine.seedText('').bytes).toString(),
          },
        },
      });
      final peerProfile = await LocalProfileDatabase.open('${root.path}/peer');
      TaskStore? peer;
      try {
        peer = await TaskStore.open(
          folder,
          peerProfile.root,
          profileDatabase: peerProfile,
          writerIdentity: '00000000-0000-4000-8000-000000000002',
          textEngine: engine,
          initializeNewWorkspaceText: true,
        );
        final capturedA = await store!.captureTaskText(task);
        final capturedB = await peer.captureTaskText(task);
        Future<void> save(
          TaskStore owner,
          TaskTextCapture capture,
          String title,
        ) async {
          final field = capture.fields['title']!;
          final draft = field.document.captureDraft(actorClientId: field.actor)
            ..replaceText(title);
          final prepared = draft.prepareSave();
          try {
            await owner.editNativeTask(task, {
              'title': {
                'context': field.context,
                'allocation': field.allocation,
                'actor': field.actor,
                'update': prepared.update.encoded,
              },
            });
            prepared.commit(receiptUpdate: prepared.update);
          } finally {
            draft.cancel();
            owner.releaseTextCapture(capture);
          }
        }

        await save(store!, capturedA, 'Base A');
        await save(peer, capturedB, 'Base B');
        await store!.refresh();
        final merged =
            store!.rows.singleWhere((row) => row['id'] == task)['title']
                as String;
        expect(merged, contains('A'));
        expect(merged, contains('B'));
        expect(
          peer.rows.singleWhere((row) => row['id'] == task)['title'],
          merged,
        );
        final before = {
          for (final entry in await folder.list())
            entry.name: base64Encode(await folder.read(entry.name)),
        };
        await store!.close();
        store = null;
        await profile.close();
        profile = await LocalProfileDatabase.open('${root.path}/cold-merged');
        store = await open();
        expect(store!.sharedTextInitialized, isTrue);
        expect(
          store!.rows.singleWhere((row) => row['id'] == task)['title'],
          merged,
        );
        expect({
          for (final entry in await folder.list())
            entry.name: base64Encode(await folder.read(entry.name)),
        }, before);
      } finally {
        await peer?.close();
        await peerProfile.close();
      }
    },
  );

  test(
    'explicit fresh initialization requires native support before writing',
    () async {
      await expectLater(
        open(native: false).then((value) => store = value),
        throwsArgumentError,
      );
      expect(await folder.list(), isEmpty);
    },
  );

  for (final cut in [0, 71, 1000000]) {
    test(
      'uncertain bootstrap cut=$cut restarts from canonical bytes without saved intent',
      () async {
        final fault = _RecordFaultFolder(folder.inner, cut);
        await expectLater(
          TaskStore.open(
            fault,
            profile.root,
            profileDatabase: profile,
            writerIdentity: _writer,
            textEngine: engine,
            initializeNewWorkspaceText: true,
          ).then((value) => store = value),
          throwsStateError,
        );
        final partial = await folder.read('$_writer.applog');
        final complete = partial.isNotEmpty && partial.last == 10;
        expect(
          profile.database.select(
            "SELECT name FROM sqlite_schema WHERE name='protected_app_outbox'",
          ),
          isEmpty,
        );
        await profile.close();
        profile = await LocalProfileDatabase.open('${root.path}/profile');
        store = await open(initialize: false);
        expect(
          await folder.read('$_writer.applog'),
          partial,
          reason:
              'Read-only open cannot resume or clean an abandoned root write.',
        );
        expect(store!.sharedTextInitialized, complete);
        expect(store!.pendingTextOperations, isEmpty);
        await store!.close();
        store = null;
        store = await open();
        expect(store!.sharedTextInitialized, isTrue);
        final records = const LineSplitter().convert(
          utf8.decode(await folder.read('$_writer.applog')),
        );
        expect(records, hasLength(1));
        expect(
          UnifiedRecord.decode(records.single).effects.single.task!.type,
          'text.baselineInitialized',
        );
        if (complete) expect(await folder.read('$_writer.applog'), partial);
      },
    );
  }
}

class _RecordFaultFolder extends _FaultFolder {
  _RecordFaultFolder(super.inner, this.cut);
  final int cut;
  @override
  Future<void> create(String name, Uint8List bytes) {
    if (name.endsWith('.applog')) failAfterBytes = cut;
    return super.create(name, bytes);
  }

  @override
  Future<void> append(String name, Uint8List bytes) {
    if (name.endsWith('.applog')) failAfterBytes = cut;
    return super.append(name, bytes);
  }
}
