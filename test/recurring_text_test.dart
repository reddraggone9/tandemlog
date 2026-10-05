import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/text_actor.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/text/recurring_text.dart';

const _space = '00000000-0000-4000-8000-000000000001';
const _parent = '00000000-0000-4000-8000-000000000002';
const _a = '00000000-0000-4000-8000-000000000003';
const _b = '00000000-0000-4000-8000-000000000004';
const _user = '00000000-0000-4000-8000-000000000005';
final _child = const Uuid().v5(_parent, 'successor');
final _library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];

class _History {
  final NativeTextEngine engine;
  _History(this.engine);
  final heads = <String, LogEvent>{};
  int clock = 0;
  LogEvent append(
    String writer,
    String entity,
    String type,
    Map<String, dynamic> data,
  ) {
    final prior = heads[writer];
    final event = LogEvent.decode(
      LogEvent(
        _space,
        writer,
        (prior?.sequence ?? 0) + 1,
        EventClock(BigInt.from(++clock)),
        entity,
        type,
        data,
      ).encode(previousHash: prior?.hash ?? eventGenesisHash(_space, writer)),
    );
    heads[writer] = event;
    return event;
  }

  LogEvent create() => append(_a, _parent, 'task.createdWithText', {
    'title': 'AB',
    'description': 'ab',
    'assignee': _user,
    'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
    'text': {
      'codec': 'yrs-v1',
      'adapter': 1,
      'seeds': {
        'title': sha256.convert(engine.seedText('AB').bytes).toString(),
        'description': sha256.convert(engine.seedText('ab').bytes).toString(),
      },
    },
  });
  LogEvent edit(
    List<LogEvent> observed,
    String writer,
    String entity,
    Map<String, String> replacements, {
    bool foreignActor = false,
  }) {
    final fields = RecurringTextResolver(engine, observed).resolve(entity);
    final changes = <String, dynamic>{};
    for (final entry in replacements.entries) {
      final field = fields[entry.key]!;
      final allocation = const Uuid().v4(),
          actor = deriveTextActor(field.context.hash, writer, allocation);
      final owner = engine.restoreDocument(
        actorClientId: 900 + clock,
        limits: const NativeTextLimits(visibleUtf16: 10000),
        checkpoint: NativeTextCheckpoint(field.state),
      );
      try {
        final draft = owner.captureDraft(
          actorClientId: foreignActor ? actor + 1 : actor,
        )..replaceText(entry.value);
        final prepared = draft.prepareSave();
        changes[entry.key] = {
          'context': field.context.hash,
          'allocation': allocation,
          'actor': actor,
          'update': prepared.update.encoded,
        };
        prepared.cancel();
      } finally {
        owner.dispose();
      }
    }
    return append(writer, entity, 'task.textEdited', {'changes': changes});
  }

  LogEvent complete(
    List<LogEvent> observed,
    String writer,
    String parent,
    String child, {
    void Function(Map<String, dynamic>)? corrupt,
  }) {
    final fields = RecurringTextResolver(engine, observed).resolve(parent);
    final latest = <String, LogEvent>{};
    for (final e in observed) {
      if (e.sequence > (latest[e.writer]?.sequence ?? 0)) latest[e.writer] = e;
    }
    final proof = <String, dynamic>{
      'codec': 'yrs-v1',
      'adapter': 1,
      'frontiers': {
        for (final e in latest.values)
          e.writer: {'seq': e.sequence, 'hash': e.hash},
      },
      'fields': {
        for (final entry in fields.entries)
          entry.key: <String, dynamic>{
            'parentContext': entry.value.context.hash,
            'seedHash': entry.value.context.seedHash,
            'stateHash': entry.value.stateHash,
          },
      },
    };
    corrupt?.call(proof);
    return append(writer, parent, 'task.completedWithText', {
      'completedAt': '2030-05-10',
      'successor': {
        'id': child,
        'title': fields['title']!.text,
        'description': fields['description']!.text,
        'assignee': _user,
        'tags': [],
        'schedule': {'dueDate': '2030-05-11', 'recurrence': 'every day'},
      },
      'inheritance': proof,
    });
  }
}

