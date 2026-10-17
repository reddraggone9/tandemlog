import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/form_validation.dart';

void main() {
  testWidgets(
    'neutral, blur-local errors, stable typing intent, deliberate review',
    (tester) async {
      final input = TextEditingController();
      final focus = FocusNode();
      var saves = 0;
      final validation = FormValidation(
        validate: () => input.text == 'good'
            ? []
            : [const FieldIssue('name', 'Enter a valid name.')],
      );
      input.addListener(() => validation.changed('name'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: validation,
              builder: (context, _) => Column(
                children: [
                  validation.field(
                    'name',
                    TextField(
                      controller: input,
                      focusNode: focus,
                      decoration: InputDecoration(
                        errorText: validation.errorFor('name'),
                      ),
                    ),
                  ),
                  ValidationActionButton(
                    validation: validation,
                    label: 'Save',
                    onSubmit: () {
                      saves++;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Enter a valid name.'), findsNothing);
      expect(find.text('Save'), findsOneWidget);
      final bounds = tester.getRect(find.byType(FilledButton));
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.pump();
      expect(find.text('Save'), findsOneWidget);
      focus.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid name.'), findsOneWidget);
      expect(find.text('Review errors'), findsOneWidget);
      expect(tester.getSize(find.byType(FilledButton)), bounds.size);
      await tester.tap(find.text('Review errors'));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(saves, 0);
      await tester.enterText(find.byType(TextField), 'good');
      await tester.pump();
      expect(find.text('Enter a valid name.'), findsNothing);
      expect(find.text('Review errors'), findsOneWidget);
      await tester.tap(find.text('Review errors'));
      await tester.pumpAndSettle();
      expect(
        saves,
        0,
        reason: 'Review remains review even after input becomes valid',
      );
      expect(find.text('Save'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      await tester.pumpWidget(const SizedBox());
      validation.dispose();
      input.dispose();
      focus.dispose();
    },
  );

  testWidgets('pointer-down review cannot save after blur restores validity', (
    tester,
  ) async {
    var invalid = true, saves = 0;
    final validation = FormValidation(
      validate: () => invalid ? [const FieldIssue('name', 'Invalid')] : [],
    );
    validation.blur('name');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValidationActionButton(
            validation: validation,
            label: 'Save',
            onSubmit: () {
              saves++;
            },
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FilledButton)),
    );
    invalid = false;
    validation.blur('name');
    await tester.pump();
    expect(find.text('Save'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(saves, 0);
    await tester.pumpWidget(const SizedBox());
    validation.dispose();
  });

  testWidgets('composition does not change settled action or local error', (
    tester,
  ) async {
    var invalid = true, composing = false;
    final validation = FormValidation(
      validate: () => invalid ? [const FieldIssue('name', 'Invalid')] : [],
      isComposing: (_) => composing,
    );
    validation.blur('name');
    expect(validation.errorFor('name'), 'Invalid');
    composing = true;
    invalid = false;
    validation.changed('name');
    validation.blur('name');
    expect(validation.reviewRequired, isTrue);
    expect(validation.errorFor('name'), 'Invalid');
    composing = false;
    validation.changed('name');
    expect(validation.errorFor('name'), isNull);
    expect(validation.reviewRequired, isTrue);
    validation.blur('name');
    expect(validation.reviewRequired, isFalse);
    validation.dispose();
  });

  testWidgets(
    'async activation is one-shot and pending retry skips current validation',
    (tester) async {
      var saves = 0, validations = 0;
      final completion = Completer<void>();
      final validation = FormValidation(
        validate: () {
          validations++;
          return [const FieldIssue('name', 'Invalid')];
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValidationActionButton(
              validation: validation,
              label: 'Save',
              retry: true,
              onSubmit: () {
                saves++;
                return completion.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Retry Save'));
      await tester.tap(find.text('Retry Save'));
      expect(saves, 1);
      expect(validations, 0);
      completion.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      validation.dispose();
    },
  );
}
