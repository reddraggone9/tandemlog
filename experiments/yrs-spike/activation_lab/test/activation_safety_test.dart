// Strengthens existing matrix expectations; frozen before these fixes.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../editor_lab/lib/native_bridge.dart';
import '../lib/activation.dart';
import 'activation_test.dart' as fixture;

void main() {
  setUp(() => NativeBridge().call('reset'));
  tearDown(() {
    for (final lab in fixture.labs) {
      lab.close();
    }
    fixture.labs.clear();
  });
  test('F01 baseline cannot omit a referenced historical Undo dependency', () {
    final c = fixture.Chain();
    final base = c.base();
    final peer = c.emit(fixture.b, fixture.task, 'task.edited', {
      'title': 'Peer',
    }, clock: 102);
    final undo = c.emit(fixture.a, fixture.task, 'task.operationUndone', {
      'operation': '${fixture.b}:1',
    }, clock: 103);
    final issuer = fixture.replica('missing-reference', fixture.a)
      ..ingestAll([...base, undo]);
    expect(
      () => issuer.prepareActivation(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message.toString(),
          'reason',
          contains('dependency'),
        ),
      ),
    );
    expect(issuer.isActive, isFalse);
    issuer.ingest(peer);
    issuer.activate();
    expect(issuer.text(fixture.task, 'title'), 'Buy oats');
  });
  test(
    'F02 pending checkpoint test really executes a native restore',
    () async {
      final p = fixture.pair();
      final parent = fixture.edit(p.x, 'cache-parent', 'Buy oats1');
      p.y.ingest(parent);
      final child = fixture.edit(p.y, 'cache-child', 'Buy oats12');
      final dir = await Directory.systemTemp.createTemp(
        'activation-restore-proof-',
      );
      try {
        final r = fixture.replica('cache-before', fixture.a, directory: dir)
          ..ingestAll([...p.base, p.activation, child]);
        expect(r.fieldPending(fixture.task, 'title'), isTrue);
        r.writeCache();
        r.close();
        final reopened = fixture.replica(
          'cache-after',
          fixture.a,
          directory: dir,
        );
        expect(reopened.cacheRestoreCount, greaterThanOrEqualTo(1));
        expect(reopened.fieldPending(fixture.task, 'title'), isTrue);
        reopened.ingest(parent);
        expect(reopened.text(fixture.task, 'title'), 'Buy oats12');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'F03 same-process unknown-receipt retry never appends the record twice',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'activation-same-process-',
      );
      try {
        final c = fixture.Chain();
        final r = fixture.replica('same-process', fixture.a, directory: dir)
          ..ingestAll(c.base());
        r.activate();
        final draft = r.begin(fixture.task, 'title', batch: 'same-process');
        draft.change(const DraftValue('Buy oats!'));
        final raw = r.prepareSave(draft);
        expect(() => r.save(draft, failAfterAppend: true), throwsStateError);
        final before = File('${dir.path}/records.jsonl').readAsBytesSync();
        expect(r.retryPrepared(raw), raw);
        expect(File('${dir.path}/records.jsonl').readAsBytesSync(), before);
        expect(r.text(fixture.task, 'title'), 'Buy oats!');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'F04 incomplete owned journal blocks writes and preserves pending bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp('activation-tail-');
      try {
        final c = fixture.Chain();
        final r = fixture.replica('tail-before', fixture.a, directory: dir)
          ..ingestAll(c.base());
        r.activate();
        final draft = r.begin(fixture.task, 'title', batch: 'partial');
        draft.change(const DraftValue('Buy oats!'));
        final raw = r.prepareSave(draft);
        final file = File('${dir.path}/records.jsonl');
        file.writeAsStringSync(
          raw.substring(0, raw.length ~/ 2),
          mode: FileMode.append,
          flush: true,
        );
        final before = file.readAsBytesSync();
        r.close();
        final reopened = fixture.replica(
          'tail-after',
          fixture.a,
          directory: dir,
        );
        expect(reopened.isBlocked, isTrue);
        expect(reopened.outboxRecords, contains(raw));
        expect(() => reopened.retryPrepared(raw), throwsStateError);
        expect(file.readAsBytesSync(), before);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
