import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/text_actor.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/text/recurring_text.dart';
import 'package:tandemlog/text/shared_text_history.dart';

const _space = '00000000-0000-4000-8000-000000000001';
const _entity = '00000000-0000-4000-8000-000000000002';
const _writer = '00000000-0000-4000-8000-000000000003';
final _context = 'a' * 64;

class _Packets {
  _Packets(this.engine)
    : seed = engine.seedText('AB'),
      owner = engine.createDocument(
        actorClientId: 2,
        limits: const NativeTextLimits(visibleUtf16: 500),
        seed: engine.seedText('AB'),
      );
  final NativeTextEngine engine;
  final NativeTextUpdate seed;
  final NativeTextDocument owner;
  LogEvent? head;

  LineageTextOperation replace(String value) {
    final allocation = const Uuid().v4();
    final actor = deriveTextActor(_context, _writer, allocation);
    final draft = owner.captureDraft(actorClientId: actor)..replaceText(value);
    final save = draft.prepareSave();
    final sequence = (head?.sequence ?? 0) + 1;
    final event = LogEvent.decode(
      LogEvent(
        _space,
        _writer,
        sequence,
        EventClock(BigInt.from(sequence)),
        _entity,
        'task.textEdited',
        {
          'changes': {
            'title': {
              'context': _context,
              'allocation': allocation,
              'actor': actor,
              'update': save.update.encoded,
            },
          },
        },
      ).encode(previousHash: head?.hash ?? eventGenesisHash(_space, _writer)),
    );
    final packet = LineageTextOperation(
      event,
      'title',
      TextActorClaim(
        context: _context,
        writer: _writer,
        allocation: allocation,
        actor: actor,
      ),
      save.update,
    );
    save.commit(receiptUpdate: save.update);
    head = event;
    return packet;
  }
}

