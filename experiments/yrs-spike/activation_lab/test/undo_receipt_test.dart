// Filesystem compensation receipt cases written before coordinator integration.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../editor_lab/lib/native_bridge.dart';
import '../lib/activation.dart';
import 'activation_test.dart' as fixture;

String prepare(ActivationLab lab) =>
    (lab as dynamic).prepareUndo(fixture.task, 'title') as String;

void main() {
  setUp(() => NativeBridge().call('reset'));
  tearDown(() {
    for (final r in fixture.labs) {
      r.close();
    }
    fixture.labs.clear();
  });

  ActivationLab diskReplica(Directory dir) {
    final p = fixture.pair();
    return fixture.replica('disk', fixture.a, directory: dir)
      ..ingestAll([...p.base, p.activation]);
  }

  test('UF01 durable preparation preserves live text before receipt', () {
    final dir = Directory.systemTemp.createTempSync('undo-receipt-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final r = diskReplica(dir);
    fixture.edit(r, 'first', 'Buy oats and fruit');
    final before = File('${dir.path}/records.jsonl').readAsBytesSync();
    final raw = prepare(r);
    expect(r.text(fixture.task, 'title'), 'Buy oats and fruit');
    expect(File('${dir.path}/records.jsonl').readAsBytesSync(), before);
    expect(r.outboxRecords, contains(raw));
    expect(
      dir.listSync().where((f) => f.path.endsWith('.prepared')),
      hasLength(1),
    );
    expect(prepare(r), raw);
    r.retryPrepared(raw);
    expect(r.text(fixture.task, 'title'), 'Buy oats');
    expect(r.outboxRecords, isEmpty);
  });

  test(
    'UF02 interruption after append retains original bytes and restarts exact compensation',
    () {
      final dir = Directory.systemTemp.createTempSync('undo-restart-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final r = diskReplica(dir);
      fixture.edit(r, 'first', 'Buy oats and fruit');
      final raw = prepare(r);
      expect(
        () => r.retryPrepared(raw, failAfterAppend: true),
        throwsStateError,
      );
      expect(r.text(fixture.task, 'title'), 'Buy oats and fruit');
      expect(r.outboxRecords, contains(raw));
      final bytes = File('${dir.path}/records.jsonl').readAsBytesSync();
      r.close();
      final restarted = fixture.replica('restarted', fixture.a, directory: dir);
      expect(restarted.text(fixture.task, 'title'), 'Buy oats');
      restarted.retryPrepared(raw);
      restarted.retryPrepared(raw);
      expect(File('${dir.path}/records.jsonl').readAsBytesSync(), bytes);
      expect(restarted.records.where((record) => record == raw), hasLength(1));
      expect(restarted.outboxRecords, isEmpty);
    },
  );

  test(
    'UF03 same-process unknown receipt commits once and retains earlier Undo',
    () {
      final dir = Directory.systemTemp.createTempSync('undo-retry-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final r = diskReplica(dir);
      fixture.edit(r, 'one', 'Buy oats and fruit');
      fixture.edit(r, 'two', 'Buy oats and fruit and milk');
      final raw = prepare(r);
      expect(
        () => r.retryPrepared(raw, failAfterAppend: true),
        throwsStateError,
      );
      final afterAppend = File('${dir.path}/records.jsonl').readAsBytesSync();
      r.retryPrepared(raw);
      r.retryPrepared(raw);
      expect(File('${dir.path}/records.jsonl').readAsBytesSync(), afterAppend);
      expect(r.text(fixture.task, 'title'), 'Buy oats and fruit');
      r.undo(fixture.task, 'title');
      expect(r.text(fixture.task, 'title'), 'Buy oats');
    },
  );

  test(
    'UF04 remote arrival after preparation merges with immutable compensation',
    () {
      final p = fixture.pair();
      final update = fixture.edit(p.x, 'local', 'Buy oats and fruit');
      p.y.ingest(update);
      final raw = prepare(p.x);
      final packet = jsonDecode(raw) as Map<String, dynamic>;
      final remote = fixture.edit(p.y, 'remote', 'Urgent: Buy oats and fruit');
      p.x.ingest(remote);
      expect(p.x.text(fixture.task, 'title'), 'Urgent: Buy oats and fruit');
      expect(prepare(p.x), raw);
      p.x.retryPrepared(raw);
      p.y.ingest(raw);
      expect((jsonDecode(raw) as Map)['update'], packet['update']);
      expect(p.x.text(fixture.task, 'title'), 'Urgent: Buy oats');
      expect(p.y.text(fixture.task, 'title'), 'Urgent: Buy oats');
      expect(p.x.records, containsAll([update, remote, raw]));
    },
  );
}
