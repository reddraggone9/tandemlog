import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/utf8_size_guard_cases.dart';

void main() {
  test('UTF8 size guards retain e23 caller errors and ordering', () {
    final expected =
        jsonDecode(
              File(
                'test/fixtures/utf8-size-guards/callers-e23.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(utf8CallerOutcomes(), expected['errors']);
    expect(utf8FrozenRecordValues(), expected['wire']);
  });

  test(
    'current operation fixtures and independent Unicode action stay frozen',
    () {
      for (final (name, expected) in [
        (
          'persons.operations',
          '4c8c32877d15e520e510a8d96d4b38fb9cd16787f9a15c1875e010f3e52b741d',
        ),
        (
          'food.operations',
          '79de9af9c528fafebea549beb95397d15b0549d05412eb106e379cb9933d369f',
        ),
      ]) {
        expect(
          sha256
              .convert(
                File(
                  'test/fixtures/current-operation-v1/$name',
                ).readAsBytesSync(),
              )
              .toString(),
          expected,
        );
      }
      final raw = File(
        'test/fixtures/utf8-size-guards/action-v5.jsonl',
      ).readAsLinesSync().single;
      expect(namedAction().encode(), raw);
    },
  );
}
