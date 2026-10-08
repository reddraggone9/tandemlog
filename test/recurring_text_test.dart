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
    bool referenceProof = false,
  }) {
    final fields = RecurringTextResolver(engine, observed).resolve(parent);
    final latest = <String, LogEvent>{};
    for (final e in observed) {
      if (e.sequence > (latest[e.writer]?.sequence ?? 0)) latest[e.writer] = e;
    }
    final proof = <String, dynamic>{
      'codec': 'yrs-v1',
      'adapter': referenceProof ? 2 : 1,
      'frontiers': {
        for (final e in latest.values)
          e.writer: {'seq': e.sequence, 'hash': e.hash},
      },
      'fields': {
        for (final entry in fields.entries)
          entry.key: <String, dynamic>{
            'parentContext': entry.value.context.hash,
            'seedHash': entry.value.context.seedHash,
            if (referenceProof)
              'historyHash': entry.value.historyReference!.hash
            else
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
        'new reference proofs preserve old exact-state proofs and reject substitution',
        () {
          final history = [h.create()];
          history.add(h.edit(history, _a, _parent, {'title': 'AXB'}));
          final completion = h.complete(
            history,
            _a,
            _parent,
            _child,
            referenceProof: true,
          );
          final shared = RecurringTextResolver(engine, [
            ...history,
            completion,
          ]).resolve(_child);
          final old = h.complete(history, _b, _parent, _child);
          final compatible = RecurringTextResolver(engine, [
            ...history,
            completion,
            old,
          ]).resolve(_child);
          expect(shared['title']!.text, 'AXB');
          expect(
            compatible['title']!.state.encoded,
            shared['title']!.state.encoded,
          );
          final corrupt = h.complete(
            history,
            _a,
            _parent,
            _child,
            referenceProof: true,
            corrupt: (proof) =>
                proof['fields']['title']['historyHash'] = 'f' * 64,
          );
          expect(
            () => RecurringTextResolver(engine, [
              ...history,
              corrupt,
            ]).resolve(_child),
            throwsA(isA<FormatFailure>()),
          );
        },
      );
      test(
        'resolver shares recurrence references and advances native history once',
        () {
          final memo = RecurringTextMemo();
          final history = [h.create()];
          var entity = _parent;
          var fields = RecurringTextResolver(
            engine,
            history,
            memo: memo,
          ).resolve(entity);
          final originalRoot = fields['title']!.historyReference!;
          for (var generation = 0; generation < 16; generation++) {
            history.add(
              h.edit(history, _a, entity, {'title': 'Task $generation'}),
            );
            fields = RecurringTextResolver(
              engine,
              history,
              memo: memo,
            ).resolve(entity);
            final reference = fields['title']!.historyReference!;
            expect(reference.rootContext, originalRoot.rootContext);
            final child = const Uuid().v5(entity, 'successor');
            history.add(h.complete(history, _a, entity, child));
            final successor = RecurringTextResolver(
              engine,
              history,
              memo: memo,
            ).resolve(child);
            expect(successor['title']!.historyReference, same(reference));
            expect(successor['title']!.text, 'Task $generation');
            expect(successor['title']!.stateHash, fields['title']!.stateHash);
            entity = child;
          }
          expect(memo.historyPacketApplications, 16);
          final cold = RecurringTextResolver(engine, history).resolve(entity);
          expect(cold['title']!.state.encoded, fields['title']!.state.encoded);
          memo.clear();
        },
      );
      test(
        'memo preserves union and rejects sparse closed prefixes after a hit',
        () {
          final created = h.create();
          final ax = h.edit([created], _a, _parent, {'title': 'AXB'});
          final head = h.append(_a, _user, 'user.created', {
            'name': 'Synthetic',
          });
          final ca = h.complete([created, ax, head], _a, _parent, _child);
          final memo = RecurringTextMemo();
          final complete = [created, ax, head, ca];
          final first = RecurringTextResolver(
            engine,
            complete,
            memo: memo,
          ).resolve(_child);
          final again = RecurringTextResolver(
            engine,
            complete,
            memo: memo,
          ).resolve(_child);
          expect(again['title']!.stateHash, first['title']!.stateHash);
          expect(memo.hits, greaterThan(0));
          expect(memo.recordDecodes, complete.length);
          expect(memo.recordHits, greaterThan(0));
          final corrupted = complete
              .map((event) => event.canonicalRaw!)
              .toList();
          corrupted[1] = corrupted[1].replaceFirst(
            '"type":"task.textEdited"',
            '"type":"task.deleted"',
          );
          expect(corrupted[1], isNot(complete[1].canonicalRaw));
          expect(
            () => RecurringTextResolver.fromCanonical(
              engine,
              corrupted,
              memo: memo,
            ).resolve(_child),
            throwsA(isA<FormatFailure>()),
          );
          // Same declared head, but one earlier immutable packet is missing.
          expect(
            () => RecurringTextResolver(engine, [
              created,
              head,
              ca,
            ], memo: memo).resolve(_child),
            throwsA(isA<FormatFailure>()),
          );
          final by = h.edit([created], _b, _parent, {'title': 'ABY'});
          final cb = h.complete([created, by], _b, _parent, _child);
          final joined = [...complete, by, cb];
          final merged = RecurringTextResolver(
            engine,
            joined,
            memo: memo,
          ).resolve(_child);
          final cold = RecurringTextResolver(engine, joined).resolve(_child);
          expect(merged['title']!.text, 'AXBY');
          expect(merged['title']!.stateHash, cold['title']!.stateHash);
          // A public resolved value cannot mutate retained memo packet metadata.
          expect(
            () =>
                again['title']!
                        .operations
                        .first
                        .event
                        .data['changes']['title']['actor'] =
                    17,
            throwsUnsupportedError,
          );
        },
      );
      test(
        'memo budgets evict without changing replay or requiring native checkpoints',
        () {
          final history = [h.create()];
          final memo = RecurringTextMemo(
            maxEntries: 2,
            maxPayloadBytes: 8192,
            maxRecords: 2,
            maxRecordPayloadBytes: 8192,
            maxActorDerivations: 2,
          );
          var parent = _parent;
          for (var i = 0; i < 6; i++) {
            final child = const Uuid().v5(parent, 'successor');
            history.add(h.complete(history, _a, parent, child));
            final value = RecurringTextResolver(
              engine,
              history,
              memo: memo,
            ).resolve(child);
            expect(value['title']!.text, 'AB');
            expect(memo.entryCount, lessThanOrEqualTo(2));
            expect(memo.retainedPayloadBytes, lessThanOrEqualTo(8192));
            expect(memo.recordCount, lessThanOrEqualTo(2));
            expect(memo.retainedRecordPayloadBytes, lessThanOrEqualTo(8192));
            parent = child;
          }
          final noRoom = RecurringTextMemo(maxPayloadBytes: 1);
          final uncached = RecurringTextResolver(
            engine,
            history,
            memo: noRoom,
          ).resolve(parent);
          expect(noRoom.entryCount, 0);
          expect(
            uncached['title']!.stateHash,
            RecurringTextResolver(
              engine,
              history,
              memo: memo,
            ).resolve(parent)['title']!.stateHash,
          );
          memo.clear();
          expect(memo.entryCount, 0);
          expect(memo.retainedPayloadBytes, 0);
          expect(memo.sharedPacketCount, 0);
          expect(memo.recordCount, 0);
          expect(memo.retainedRecordPayloadBytes, 0);
          for (var i = 0; i < 6; i++) {
            final context = '$i' * 64;
            final actor = memo.deriveActor(context, _a, _parent);
            expect(actor, deriveTextActor(context, _a, _parent));
            expect(memo.deriveActor(context, _a, _parent), actor);
            expect(memo.actorDerivationCount, lessThanOrEqualTo(2));
          }
          expect(
            () => memo.deriveActor('invalid', _a, _parent),
            throwsA(isA<FormatFailure>()),
          );
          memo.clear();
          expect(memo.actorDerivationCount, 0);
        },
      );
      test(
        'shared originals remain bounded without evicting the latest edited proof',
        () {
          final history = [h.create()];
          final memo = RecurringTextMemo(
            maxEntries: 3,
            maxPayloadBytes: 100000,
          );
          var parent = _parent;
          for (var i = 0; i < 18; i++) {
            history.add(h.edit(history, _a, parent, {'title': 'Plan $i'}));
            final child = const Uuid().v5(parent, 'successor');
            history.add(h.complete(history, _a, parent, child));
            final fields = RecurringTextResolver(
              engine,
              history,
              memo: memo,
            ).resolve(child);
            expect(fields['title']!.text, 'Plan $i');
            expect(memo.entryCount, lessThanOrEqualTo(3));
            expect(memo.retainedPayloadBytes, lessThanOrEqualTo(100000));
            expect(memo.sharedPacketCount, i + 1);
            final misses = memo.misses;
            RecurringTextResolver(engine, history, memo: memo).resolve(child);
            expect(memo.misses, misses);
            parent = child;
          }
          expect(
            RecurringTextResolver(
              engine,
              history,
              memo: memo,
            ).resolve(parent)['title']!.stateHash,
            RecurringTextResolver(
              engine,
              history,
            ).resolve(parent)['title']!.stateHash,
          );
          memo.clear();
          expect(memo.sharedPacketCount, 0);
          expect(memo.retainedPayloadBytes, 0);
        },
      );
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
