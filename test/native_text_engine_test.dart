import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/text/native_text_engine.dart';

void main() {
  test('missing native library is an explicit failure', () {
    expect(
      () => NativeTextEngine(libraryPath: '/missing/tandemlog_text.so'),
      throwsA(isA<NativeTextException>()),
    );
  });
  test('operation bytes require exact canonical Base64 and bounded size', () {
    for (final invalid in [null, 1, 'AA', 'AA==\n', 'AB==', 'AA-_']) {
      expect(() => NativeTextUpdate.parse(invalid), throwsFormatException);
    }
    expect(
      () => NativeTextUpdate.parse(base64Encode(Uint8List(1024 * 1024 + 1))),
      throwsFormatException,
    );
    expect(NativeTextUpdate.parse('AAA=').encoded, 'AAA=');
  });

  final libraryPath =
      Platform.environment['TANDEMLOG_TEXT_LIBRARY'] ??
      Platform.environment['SPIKE_LIBRARY'];
  group(
    'actual production FFI',
    () {
      late NativeTextEngine engine;
      setUp(() => engine = NativeTextEngine(libraryPath: libraryPath!));
      tearDown(() => engine.dispose());
      NativeTextDocument document(
        int actor, {
        String text = 'A😀B',
        int limit = 500,
      }) => engine.createDocument(
        actorClientId: actor,
        limits: NativeTextLimits(visibleUtf16: limit),
        seed: engine.seedText(text),
      );

      test(
        'pending named Undo rejects a different operation and keeps exact retry',
        () {
          final source = document(300, text: 'A');
          final owner = document(301, text: 'A');
          for (final (actor, title, operation) in [
            (302, 'AX', 'first'),
            (303, 'AXY', 'second'),
          ]) {
            final draft = source.captureDraft(actorClientId: actor)
              ..replaceText(title);
            final save = draft.prepareSave();
            save.commit(receiptUpdate: save.update);
            owner.applyOwnedReceipt(save.update, operationId: operation);
          }
          final before = owner.fullState.encoded;
          final first = owner.prepareOperationUndo(operationId: 'first');
          expect(
            () => owner.prepareOperationUndo(operationId: 'second'),
            throwsA(isA<NativeTextException>()),
          );
          expect(
            () => owner.prepareUndo(),
            throwsA(isA<NativeTextException>()),
          );
          expect(
            identical(owner.prepareOperationUndo(operationId: 'first'), first),
            isTrue,
          );
          expect(owner.fullState.encoded, before);
          first.cancel();
          final second = owner.prepareOperationUndo(operationId: 'second');
          second.commit(receiptUpdate: second.update);
          expect(owner.read().text, 'AX');
          final retry = owner.prepareOperationUndo(operationId: 'first');
          retry.commit(receiptUpdate: retry.update);
          expect(owner.read().text, 'A');
        },
      );
      test(
        'dedicated receipt owner never undoes an older Save after remote cancellation',
        () {
          final live = document(200, text: 'A');
          final first = live.captureDraft(actorClientId: 201)
            ..replaceText('AX');
          final firstPacket = first.prepareSave();
          firstPacket.commit(receiptUpdate: firstPacket.update);
          final baseline = live.checkpoint();
          final second = live.captureDraft(actorClientId: 202)
            ..replaceText('AXY');
          final secondPacket = second.prepareSave();
          secondPacket.commit(receiptUpdate: secondPacket.update);
          final owner = engine.restoreDocument(
            actorClientId: 203,
            limits: const NativeTextLimits(visibleUtf16: 500),
            checkpoint: baseline,
          );
          owner.applyLocalReceipt(secondPacket.update);
          final remote = live.captureDraft(actorClientId: 204)
            ..replaceText('AX');
          final remotePacket = remote.prepareSave();
          remotePacket.commit(receiptUpdate: remotePacket.update);
          owner.applyRemote(remotePacket.update);
          expect(owner.read().text, 'AX');
          expect(
            () => owner.prepareUndo(),
            throwsA(isA<NativeTextException>()),
          );
          expect(owner.read().text, 'AX');
          owner.dispose();
          expect(
            () => owner.applyLocalReceipt(secondPacket.update),
            throwsStateError,
          );
        },
      );

      test(
        'captured Unicode edit survives remote arrival and receipt-gated Save',
        () {
          final a = document(2), b = document(3);
          final draft = a.captureDraft(actorClientId: 4);
          draft.replaceText('A😀BL');
          final remote = b.captureDraft(actorClientId: 5)..replaceText('RA😀B');
          final remoteSave = remote.prepareSave();
          remoteSave.commit(receiptUpdate: remoteSave.update);
          a.applyRemote(remoteSave.update);
          expect(draft.capturedText, 'A😀BL');
          final before = a.fullState.encoded;
          final save = draft.prepareSave();
          expect(a.fullState.encoded, before);
          expect(
            () => draft.replaceText('changed after prepare'),
            throwsStateError,
          );
          save.commit(receiptUpdate: save.update);
          b.applyRemote(save.update);
          expect(a.read().text, b.read().text);
          expect(a.read().text, 'RA😀BL');
          expect(draft.isClosed, isTrue);
          expect(save.commit(receiptUpdate: save.update).text, 'RA😀BL');
        },
      );

      test('IME and wrong-source preparation preserve the captured draft', () {
        final a = document(2), other = document(3);
        final draft = a.captureDraft(actorClientId: 4)..replaceText('A😀BC');
        final before = a.fullState.encoded;
        draft.setComposing(true);
        expect(() => draft.prepareSave(), throwsStateError);
        expect(draft.capturedText, 'A😀BC');
        draft.setComposing(false);
        expect(() => draft.prepareSave(target: other), throwsStateError);
        expect(a.fullState.encoded, before);
        expect(draft.capturedText, 'A😀BC');
        draft.cancel();
        draft.cancel();
        expect(a.fullState.encoded, before);
      });

      test('rejected receipt preserves live state, draft and prior Undo', () {
        final a = document(2, text: 'x');
        final first = a.captureDraft(actorClientId: 3)..replaceText('xL');
        final saved = first.prepareSave();
        saved.commit(receiptUpdate: saved.update);
        final next = a.captureDraft(actorClientId: 4)..replaceText('xLN');
        final pending = next.prepareSave();
        final before = a.fullState.encoded;
        expect(
          () => pending.commit(receiptUpdate: engine.seedText('wrong')),
          throwsStateError,
        );
        expect(a.fullState.encoded, before);
        expect(next.capturedText, 'xLN');
        next.cancel();
        final undo = a.prepareUndo();
        expect(a.fullState.encoded, before);
        expect(
          () => undo.commit(receiptUpdate: engine.seedText('wrong')),
          throwsStateError,
        );
        expect(a.fullState.encoded, before);
        undo.commit(receiptUpdate: undo.update);
        expect(a.read().text, 'x');
        expect(undo.commit(receiptUpdate: undo.update).text, 'x');
      });

      test(
        'prepared Undo keeps remote text and cancellation retains prior stack',
        () {
          final a = document(2, text: 'x'), b = document(3, text: 'x');
          final local = a.captureDraft(actorClientId: 4)..replaceText('xL');
          final save = local.prepareSave();
          save.commit(receiptUpdate: save.update);
          b.applyRemote(save.update);
          final cancelled = a.prepareUndo();
          cancelled.cancel();
          cancelled.cancel();
          expect(a.read().text, 'xL');
          final undo = a.prepareUndo();
          final remote = b.captureDraft(actorClientId: 5)..replaceText('RxL');
          final remoteSave = remote.prepareSave();
          remoteSave.commit(receiptUpdate: remoteSave.update);
          a.applyRemote(remoteSave.update);
          undo.commit(receiptUpdate: undo.update);
          b.applyRemote(undo.update);
          expect(a.read().text, 'Rx');
          expect(a.read().text, b.read().text);
        },
      );

      test(
        'invalid update, field limit and split surrogate rejection are atomic',
        () {
          final a = document(2, text: 'A😀B', limit: 5);
          final draft = a.captureDraft(actorClientId: 3);
          final before = a.fullState.encoded;
          expect(() => draft.replaceText('A😀BBB'), throwsFormatException);
          expect(
            () => draft.replaceText(String.fromCharCodes([0xd800])),
            throwsFormatException,
          );
          expect(
            () => a.applyRemote(NativeTextUpdate.parse('/w==')),
            throwsA(isA<NativeTextException>()),
          );
          expect(a.fullState.encoded, before);
          expect(draft.capturedText, 'A😀B');
          draft.replaceText('A🦀B');
          final save = draft.prepareSave();
          save.commit(receiptUpdate: save.update);
          expect(a.read().text, 'A🦀B');
        },
      );

      test(
        'native remote limit rejection preserves source and captured draft',
        () {
          final a = document(2, text: 'xx', limit: 2);
          final remote = document(3, text: 'xx', limit: 10);
          final captured = a.captureDraft(actorClientId: 4);
          final draft = remote.captureDraft(actorClientId: 5)
            ..replaceText('xxx');
          final save = draft.prepareSave();
          save.commit(receiptUpdate: save.update);
          final before = a.fullState.encoded;
          expect(
            () => a.applyRemote(save.update),
            throwsA(isA<NativeTextException>()),
          );
          expect(a.fullState.encoded, before);
          expect(a.read().text, 'xx');
          expect(captured.capturedText, 'xx');
        },
      );

      test('inspection reports struct authors rather than delivery owner', () {
        final a = document(2, text: 'x');
        expect(engine.inspect(engine.seedText('x')), [1]);
        final draft = a.captureDraft(actorClientId: 3)..replaceText('xL');
        final save = draft.prepareSave();
        expect(engine.inspect(save.update), [3]);
      });

      test(
        'checkpoint includes pending operations and restores with a fresh GUID',
        () {
          final a = document(2, text: 'x'), b = document(3, text: 'x');
          final first = b.captureDraft(actorClientId: 4)..replaceText('xA');
          final firstSave = first.prepareSave();
          firstSave.commit(receiptUpdate: firstSave.update);
          final second = b.captureDraft(actorClientId: 5)..replaceText('xAB');
          final secondSave = second.prepareSave();
          secondSave.commit(receiptUpdate: secondSave.update);
          a.applyRemote(secondSave.update);
          expect(a.read().pending, isTrue);
          final restored = engine.restoreDocument(
            actorClientId: 6,
            limits: const NativeTextLimits(visibleUtf16: 500),
            checkpoint: a.checkpoint(),
          );
          expect(restored.guid, isNot(a.guid));
          expect(restored.read().pending, isTrue);
          restored.applyRemote(firstSave.update);
          expect(restored.read().pending, isFalse);
          expect(restored.read().text, 'xAB');
        },
      );

      test(
        'foreign handles, disposed generations and actor collisions fail explicitly',
        () {
          final a = document(2);
          final foreign = NativeTextEngine(libraryPath: libraryPath);
          try {
            expect(
              () => foreign.captureDraft(a, actorClientId: 3),
              throwsStateError,
            );
            expect(() => document(2), throwsA(isA<NativeTextException>()));
            final draft = a.captureDraft(actorClientId: 3);
            a.dispose();
            a.dispose();
            expect(draft.isClosed, isTrue);
            expect(() => a.read(), throwsStateError);
            final fresh = document(2);
            expect(fresh.handleId, isNot(a.handleId));
            expect(fresh.guid, isNot(a.guid));
            engine.dispose();
            engine.dispose();
            expect(() => fresh.read(), throwsStateError);
          } finally {
            foreign.dispose();
          }
        },
      );
    },
    skip: libraryPath == null
        ? 'Provide an explicit actual production library path'
        : false,
  );
}
