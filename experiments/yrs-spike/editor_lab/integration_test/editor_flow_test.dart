// Native Flutter rendering/callback flow. Injected composition is explicitly
// separate from the manual OS-IME scenario in editor-matrix.json.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yrs_editor_lab/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('H11 native editor SaveCancelUndo and platform callback path', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    await tester.pumpWidget(const EditorLabApp());
    await tester.pumpAndSettle();
    expect(find.text('A😀B'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('begin-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('draft-field')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'A😀にB',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 3, end: 4),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('remote-prefix')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('draft-field')))
          .controller!
          .value
          .composing,
      const TextRange(start: 3, end: 4),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-draft')))
          .onPressed,
      isNull,
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'A😀日本B',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange.empty,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-draft')));
    await tester.pumpAndSettle();
    expect(find.text('REMOTE A😀日本B'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('undo')));
    await tester.pumpAndSettle();
    expect(find.text('REMOTE A😀B'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('redo')));
    await tester.pumpAndSettle();
    expect(find.text('REMOTE A😀日本B'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('begin-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('draft-field')),
      'discard',
    );
    await tester.tap(find.byKey(const ValueKey('cancel-draft')));
    await tester.pumpAndSettle();
    expect(find.text('REMOTE A😀日本B'), findsNWidgets(2));
  });
}
