import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/application/checklist_completion_command.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

class _CompletionFixture {
  _CompletionFixture(
    this.root,
    this.folder,
    this.engine,
    this.a,
    this.b,
    this.parent,
    this.first,
    this.second,
  );
  final Directory root;
  final LocalLogFolder folder;
  final NativeTextEngine engine;
  final TaskStore a, b;
  final String parent, first, second;
  static Future<_CompletionFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'checklist-completion-command-',
    );
    final folder = LocalLogFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    final engine = NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    final a = await TaskStore.open(
      folder,
      '${root.path}/a',
      textEngine: engine,
    );
    final user = const Uuid().v4(), parent = const Uuid().v4();
    await a.command(user, 'user.created', {'name': 'Synthetic'});
    await a.command(parent, 'task.createdWithText', {
      'title': 'Parent',
      'description': '',
      'assignee': user,
      'text': {
        'codec': 'yrs-v1',
        'adapter': 1,
        'seeds': {
          'title': sha256.convert(engine.seedText('Parent').bytes).toString(),
          'description': sha256.convert(engine.seedText('').bytes).toString(),
        },
      },
    });
    final first = (await a.addChecklistItem(
      parent,
      'First',
      notes: 'First notes',
    )).entity;
    final second = (await a.addChecklistItem(
      parent,
      'Second',
      notes: 'Second notes',
    )).entity;
    final b = await TaskStore.open(
      folder,
      '${root.path}/b',
      textEngine: engine,
    );
    return _CompletionFixture(
      root,
      folder,
      engine,
      a,
      b,
      parent,
      first,
      second,
    );
  }

  Future<Map<String, String>> canonical() async => {
    for (final file in await folder.list())
      file.name: sha256
          .convert(await File('${folder.location}/${file.name}').readAsBytes())
          .toString(),
  };
  List<LogEvent> get completions => a.db
      .select('SELECT raw FROM events WHERE entity=?', [parent])
      .map((row) => LogEvent.decode(row['raw'] as String))
      .where((event) => isTaskCompletion(event.type))
      .toList();
  Future<LogEvent?> run(
    Future<bool> Function(List<Map<String, dynamic>>) confirm, {
    void Function(OperationReceipt)? prepared,
  }) => ChecklistCompletionCommand(a).complete(
    parent,
    completionInstant: DateTime.utc(2030, 5, 10, 12),
    localZoneId: 'UTC',
    confirmUnfinished: confirm,
    onPrepared: prepared,
  );
  Future<void> editText(
    TaskStore store,
    String id,
    String field,
    String value,
  ) async {
    final capture = await store.captureTaskText(id);
    final session = TaskTextSession(
      capture,
      registerDraftActor: (name, allocation, actor) =>
          store.registerTextDraftActor(capture, name, allocation, actor),
    );
    try {
      session.replace(field, value);
      final result = await TextSaveCommand(
        store,
        session,
      ).save(fields: {}, tags: [], observedTagRefs: {});
      expect(result.receipt, isNotNull);
      expect(result.undoError, isNull);
    } finally {
      session.cancel();
      store.releaseTextCapture(capture);
    }
  }

  Future<void> close() async {
    await a.close();
    await b.close();
    engine.dispose();
  }
}