void main() {
  group(
    'actual native recurring inherited text',
    () {
      late NativeTextEngine engine;
      late _History h;
      setUp(() {
        engine = NativeTextEngine(libraryPath: _library);
        h = _History(engine);
      });
      tearDown(() => engine.dispose());
      test(
        'offline title and notes union preserves acknowledged child prefix and duplicates',
        () {
          final created = h.create();
          final ax = h.edit(
            [created],
            _a,
            _parent,
            {'title': 'AXB', 'description': 'axb'},
          );
          final by = h.edit(
            [created],
            _b,
            _parent,
            {'title': 'ABY', 'description': 'aby'},
          );
          final ca = h.complete([created, ax], _a, _parent, _child);
          final childEdit = h.edit(
            [created, ax, ca],
            _a,
            _child,
            {'title': 'Next: AXB', 'description': 'Next: axb'},
          );
          final cb = h.complete([created, by], _b, _parent, _child);
          final history = [created, ax, by, ca, childEdit, cb];
          final resolved = RecurringTextResolver(
            engine,
            history,
          ).resolve(_child);
          final parentFields = RecurringTextResolver(engine, [
            created,
          ]).resolve(_parent);
          expect(
            resolved['title']!.context.seedHash,
            parentFields['title']!.context.seedHash,
          );
          expect(
            resolved['description']!.context.seedHash,
            parentFields['description']!.context.seedHash,
          );
          expect(
            resolved['title']!.context.hash,
            isNot(parentFields['title']!.context.hash),
          );
          expect(resolved['title']!.text, 'Next: AXBY');
          expect(resolved['description']!.text, 'Next: axby');
          final reordered = RecurringTextResolver(engine, [
            cb,
            childEdit,
            ca,
            by,
            ax,
            created,
            cb,
            ax,
          ]).resolve(_child);
          expect(reordered['title']!.stateHash, resolved['title']!.stateHash);
          expect(
            reordered['description']!.stateHash,
            resolved['description']!.stateHash,
          );
        },
      );
      test(
        'later parent edits flow only through another completion and Undo retains contributions',
        () {
          final created = h.create(),
              ca = h.complete([h.heads[_a]!], _a, _parent, _child);
          final later = h.edit([created, ca], _b, _parent, {'title': 'ABY'});
          expect(
            RecurringTextResolver(engine, [
              created,
              ca,
              later,
            ]).resolve(_child)['title']!.text,
            'AB',
          );
          final cb = h.complete([created, ca, later], _b, _parent, _child);
          final undo = h.append(_b, _parent, 'task.recurringCompletionUndone', {
            'completion': cb.id,
          });
          expect(
            RecurringTextResolver(engine, [
              created,
              ca,
              later,
              cb,
              undo,
            ]).resolve(_child)['title']!.text,
            'ABY',
          );
        },
      );
      test(
        'missing proof is pending; known wrong context or state hash is invalid',
        () {
          final created = h.create(),
              edit = h.edit([h.heads[_a]!], _b, _parent, {'title': 'AXB'});
          final completion = h.complete([created, edit], _a, _parent, _child);
          expect(
            () => RecurringTextResolver(engine, [
              created,
              completion,
            ]).resolve(_child),
            throwsA(isA<TextInheritancePending>()),
          );
          for (final key in ['parentContext', 'seedHash', 'stateHash']) {
            final bad = h.complete(
              [created, edit],
              _b,
              _parent,
              _child,
              corrupt: (proof) => proof['fields']['title'][key] = 'd' * 64,
            );
            expect(
              () => RecurringTextResolver(engine, [
                created,
                edit,
                bad,
              ]).resolve(_child),
              throwsA(isA<FormatFailure>()),
            );
          }
        },
      );
      test('actual foreign struct author is rejected', () {
        final created = h.create(),
            forged = h.edit(
              [h.heads[_a]!],
              _b,
              _parent,
              {'title': 'AXB'},
              foreignActor: true,
            );
        expect(
          () =>
              RecurringTextResolver(engine, [created, forged]).resolve(_parent),
          throwsA(isA<FormatFailure>()),
        );
      });
      test('reusing another writer’s actor claim is rejected', () {
        final created = h.create();
        final legitimate = h.edit([created], _a, _parent, {'title': 'AXB'});
        final collision = h.append(_b, _parent, 'task.textEdited', {
          'changes': legitimate.data['changes'],
        });
        expect(
          () => RecurringTextResolver(engine, [
            created,
            legitimate,
            collision,
          ]).resolve(_parent),
          throwsA(isA<FormatFailure>()),
        );
      });
      test('grandchild prefix excludes a late ancestor completion', () {
        final created = h.create(),
            ax = h.edit([h.heads[_a]!], _a, _parent, {'title': 'AXB'});
        final ca = h.complete([created, ax], _a, _parent, _child);
        final grandchild = const Uuid().v5(_child, 'successor');
        final grand = h.complete([created, ax, ca], _a, _child, grandchild);
        final by = h.edit([created], _b, _parent, {'title': 'ABY'});
        final cb = h.complete([created, by], _b, _parent, _child);
        final fields = RecurringTextResolver(engine, [
          created,
          ax,
          ca,
          grand,
          by,
          cb,
        ]).resolve(grandchild);
        expect(fields['title']!.text, 'AXB');
      });
      test(
        'missing current grant waits but a closed incomplete proof rejects',
        () {
          final created = h.create();
          final ca = h.complete([created], _a, _parent, _child);
          final by = h.edit([created], _b, _parent, {'title': 'ABY'});
          final cb = h.complete([created, by], _b, _parent, _child);
          final childEdit = h.edit(
            [created, ca, by, cb],
            _a,
            _child,
            {'title': 'ABY!'},
          );
          expect(
            () => RecurringTextResolver(engine, [
              created,
              ca,
              childEdit,
            ]).resolve(_child),
            throwsA(isA<TextInheritancePending>()),
          );
          final invalid = h.complete(
            [created, ca, by, cb, childEdit],
            _a,
            _child,
            const Uuid().v5(_child, 'successor'),
            corrupt: (proof) => (proof['frontiers'] as Map).remove(_b),
          );
          expect(
            () => RecurringTextResolver(engine, [
              created,
              ca,
              by,
              cb,
              childEdit,
              invalid,
            ]).resolve(const Uuid().v5(_child, 'successor')),
            throwsA(
              isA<FormatFailure>().having(
                (e) => e.message,
                'reason',
                contains('Incomplete observed text proof'),
              ),
            ),
          );
        },
      );
      test(
        'union visible overflow rejects without modifying canonical inputs',
        () {
          final created = h.create();
          final ax = h.edit(
            [created],
            _a,
            _parent,
            {'title': 'A${'X' * 249}B'},
          );
          final by = h.edit(
            [created],
            _b,
            _parent,
            {'title': 'AB${'Y' * 250}'},
          );
          final ca = h.complete([created, ax], _a, _parent, _child),
              cb = h.complete([created, by], _b, _parent, _child);
          final history = [created, ax, by, ca, cb],
              bytes = history.map((e) => e.canonicalRaw).toList();
          expect(
            () => RecurringTextResolver(engine, history).resolve(_child),
            throwsA(anyOf(isA<FormatFailure>(), isA<NativeTextException>())),
          );
          expect(history.map((e) => e.canonicalRaw).toList(), bytes);
        },
      );
    },
    skip: _library == null
        ? 'Set TANDEMLOG_TEXT_LIBRARY to the unpatched native library.'
        : false,
  );
}
