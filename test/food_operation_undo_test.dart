import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event_chain.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';

const owner = '00000000-0000-4000-8000-000000000010';
const peer = '00000000-0000-4000-8000-000000000020';
const a = '00000000-0000-4000-8000-000000000002';
const b = '00000000-0000-4000-8000-000000000003';

FoodOperation event(
  int seq,
  FoodAction action, {
  String writer = owner,
  int? clock,
  List<String> targets = const [a],
  FoodDetails? details,
  List<String>? fields,
  Contents? contents,
  List<String> deletes = const [],
  List<String> edits = const [],
}) => FoodOperation(
  id: '$writer:$seq',
  order: clock ?? seq,
  action: action,
  targets: targets,
  details: details,
  fields: fields,
  contents: contents,
  observedDeletes: deletes,
  observedEdits: edits,
  createdAt: action == FoodAction.add ? '2026-10-10T00:00:00Z' : null,
);

FoodOperation birth({List<String> targets = const [a]}) => event(
  1,
  FoodAction.add,
  targets: targets,
  details: const FoodDetails(name: 'Rice', estimated: null),
  contents: const Contents.fraction(1, 1),
);

FoodOperation undo(
  int seq,
  FoodOperation original, {
  List<String>? targets,
  String writer = owner,
  int? clock,
}) => FoodOperation.fromJson({
  'id': '$writer:$seq',
  'order': '${clock ?? seq}',
  'action': 'undo',
  'targets': targets ?? original.targets,
  'retracts': original.id,
});

List<Map<String, dynamic>> snapshot(Iterable<FoodOperation> events) =>
    projectFood(events).containers.map((c) => c.toJson()).toList();

String hashCanonical(Map<String, dynamic> body) {
  final payload = Map<String, dynamic>.from(body)..remove('hash');
  final domain = payload['v'] == 1
      ? foodRecordHashDomain
      : foodUndoRecordHashDomain;
  return canonicalDataJson({
    ...payload,
    'hash': sha256
        .convert(utf8.encode('$domain${canonicalDataJson(payload)}'))
        .toString(),
  });
}