/// Preserve the real native store while scheduling one peer append between the
/// coordinator's last observation and the store's own receipt-preparation gate.
class _BeforeCommitPeerStore implements TaskStore {
  _BeforeCommitPeerStore(this.actual, this.peer, this.parent);
  final TaskStore actual, peer;
  final String parent;
  int attempts = 0;
  @override
  Future<bool> refresh() => actual.refresh();
  @override
  get db => actual.db;
  @override
  get tables => actual.tables;
  @override
  List<Map<String, dynamic>> get rows => actual.rows;
  @override
  String get taskSnapshot => actual.taskSnapshot;
  @override
  List<String> activeCompletionIds(String entity) =>
      actual.activeCompletionIds(entity);
  @override
  Future<LogEvent> complete(
    String entity, {
    DateTime? completionDay,
    DateTime? completionInstant,
    String? localZoneId,
    String? expectedChecklistSnapshot,
    bool requireIncomplete = false,
    void Function(OperationReceipt)? onPrepared,
  }) async {
    attempts++;
    if (attempts == 1) {
      await peer.addChecklistItem(parent, 'Arrived at preparation boundary');
    }
    return actual.complete(
      entity,
      completionDay: completionDay,
      completionInstant: completionInstant,
      localZoneId: localZoneId,
      expectedChecklistSnapshot: expectedChecklistSnapshot,
      requireIncomplete: requireIncomplete,
      onPrepared: onPrepared,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected boundary proxy call: ${invocation.memberName}',
  );
}

void main() {
  late _CompletionFixture f;
  setUp(() async => f = await _CompletionFixture.create());
  tearDown(() async => f.close());

  test(
    'all checked items complete without warning and prepare exactly one receipt',
    () async {
      await f.a.setChecklistCompleted(f.first, true);
      await f.a.setChecklistCompleted(f.second, true);
      var warnings = 0, prepared = 0;
      final result = await f.run((_) async {
        warnings++;
        return false;
      }, prepared: (_) => prepared++);
      expect(result, isNotNull);
      expect(warnings, 0);
      expect(prepared, 1);
      expect(f.completions, hasLength(1));
    },
  );

  test(
    'cancel unfinished warning prepares nothing and preserves exact canonical bytes',
    () async {
      final before = await f.canonical();
      var warnings = 0, prepared = 0;
      final result = await f.run((items) async {
        warnings++;
        expect(items.map((item) => item['id']), [f.first, f.second]);
        return false;
      }, prepared: (_) => prepared++);
      expect(result, isNull);
      expect(warnings, 1);
      expect(prepared, 0);
      expect(await f.canonical(), before);
      expect(f.completions, isEmpty);
      expect(f.a.db.select('SELECT * FROM text_outbox'), isEmpty);
    },
  );

  test(
    'warning observes whole current checklist including checked items notes and order',
    () async {
      await f.a.setChecklistCompleted(f.first, true);
      await f.a.moveChecklistItem(f.second, f.first);
      final expected = jsonEncode(f.a.checklistItems(f.parent));
      var warnings = 0;
      final result = await f.run((items) async {
        warnings++;
        expect(jsonEncode(items), expected);
        expect(items.first['description'], 'Second notes');
        expect(items.last['completed'], true);
        return true;
      });
      expect(result, isNotNull);
      expect(warnings, 1);
      expect(f.completions, hasLength(1));
    },
  );

  for (final incoming in [
    'new unchecked item',
    'completion state',
    'title',
    'notes',
    'order',
  ]) {
    test(
      'incoming $incoming during warning requires fresh confirmation before receipt',
      () async {
        var warnings = 0, prepared = 0;
        String? newItem;
        final original = jsonEncode(f.a.checklistItems(f.parent));
        final result = await f.run((items) async {
          warnings++;
          expect(prepared, 0);
          if (warnings == 1) {
            expect(jsonEncode(items), original);
            switch (incoming) {
              case 'new unchecked item':
                newItem = (await f.b.addChecklistItem(
                  f.parent,
                  'Incoming unchecked',
                )).entity;
              case 'completion state':
                await f.b.setChecklistCompleted(f.first, true);
              case 'title':
                await f.editText(f.b, f.first, 'title', 'Incoming title');
              case 'notes':
                await f.editText(f.b, f.first, 'description', 'Incoming notes');
              case 'order':
                await f.b.moveChecklistItem(f.second, f.first);
            }
            return true;
          }
          expect(warnings, 2);
          switch (incoming) {
            case 'new unchecked item':
              expect(items.map((item) => item['id']), contains(newItem));
              expect(items.last['completed'], false);
            case 'completion state':
              expect(
                items.singleWhere((item) => item['id'] == f.first)['completed'],
                true,
              );
            case 'title':
              expect(
                items.singleWhere((item) => item['id'] == f.first)['title'],
                'Incoming title',
              );
            case 'notes':
              expect(
                items.singleWhere(
                  (item) => item['id'] == f.first,
                )['description'],
                'Incoming notes',
              );
            case 'order':
              expect(items.map((item) => item['id']), [f.second, f.first]);
          }
          return true;
        }, prepared: (_) => prepared++);
        expect(result, isNotNull);
        expect(warnings, 2);
        expect(prepared, 1);
        expect(f.completions, hasLength(1));
      },
    );
  }

  test(
    'cancel renewed warning keeps peer changes but writes no local completion',
    () async {
      var warnings = 0, prepared = 0;
      Map<String, String>? peerBytes;
      final result = await f.run((items) async {
        warnings++;
        if (warnings == 1) {
          await f.b.addChecklistItem(f.parent, 'Needs renewed consent');
          peerBytes = await f.canonical();
          return true;
        }
        expect(warnings, 2);
        expect(items, hasLength(3));
        return false;
      }, prepared: (_) => prepared++);
      expect(result, isNull);
      expect(warnings, 2);
      expect(prepared, 0);
      expect(await f.canonical(), peerBytes);
      expect(f.completions, isEmpty);
    },
  );

  test(
    'incoming checks clearing all unfinished work need no second warning',
    () async {
      var warnings = 0;
      final result = await f.run((_) async {
        warnings++;
        await f.b.setChecklistCompleted(f.first, true);
        await f.b.setChecklistCompleted(f.second, true);
        return true;
      });
      expect(result, isNotNull);
      expect(warnings, 1);
      expect(f.completions, hasLength(1));
      expect(
        f.a.checklistItems(f.parent).every((item) => item['completed'] == true),
        true,
      );
    },
  );

  for (final incoming in ['deleted', 'completed']) {
    test(
      'task $incoming while warning is open stops without preparing duplicate completion',
      () async {
        var warnings = 0, prepared = 0;
        Map<String, String>? peerBytes;
        final result = await f.run((_) async {
          warnings++;
          if (incoming == 'deleted') {
            await f.b.command(f.parent, 'task.deleted', {});
          } else {
            await f.b.complete(
              f.parent,
              completionInstant: DateTime.utc(2030, 5, 10, 12),
              localZoneId: 'UTC',
            );
          }
          peerBytes = await f.canonical();
          return true;
        }, prepared: (_) => prepared++);
        expect(result, isNull);
        expect(warnings, 1);
        expect(prepared, 0);
        expect(await f.canonical(), peerBytes);
        expect(f.completions, hasLength(incoming == 'completed' ? 1 : 0));
      },
    );
  }

  test(
    'already completed task returns null without warning or duplicate receipt',
    () async {
      await f.b.complete(
        f.parent,
        completionInstant: DateTime.utc(2030, 5, 10, 12),
        localZoneId: 'UTC',
      );
      final before = await f.canonical();
      var warnings = 0, prepared = 0;
      final result = await f.run((_) async {
        warnings++;
        return true;
      }, prepared: (_) => prepared++);
      expect(result, isNull);
      expect(warnings, 0);
      expect(prepared, 0);
      expect(await f.canonical(), before);
      expect(f.completions, hasLength(1));
    },
  );

  test(
    'native incoming notes renew warning while another private item draft stays unpublished',
    () async {
      final capture = await f.a.captureTaskText(f.first);
      final private = TaskTextSession(
        capture,
        registerDraftActor: (name, allocation, actor) =>
            f.a.registerTextDraftActor(capture, name, allocation, actor),
      );
      try {
        private.replace('title', 'Private unsaved title');
        var warnings = 0;
        final result = await f.run((items) async {
          warnings++;
          expect(private.text('title'), 'Private unsaved title');
          expect(
            items.singleWhere((item) => item['id'] == f.first)['title'],
            'First',
          );
          if (warnings == 1) {
            await f.editText(f.b, f.first, 'description', 'Remote notes');
            return true;
          }
          expect(warnings, 2);
          expect(
            items.singleWhere((item) => item['id'] == f.first)['description'],
            'Remote notes',
          );
          return true;
        });
        expect(result, isNotNull);
        expect(warnings, 2);
        expect(private.text('title'), 'Private unsaved title');
        expect(
          f.a
              .checklistItems(f.parent)
              .singleWhere((item) => item['id'] == f.first)['title'],
          'First',
        );
        expect(f.completions, hasLength(1));
      } finally {
        private.cancel();
        f.a.releaseTextCapture(capture);
      }
    },
  );

  test(
    'incoming unchecked item at native preparation boundary retries confirmation before any receipt',
    () async {
      final proxy = _BeforeCommitPeerStore(f.a, f.b, f.parent);
      var warnings = 0, prepared = 0;
      final result = await ChecklistCompletionCommand(proxy).complete(
        f.parent,
        completionInstant: DateTime.utc(2030, 5, 10, 12),
        localZoneId: 'UTC',
        confirmUnfinished: (items) async {
          warnings++;
          expect(prepared, 0);
          expect(items, hasLength(warnings == 1 ? 2 : 3));
          if (warnings == 2) {
            expect(items.last['title'], 'Arrived at preparation boundary');
          }
          return true;
        },
        onPrepared: (_) => prepared++,
      );
      expect(result, isNotNull);
      expect(warnings, 2);
      expect(proxy.attempts, 2);
      expect(prepared, 1);
      expect(f.completions, hasLength(1));
    },
  );
}
