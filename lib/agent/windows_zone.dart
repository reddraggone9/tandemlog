import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _GetZoneNative = Uint32 Function(Pointer<Uint8>);
typedef _GetZone = int Function(Pointer<Uint8>);
typedef _MapZoneNative =
    Int32 Function(
      Pointer<Uint16>,
      Int32,
      Pointer<Utf8>,
      Pointer<Uint16>,
      Int32,
      Pointer<Int32>,
    );
typedef _MapZone =
    int Function(
      Pointer<Uint16>,
      int,
      Pointer<Utf8>,
      Pointer<Uint16>,
      int,
      Pointer<Int32>,
    );

/// The headless counterpart of the app runner's `zone` method
/// (windows/runner/flutter_window.cpp): the Windows zone key mapped to its
/// IANA name by the system ICU, plus the current UTC offset.
({String id, int offsetSeconds}) readWindowsZone() {
  // DYNAMIC_TIME_ZONE_INFORMATION, 432 bytes.
  const size = 432,
      standardBias = 84,
      daylightMonth = 154,
      daylightBias = 168,
      keyName = 172,
      dstDisabled = 428;
  const invalid = 0xFFFFFFFF, daylight = 2;
  final kernel = DynamicLibrary.open('kernel32.dll');
  final getZone = kernel.lookupFunction<_GetZoneNative, _GetZone>(
    'GetDynamicTimeZoneInformation',
  );
  final info = calloc<Uint8>(size);
  final iana = calloc<Uint16>(256);
  final status = calloc<Int32>();
  try {
    final current = getZone(info);
    if (current == invalid) throw StateError('Windows time zone unavailable.');
    final data = info.asTypedList(size).buffer.asByteData();
    if (data.getUint8(dstDisabled) != 0 &&
        data.getUint16(daylightMonth, Endian.little) != 0) {
      throw StateError('Custom disabled-DST configuration is unsupported.');
    }
    final icu = DynamicLibrary.open('icu.dll');
    final mapZone = icu.lookupFunction<_MapZoneNative, _MapZone>(
      'ucal_getTimeZoneIDForWindowsID',
    );
    final length = mapZone(
      Pointer<Uint16>.fromAddress(info.address + keyName),
      -1,
      nullptr,
      iana,
      256,
      status,
    );
    if (status.value > 0 || length <= 0 || length >= 256) {
      throw StateError('Windows to IANA time zone mapping unavailable.');
    }
    final id = String.fromCharCodes(iana.asTypedList(length));
    final bias =
        data.getInt32(0, Endian.little) +
        data.getInt32(
          current == daylight ? daylightBias : standardBias,
          Endian.little,
        );
    return (id: id, offsetSeconds: -bias * 60);
  } finally {
    calloc.free(info);
    calloc.free(iana);
    calloc.free(status);
  }
}