void main() {
  test('Undo Add suppresses untouched IDs without making deletion tokens', () {
    final add = birth(targets: [a, b]);
    final state = projectFood([add, undo(2, add)]);
    expect(state.containers, isEmpty);
    expect(state.active, isEmpty);
    expect(state.deleted, isEmpty);
  });

  test('late independent edits preserve only their exact physical seed', () {
    final add = birth(targets: [a, b]);
    final inverse = undo(2, add);
    final remote = event(
      1,
      FoodAction.edit,
      writer: peer,
      clock: 3,
      details: const FoodDetails(name: 'Rice', brand: 'Peer brand'),
      fields: ['brand'],
    );
    expect(projectFood([add, inverse]).containers, isEmpty);
    final state = projectFood([inverse, remote, add]);
    expect(state.active.single.id, a);
    expect(state.active.single.details.brand, 'Peer brand');
    expect(state.active.single.details.estimated, isNull);
    expect(state.active.single.createdAt, add.createdAt);
    expect(state.active.single.deletions, isEmpty);
  });

  test('independent removal preserves seed in Deleted after Undo Add', () {
    final add = birth();
    final remove = event(1, FoodAction.remove, writer: peer, clock: 3);
    final state = projectFood([undo(2, add), remove, add]);
    expect(state.active, isEmpty);
    expect(state.deleted.single.id, a);
    expect(state.deleted.single.deletions, {remove.id});
  });

  test('Undo prior local edits then Add removes every unprotected ID', () {
    final add = birth();
    final edit = event(
      2,
      FoodAction.edit,
      details: const FoodDetails(name: 'Rice', expiry: '2026-10-15'),
      fields: ['expiry'],
    );
    final events = [add, edit, undo(3, edit), undo(4, add)];
    expect(projectFood(events).containers, isEmpty);
    expect(snapshot(events.reversed), snapshot(events));
  });

  test(
    'Undo details restores only original contributions; newer fields stay',
    () {
      final add = birth();
      final edit = event(
        2,
        FoodAction.edit,
        details: const FoodDetails(
          name: 'Changed',
          brand: 'Local',
          expiry: '2026-10-15',
          retention: 'Gift',
        ),
        fields: ['name', 'brand', 'expiry', 'retention'],
      );
      final remote = event(
        1,
        FoodAction.edit,
        writer: peer,
        clock: 3,
        details: const FoodDetails(name: 'Peer title', brand: 'Peer'),
        fields: ['name', 'brand'],
      );
      final state = projectFood([undo(4, edit), remote, edit, add]);
      final details = state.active.single.details;
      expect(details.name, 'Peer title');
      expect(details.brand, 'Peer');
      expect(details.expiry, isNull);
      expect(details.retention, '');
      expect(details.estimated, isNull);
      expect(state.view(FoodView.inbox).single.containers.single.id, a);
    },
  );

  test(
    'Undo contents resolution restores alternatives, later resolution stays',
    () {
      final add = birth();
      final first = event(
        2,
        FoodAction.edit,
        contents: const Contents.fraction(1, 2),
      );
      final second = event(
        1,
        FoodAction.edit,
        writer: peer,
        clock: 3,
        contents: const Contents.fraction(1, 3),
      );
      final resolution = event(
        3,
        FoodAction.edit,
        clock: 4,
        contents: const Contents.fraction(1, 4),
        edits: [first.id, second.id],
      );
      final inverse = undo(4, resolution, clock: 5);
      final restored = projectFood([add, first, second, resolution, inverse]);
      expect(restored.active.single.contentsEdits.keys.toSet(), {
        first.id,
        second.id,
      });
      expect(restored.active.single.contentsConflict, isTrue);
      expect(restored.active.single.contents.label, '⅓ remaining');
      final later = event(
        2,
        FoodAction.edit,
        writer: peer,
        clock: 6,
        contents: const Contents.fraction(3, 4),
        edits: [first.id, second.id, resolution.id],
      );
      final state = projectFood([
        later,
        inverse,
        resolution,
        second,
        first,
        add,
      ]);
      expect(state.active.single.contentsEdits.keys, [later.id]);
      expect(state.active.single.contents.label, '¾ remaining');
    },
  );

  test('Undo removal keeps an unseen concurrent removal', () {
    final local = event(2, FoodAction.remove);
    final remote = event(1, FoodAction.remove, writer: peer, clock: 3);
    final state = projectFood([
      birth(),
      local,
      undo(3, local, clock: 4),
      remote,
    ]);
    expect(state.deleted.single.deletions, {remote.id});
  });

  test(
    'Undo Restore withdraws only its token effect; another Restore survives',
    () {
      final remove = event(2, FoodAction.remove, targets: [a, b]);
      final restored = event(
        3,
        FoodAction.restore,
        targets: [a],
        deletes: [remove.id],
      );
      final independent = event(
        1,
        FoodAction.restore,
        writer: peer,
        clock: 4,
        targets: [a],
        deletes: [remove.id],
      );
      final events = [
        birth(targets: [a, b]),
        remove,
        restored,
        undo(4, restored, clock: 5),
      ];
      expect(projectFood(events).deleted.map((c) => c.id), [a, b]);
      final state = projectFood([...events, independent]);
      expect(state.active.single.id, a);
      expect(state.deleted.single.id, b);
      expect(state.deleted.single.deletions, {remove.id});
    },
  );

  test(
    'duplicate Undo and reordered delivery converge without changing IDs',
    () {
      final edit = event(
        2,
        FoodAction.edit,
        contents: const Contents.fraction(1, 2),
      );
      final inverse = undo(3, edit);
      final events = [birth(), edit, inverse, undo(4, edit)];
      final expected = snapshot(events);
      for (var shift = 0; shift < events.length; shift++) {
        expect(
          snapshot([
            ...events.skip(shift),
            ...events.take(shift),
            ...events.reversed,
          ]),
          expected,
        );
      }
    },
  );

  test('Undo cannot target another writer, a subset, or another Undo', () {
    final add = birth(targets: [a, b]);
    expect(
      () => projectFood([add, undo(2, add, writer: peer)]),
      throwsFormatException,
    );
    expect(
      () => projectFood([
        add,
        undo(2, add, targets: [a]),
      ]),
      throwsFormatException,
    );
    final inverse = undo(2, add);
    expect(
      () => projectFood([add, inverse, undo(3, inverse)]),
      throwsFormatException,
    );
    expect(() => undo(1, add), throwsFormatException);
  });

  test('Undo never hides malformed original history or invalid references', () {
    final invalid = event(
      2,
      FoodAction.edit,
      details: const FoodDetails(name: 'Bad basis'),
      fields: ['name'],
      clock: 0,
    );
    expect(
      () => projectFood([birth(), invalid, undo(3, invalid)]),
      throwsFormatException,
    );
    final crossTarget = event(2, FoodAction.remove, targets: [b]);
    final restore = event(3, FoodAction.restore, deletes: [crossTarget.id]);
    expect(
      () => projectFood([
        birth(targets: [a, b]),
        crossTarget,
        restore,
        undo(4, restore),
      ]),
      throwsFormatException,
    );
  });

  test(
    'independently hashed current Food Add and Undo preserve one reference chain',
    () {
      final lines = File(
        'test/fixtures/current-operation-v1/food.operations',
      ).readAsLinesSync();
      final add = FoodRecord.decode(lines.first),
          inverse = FoodRecord.decode(lines.last);
      expect(
        add.hash,
        '00249487efdb903e7757553f7d3c1f858700f48e6df904b9659fc2d09585c250',
      );
      expect(
        inverse.hash,
        'fe4b83c285343a4e7b99bd32151b33fb5446169730e4036797bdfa8ea6ff6f6d',
      );
      expect(add.encode(), lines.first);
      expect(inverse.encode(), lines.last);
      expect(inverse.previousHash, add.hash);
      expect(inverse.writer, add.writer);
      expect(inverse.operation.retracts, add.id);
      expect(
        projectFood([add.operation, inverse.operation]).containers,
        isEmpty,
      );
      // Frozen historical byte fixtures remain unchanged and execute externally.
      for (final raw in File(
        'test/fixtures/food-undo/mixed-v1-v2.foodlog',
      ).readAsLinesSync()) {
        expect(() => FoodRecord.decode(raw), throwsFormatException);
      }
    },
  );

  test(
    'pre-cutover Food envelope variants are refused without reinterpretation',
    () {
      final lines = File(
        'test/fixtures/food-undo/mixed-v1-v2.foodlog',
      ).readAsLinesSync();
      final original = jsonDecode(lines.last) as Map<String, dynamic>;
      for (final changed in [
        {...original, 'v': 1},
        {...original, 'v': 3},
        {
          ...original,
          'operation': {...original['operation'] as Map, 'details': null},
        },
        {...jsonDecode(lines.first) as Map, 'v': 2},
        {
          ...jsonDecode(lines.first) as Map,
          'operation': {
            ...jsonDecode(lines.first)['operation'] as Map,
            'retracts': '$owner:1',
          },
        },
        {
          ...original,
          'operation': {
            ...original['operation'] as Map,
            'retracts': '$owner:3',
          },
        },
      ]) {
        expect(
          () => FoodRecord.decode(
            hashCanonical(Map<String, dynamic>.from(changed)),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
