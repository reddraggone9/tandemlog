// Executable expectations frozen before the isolated prepare implementation.
import 'package:flutter_test/flutter_test.dart';
import '../../editor_lab/lib/native_bridge.dart';

void main() {
  final bridge = NativeBridge();
  setUp(() {
    bridge.call('reset');
    final seed = bridge.call('seed', {'text': 'Buy oats'})['update'];
    bridge.call('new', {'name': 'live', 'client': 10, 'seed': seed});
    bridge.call('draft', {'name': 'draft', 'source': 'live', 'client': 20});
    bridge.call('edit', {
      'name': 'draft',
      'index': 8,
      'delete': 0,
      'insert': ' milk',
    });
  });
  test(
    'prepare returns repeatable bytes without mutating or consuming a draft',
    () {
      final first = bridge.call('prepare', {'name': 'draft', 'target': 'live'});
      final second = bridge.call('prepare', {
        'name': 'draft',
        'target': 'live',
      });
      expect(first['update'], second['update']);
      expect(bridge.call('read', {'name': 'live'})['text'], 'Buy oats');
      expect(bridge.call('read', {'name': 'draft'})['text'], 'Buy oats milk');
      final committed = bridge.call('save', {
        'name': 'draft',
        'target': 'live',
      });
      expect(committed['update'], first['update']);
    },
  );
  test('composing preparation rejects atomically and preserves the draft', () {
    bridge.call('composition', {'name': 'draft', 'active': true});
    expect(
      () => bridge.call('prepare', {'name': 'draft', 'target': 'live'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message.toString(),
          'reason',
          contains('composition'),
        ),
      ),
    );
    expect(bridge.call('read', {'name': 'live'})['text'], 'Buy oats');
    expect(bridge.call('read', {'name': 'draft'})['text'], 'Buy oats milk');
  });
  test('wrong-source preparation rejects before changing either document', () {
    final seed = bridge.call('seed', {'text': 'Other'})['update'];
    bridge.call('new', {'name': 'other', 'client': 30, 'seed': seed});
    expect(
      () => bridge.call('prepare', {'name': 'draft', 'target': 'other'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message.toString(),
          'reason',
          contains('source'),
        ),
      ),
    );
    expect(bridge.call('read', {'name': 'other'})['text'], 'Other');
    expect(bridge.call('read', {'name': 'draft'})['text'], 'Buy oats milk');
  });
  test('confirmed prepared local bytes retain selective native Undo', () {
    final packet = bridge.call('prepare', {'name': 'draft', 'target': 'live'});
    bridge.call('apply_local', {'name': 'live', 'update': packet['update']});
    final result = bridge.call('undo', {'name': 'live'});
    expect(result['changed'], isTrue);
    expect(result['text'], 'Buy oats');
  });
}
