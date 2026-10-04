// Synthetic laboratory only. No production application import or protocol.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

class NativeBridge {
  NativeBridge() {
    final configured = Platform.environment['SPIKE_LIBRARY'];
    final library = DynamicLibrary.open(
      configured ??
          (Platform.isAndroid
              ? 'libtandemlog_yrs_spike.so'
              : '${File(Platform.resolvedExecutable).parent.path}/lib/${Platform.isWindows ? 'tandemlog_yrs_spike.dll' : 'libtandemlog_yrs_spike.so'}'),
    );
    _allocate = library
        .lookupFunction<
          Pointer<Uint8> Function(UintPtr),
          Pointer<Uint8> Function(int)
        >('spike_alloc');
    _releaseInput = library
        .lookupFunction<
          Void Function(Pointer<Uint8>, UintPtr),
          void Function(Pointer<Uint8>, int)
        >('spike_release_input');
    _request = library
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Uint8>),
          Pointer<Uint8> Function(Pointer<Uint8>)
        >('spike_json');
    _release = library
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('spike_free');
  }
  late final Pointer<Uint8> Function(int) _allocate;
  late final void Function(Pointer<Uint8>, int) _releaseInput;
  late final Pointer<Uint8> Function(Pointer<Uint8>) _request;
  late final void Function(Pointer<Uint8>) _release;

  Map<String, dynamic> call(String op, [Map<String, dynamic> data = const {}]) {
    final raw = utf8.encode(jsonEncode({'op': op, ...data}));
    final p = _allocate(raw.length + 1);
    if (p == nullptr) throw StateError('Native input allocation rejected');
    Pointer<Uint8> out;
    try {
      p.asTypedList(raw.length + 1).setAll(0, [...raw, 0]);
      out = _request(p);
    } finally {
      _releaseInput(p, raw.length + 1);
    }
    if (out == nullptr) throw StateError('Native response is null');
    try {
      var n = 0;
      while (n < 300000 && out[n] != 0) {
        n++;
      }
      if (n == 300000) throw StateError('Native response size limit');
      final value =
          jsonDecode(utf8.decode(out.asTypedList(n))) as Map<String, dynamic>;
      if (value.containsKey('error'))
        throw StateError(value['error'] as String);
      return value;
    } finally {
      _release(out);
    }
  }
}
