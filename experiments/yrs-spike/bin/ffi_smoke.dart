// Implements prewritten native ABI gate N01/N02/N03; disposable data only.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

final library = DynamicLibrary.open(Platform.environment['SPIKE_LIBRARY']!);
final allocate = library
    .lookupFunction<
      Pointer<Uint8> Function(UintPtr),
      Pointer<Uint8> Function(int)
    >('spike_alloc');
final releaseInput = library
    .lookupFunction<
      Void Function(Pointer<Uint8>, UintPtr),
      void Function(Pointer<Uint8>, int)
    >('spike_release_input');
final request = library
    .lookupFunction<
      Pointer<Uint8> Function(Pointer<Uint8>),
      Pointer<Uint8> Function(Pointer<Uint8>)
    >('spike_json');
final release = library
    .lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)
    >('spike_free');

Map<String, dynamic> call(String op, [Map<String, dynamic> data = const {}]) {
  final raw = utf8.encode(jsonEncode({'op': op, ...data}));
  final p = allocate(raw.length + 1);
  p.asTypedList(raw.length + 1).setAll(0, [...raw, 0]);
  final out = request(p);
  releaseInput(p, raw.length + 1);
  if (out == nullptr) throw StateError('Null response');
  try {
    var n = 0;
    while (out[n] != 0 && n < 300000) {
      n++;
    }
    if (n == 300000) throw StateError('Response limit');
    final value =
        jsonDecode(utf8.decode(out.asTypedList(n))) as Map<String, dynamic>;
    if (value.containsKey('error')) throw StateError(value['error'] as String);
    return value;
  } finally {
    release(out);
  }
}

void check(Object? actual, Object? expected) {
  if (actual != expected) throw StateError('$actual != $expected');
}

void main() {
  call('reset');
  final seed = call('seed', {'text': 'A😀B'})['update'];
  call('new', {'name': 'a', 'client': 10, 'seed': seed});
  call('new', {'name': 'b', 'client': 20, 'seed': seed});
  call('draft', {'name': 'draft', 'source': 'a', 'client': 30});
  call('edit', {'name': 'draft', 'index': 3, 'delete': 0, 'insert': '日本'});
  check(call('read', {'name': 'a'})['text'], 'A😀B');
  final remote = call('edit', {
    'name': 'b',
    'index': 0,
    'delete': 0,
    'insert': 'REMOTE ',
  })['update'];
  call('apply', {'name': 'a', 'update': remote});
  final saved = call('save', {'name': 'draft', 'target': 'a'})['update'];
  call('apply', {'name': 'b', 'update': saved});
  check(call('read', {'name': 'b'})['text'], 'REMOTE A😀日本B');
  final undo = call('undo', {'name': 'a'})['update'];
  call('apply', {'name': 'b', 'update': undo});
  check(call('read', {'name': 'b'})['text'], 'REMOTE A😀B');
  call('draft', {'name': 'cancelled', 'source': 'a', 'client': 40});
  call('edit', {
    'name': 'cancelled',
    'index': 0,
    'delete': 0,
    'insert': 'DISCARD ',
  });
  call('cancel', {'name': 'cancelled'});
  check(call('read', {'name': 'a'})['text'], 'REMOTE A😀B');
  stdout.writeln(
    jsonEncode({
      'native_ffi': 'pass',
      'os': Platform.operatingSystem,
      'dart': Platform.version,
      'scope':
          'synthetic ABI/UTF16/captured Save/Cancel/selective Undo; not UI/native IME',
    }),
  );
}
