import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/text/recurring_text.dart';

const space = '00000000-0000-4000-8000-000000000001';
const parent = '00000000-0000-4000-8000-000000000002';
const a = '00000000-0000-4000-8000-000000000003';
const b = '00000000-0000-4000-8000-000000000004';
const c = '00000000-0000-4000-8000-000000000005';
const e = '00000000-0000-4000-8000-000000000006';
const f = '00000000-0000-4000-8000-000000000007';
const missingParent = '00000000-0000-4000-8000-000000000008';

class CollisionMemo extends RecurringTextMemo {
  @override
  int deriveActor(String context, String writer, String allocation) => 42;
}

class History {
  History(this.engine);
  final NativeTextEngine engine;
  final heads = <String, LogEvent>{};
  int clock = 0;
  LogEvent append(
    String writer,
    String entity,
    String type,
    Map<String, dynamic> data,
  ) {
    final old = heads[writer];
    final event = LogEvent.decode(
      LogEvent(
        space,
        writer,
        (old?.sequence ?? 0) + 1,
        EventClock(BigInt.from(++clock)),
        entity,
        type,
        data,
      ).encode(previousHash: old?.hash ?? eventGenesisHash(space, writer)),
    );
    heads[writer] = event;
    return event;
  }

  LogEvent create(String writer, String entity) =>
      append(writer, entity, 'task.createdWithText', {
        'title': 'AB',
        'description': '',
        'assignee': a,
        'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
        'text': {
          'codec': 'yrs-v1',
          'adapter': 1,
          'seeds': {
            'title': sha256.convert(engine.seedText('AB').bytes).toString(),
            'description': sha256.convert(engine.seedText('').bytes).toString(),
          },
        },
      });
  LogEvent edit(
    String writer,
    String entity,
    ResolvedTextField field,
    String next,
  ) {
    final owner = engine.restoreDocument(
      actorClientId: 2,
      checkpoint: NativeTextCheckpoint(field.state),
      limits: const NativeTextLimits(visibleUtf16: 500),
    );
    try {
      final draft = owner.captureDraft(actorClientId: 42)..replaceText(next),
          saved = draft.prepareSave();
      final event = append(writer, entity, 'task.textEdited', {
        'changes': {
          'title': {
            'context': field.context.hash,
            'allocation': const Uuid().v4(),
            'actor': 42,
            'update': saved.update.encoded,
          },
        },
      });
      saved.cancel();
      return event;
    } finally {
      owner.dispose();
    }
  }

  LogEvent complete(
    List<LogEvent> observed,
    String writer,
    String entity,
    RecurringTextMemo memo,
  ) {
    final fields = RecurringTextResolver(
      engine,
      observed,
      memo: memo,
    ).resolve(entity);
    final latest = <String, LogEvent>{};
    for (final event in observed) {
      if (event.sequence > (latest[event.writer]?.sequence ?? 0))
        latest[event.writer] = event;
    }
    return append(writer, entity, 'task.completedWithText', {
      'completedAt': '2030-05-10',
      'successor': {
        'id': const Uuid().v5(entity, 'successor'),
        'title': fields['title']!.text,
        'description': fields['description']!.text,
        'assignee': a,
        'tags': <String>[],
        'schedule': {'dueDate': '2030-05-11', 'recurrence': 'every day'},
      },
      'inheritance': {
        'codec': 'yrs-v1',
        'adapter': 2,
        'frontiers': {
          for (final event in latest.values)
            event.writer: {'seq': event.sequence, 'hash': event.hash},
        },
        'fields': {
          for (final entry in fields.entries)
            entry.key: {
              'parentContext': entry.value.context.hash,
              'seedHash': entry.value.context.seedHash,
              'historyHash': entry.value.historyReference!.hash,
            },
        },
      },
    });
  }
}

void main() {
  test(
    'pending then valid resolution cannot publish inherited actor proof into a different runtime',
    () {
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final builder = CollisionMemo(),
          warm = CollisionMemo(),
          cold = CollisionMemo();
      try {
        final h = History(engine),
            created = h.create(a, parent),
            child = const Uuid().v5(parent, 'successor');
        final root = RecurringTextResolver(engine, [
          created,
        ], memo: builder).resolve(parent);
        final parentEdit = h.edit(b, parent, root['title']!, 'AXB');
        final completion = h.complete(
          [created, parentEdit],
          a,
          parent,
          builder,
        );
        final inherited = RecurringTextResolver(engine, [
          created,
          parentEdit,
          completion,
        ], memo: builder).resolve(child);
        final childEdit = h.edit(c, child, inherited['title']!, 'AXBY');
        // actor42 already has X at clock0; this child packet contains only Y at clock1.
        // Thus native identity conflict checks cannot substitute for ownership checks.
        expect(
          engine.inspect(
            NativeTextUpdate.parse(
              childEdit.data['changes']['title']['update'],
            ),
          ),
          [42],
        );
        final missing = h.create(e, missingParent);
        final pending = h.complete([missing], f, missingParent, builder);
        final records = [created, parentEdit, completion, pending];
        expect(
          () => RecurringTextResolver(engine, [
            ...records,
            childEdit,
          ], memo: cold).resolve(child),
          throwsA(
            isA<FormatFailure>().having(
              (failure) => failure.message,
              'cold collision',
              contains('actor collision'),
            ),
          ),
        );
        final reused = RecurringTextResolver(engine, records, memo: warm);
        expect(
          () => reused.resolve(const Uuid().v5(missingParent, 'successor')),
          throwsA(isA<TextInheritancePending>()),
        );
        expect(reused.resolve(child)['title']!.text, 'AXB');
        final beforeHits = warm.hits;
        expect(
          () => RecurringTextResolver(engine, [
            ...records,
            childEdit,
          ], memo: warm).resolve(child),
          throwsA(
            isA<FormatFailure>().having(
              (failure) => failure.message,
              'warm collision',
              contains('actor collision'),
            ),
          ),
        );
        expect(warm.hits, greaterThan(beforeHits));
      } finally {
        builder.clear();
        warm.clear();
        cold.clear();
        engine.dispose();
      }
    },
  );
}