void main() {
  late NativeTextEngine engine;
  late _Packets packets;
  setUp(() {
    engine = NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    packets = _Packets(engine);
  });
  tearDown(() => engine.dispose());

  test(
    'one original operation is retained across immutable recurrence references',
    () {
      final graph = SharedTextHistoryGraph();
      final root = graph.root(_context, packets.seed);
      var current = root;
      for (var generation = 0; generation < 64; generation++) {
        final prior = current;
        current = graph.append(current, packets.replace('Task $generation'));
        expect(current.parents.single, same(prior));
        expect(graph.merge([current, current]), same(current));
      }
      expect(graph.packetCount, 64);
      expect(graph.nodeCount, 65);
      expect(graph.operations(root), isEmpty);
      expect(graph.operations(current), hasLength(64));
      expect(
        graph.operations(current).map((op) => op.event.id).toSet(),
        hasLength(64),
      );
    },
  );

  test(
    'union order and duplicate arrival retain one reference to each original',
    () {
      final graph = SharedTextHistoryGraph();
      final root = graph.root(_context, packets.seed);
      final first = packets.replace('AXB');
      final second = packets.replace('AXBY');
      final a = graph.append(root, first), b = graph.append(root, second);
      final union = graph.merge([a, b]);
      expect(graph.merge([b, a, b]), same(union));
      expect(graph.operations(union).map((op) => op.event.id).toSet(), {
        first.event.id,
        second.event.id,
      });
      expect(graph.append(a, first), same(a));
      expect(graph.packetCount, 2);
      expect(graph.operations(root), isEmpty);
    },
  );

  test(
    'equal seed text cannot authorize independent roots or forged packet claims',
    () {
      final graph = SharedTextHistoryGraph();
      final root = graph.root(_context, packets.seed);
      final independent = graph.root('b' * 64, packets.seed);
      expect(
        () => graph.merge([root, independent]),
        throwsA(isA<FormatFailure>()),
      );
      final original = packets.replace('AXB');
      final forged = LineageTextOperation(
        original.event,
        original.field,
        TextActorClaim(
          context: 'c' * 64,
          writer: _writer,
          allocation: original.claim.allocation,
          actor: original.claim.actor,
        ),
        original.update,
      );
      expect(() => graph.append(root, forged), throwsA(isA<FormatFailure>()));
      expect(graph.packetCount, 0);
      expect(graph.operations(root), isEmpty);
    },
  );

  test('canonical packet metadata is checked before retaining a reference', () {
    final graph = SharedTextHistoryGraph();
    final root = graph.root(_context, packets.seed);
    final original = packets.replace('AXB');
    final event = original.event;
    final forged = LogEvent(
      event.space,
      event.writer,
      event.sequence,
      event.clock,
      const Uuid().v4(),
      event.type,
      event.data,
      previousHash: event.previousHash,
      hash: event.hash,
      canonicalRaw: event.canonicalRaw,
    );
    expect(
      () => graph.append(
        root,
        LineageTextOperation(
          forged,
          original.field,
          original.claim,
          original.update,
        ),
      ),
      throwsA(isA<FormatFailure>()),
    );
    expect(graph.packetCount, 0);
  });

  test(
    'retained original packets are deeply immutable and privately owned',
    () {
      final graph = SharedTextHistoryGraph();
      final root = graph.root(_context, packets.seed);
      final original = packets.replace('AXB');
      final event = original.event;
      final caller = LogEvent(
        event.space,
        event.writer,
        event.sequence,
        event.clock,
        event.entity,
        event.type,
        (jsonDecode(event.canonicalRaw!) as Map)['data']
            as Map<String, dynamic>,
        previousHash: event.previousHash,
        hash: event.hash,
        canonicalRaw: event.canonicalRaw,
      );
      final reference = graph.append(
        root,
        LineageTextOperation(
          caller,
          original.field,
          original.claim,
          original.update,
        ),
      );
      final retained = graph.operations(reference).single;
      (caller.data['changes'] as Map)['title'] = {'context': 'forged'};
      expect(
        (retained.event.data['changes'] as Map)['title'],
        containsPair('context', _context),
      );
      expect(
        () => (retained.event.data['changes'] as Map)['title'] = {},
        throwsUnsupportedError,
      );
      expect(retained.event.canonicalRaw, original.event.canonicalRaw);
    },
  );

  test(
    'incremental native replay is linear and sparse checkpoints preserve historical state',
    () {
      final graph = SharedTextHistoryGraph();
      var current = graph.root(_context, packets.seed);
      final native = SharedTextMaterializer(
        engine,
        checkpointInterval: 8,
        checkpointByteLimit: 1024 * 1024,
      );
      final references = [current];
      final hashes = <String>[];
      try {
        for (var generation = 0; generation < 32; generation++) {
          current = graph.append(current, packets.replace('Task $generation'));
          references.add(current);
          final snapshot = native.snapshot(current);
          expect(snapshot.text, 'Task $generation');
          expect(snapshot.pending, isFalse);
          hashes.add(snapshot.stateHash);
        }
        expect(native.packetApplications, 32);
        expect(native.checkpointCount, lessThanOrEqualTo(4));
        expect(native.checkpointBytes, lessThanOrEqualTo(1024 * 1024));
        final last = native.state(current).encoded;
        expect(last, packets.owner.fullState.encoded);
        expect(native.snapshot(references[8]).stateHash, hashes[7]);
        final cold = SharedTextMaterializer(
          engine,
          checkpointInterval: 8,
          checkpointByteLimit: 1,
        );
        try {
          expect(cold.state(current).encoded, last);
          expect(cold.packetApplications, 32);
          expect(cold.checkpointCount, 0);
        } finally {
          cold.close();
        }
      } finally {
        native.close();
      }
    },
  );

  test(
    'reference summaries export full state only for sparse checkpoints or explicit proof',
    () {
      final graph = SharedTextHistoryGraph();
      var reference = graph.root(_context, packets.seed);
      final native = SharedTextMaterializer(engine, checkpointInterval: 8);
      try {
        for (var generation = 0; generation < 32; generation++) {
          reference = graph.append(
            reference,
            packets.replace('Task $generation'),
          );
          expect(native.snapshot(reference).text, 'Task $generation');
        }
        expect(native.stateExports, 4);
        expect(
          native.state(reference).encoded,
          packets.owner.fullState.encoded,
        );
        expect(native.stateExports, 5);
      } finally {
        native.close();
      }
    },
  );

  test(
    'evicting native roots and closing a materializer does not change references',
    () {
      final graph = SharedTextHistoryGraph();
      final root = graph.root(_context, packets.seed);
      final child = graph.append(root, packets.replace('AXB'));
      final native = SharedTextMaterializer(engine, maxActiveRoots: 1);
      final other = graph.root('b' * 64, engine.seedText('Other'));
      expect(native.snapshot(child).text, 'AXB');
      expect(native.snapshot(other).text, 'Other');
      expect(native.snapshot(child).text, 'AXB');
      native.close();
      expect(() => native.snapshot(child), throwsStateError);
      expect(graph.operations(child), hasLength(1));
    },
  );
}
