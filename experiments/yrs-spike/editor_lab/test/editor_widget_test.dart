// Frozen before harness implementation. Flutter composition/selection adapter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yrs_editor_lab/main.dart';

void main() {
  testWidgets(
    'H07 remote arrival preserves private selection and composition',
    (tester) async {
      await tester.pumpWidget(const EditorLabApp());
      await tester.tap(find.byKey(const ValueKey('begin-edit')));
      await tester.pump();
      final field = find.byKey(const ValueKey('draft-field'));
      await tester.tap(field);
      const value = TextEditingValue(
        text: 'A😀にB',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 3, end: 4),
      );
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('remote-prefix')));
      await tester.pump();
      final input = tester.widget<TextField>(field);
      expect(input.controller!.value, value);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('save-draft')))
            .onPressed,
        isNull,
      );
      expect(find.text('REMOTE A😀B'), findsNWidgets(2));
      tester.testTextInput.updateEditingValue(
        value.copyWith(
          text: 'A😀日本B',
          selection: const TextSelection.collapsed(offset: 5),
          composing: TextRange.empty,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-draft')));
      await tester.pump();
      expect(find.text('REMOTE A😀日本B'), findsNWidgets(2));
    },
  );
  testWidgets('H10 editor cancel and reopen use latest captured baseline', (
    tester,
  ) async {
    await tester.pumpWidget(const EditorLabApp());
    await tester.tap(find.byKey(const ValueKey('begin-edit')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('draft-field')),
      'Discard',
    );
    await tester.tap(find.byKey(const ValueKey('remote-prefix')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cancel-draft')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('begin-edit')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('draft-field')))
          .controller!
          .text,
      'REMOTE A😀B',
    );
  });
}
