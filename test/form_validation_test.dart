import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets(
      'primary gesture retains its target through input blur for $kind',
      (tester) async {
        final input = TextEditingController(text: 'bad');
        final inputFocus = FocusNode();
        final scroll = ScrollController();
        var saves = 0;
        final validation = FormValidation(
          validate: () => [
            const FieldIssue('name', 'Enter a valid name before saving.'),
          ],
        );
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    height: 300,
                    child: ListenableBuilder(
                      listenable: validation,
                      builder: (context, _) => SingleChildScrollView(
                        controller: scroll,
                        child: Column(
                          children: [
                            validation.field(
                              'name',
                              TextField(
                                controller: input,
                                focusNode: inputFocus,
                                decoration: InputDecoration(
                                  labelText: 'Name',
                                  errorText: validation.errorFor('name'),
                                  errorMaxLines: 3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 600),
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
                ),
              ),
            ),
          );
          inputFocus.requestFocus();
          await tester.pumpAndSettle();
          final action = find.byType(FilledButton);
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          final before = tester.getRect(action);
          final element = tester.element(action);
          final gesture = await tester.startGesture(before.center, kind: kind);
          // Native button focus can blur the input before a held tap completes.
          inputFocus.unfocus();
          await tester.pumpAndSettle();
          expect(identical(tester.element(action), element), isTrue);
          expect(
            tester.getRect(action),
            before,
            reason:
                'Blur must not move the primary target away from the held pointer',
          );
          await gesture.up();
          await tester.pumpAndSettle();
          expect(saves, 0);
          expect(inputFocus.hasFocus, isTrue);
          expect(
            find.text('Enter a valid name before saving.'),
            findsOneWidget,
          );
          final error = tester.getRect(
            find.text('Enter a valid name before saving.'),
          );
          expect(error.top, greaterThanOrEqualTo(0));
          expect(error.bottom, lessThanOrEqualTo(300));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          validation.dispose();
          input.dispose();
          inputFocus.dispose();
          scroll.dispose();
        }
      },
    );
  }
  testWidgets('held gesture cannot activate a replacement form', (
    tester,
  ) async {
    final old = FormValidation(
      validate: () => [const FieldIssue('name', 'Old error')],
    );
    final next = FormValidation(validate: () => []);
    final active = ValueNotifier<FormValidation>(old);
    var oldSaves = 0, newSaves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<FormValidation>(
            valueListenable: active,
            builder: (context, current, _) => ListenableBuilder(
              listenable: current,
              builder: (context, _) => Column(
                children: [
                  current.field(
                    'name',
                    TextField(
                      decoration: InputDecoration(
                        errorText: current.errorFor('name'),
                      ),
                    ),
                  ),
                  ValidationActionButton(
                    validation: current,
                    label: 'Save',
                    onSubmit: () {
                      if (identical(current, old)) {
                        oldSaves++;
                      } else {
                        newSaves++;
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FilledButton)),
    );
    old.blur('name');
    active.value = next;
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(oldSaves, 0);
    expect(newSaves, 0);
    expect(
      old.errorFor('name'),
      'Old error',
      reason: 'Retired pointer painting must be released',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(
      newSaves,
      1,
      reason: 'A separate gesture may submit the replacement form',
    );
    await tester.pumpWidget(const SizedBox());
    old.dispose();
    next.dispose();
    active.dispose();
  });

  testWidgets('older pointer cleanup cannot release a newer gesture', (
    tester,
  ) async {
    var invalid = true, saves = 0;
    final validation = FormValidation(
      validate: () =>
          invalid ? [const FieldIssue('name', 'Visible error')] : [],
    );
    validation.blur('name');
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
    final action = find.byType(FilledButton);
    final first = await tester.startGesture(tester.getCenter(action));
    await first.up();
    final second = await tester.startGesture(tester.getCenter(action));
    final bounds = tester.getRect(action);
    invalid = false;
    validation.blur('name');
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(
      tester.getRect(action),
      bounds,
      reason: 'The newer gesture still owns the painted error height',
    );
    await second.up();
    await tester.pumpAndSettle();
    expect(saves, 0, reason: 'The newer captured Review cannot become Save');
    expect(find.text('Visible error'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    validation.dispose();
  });

  testWidgets('cancelled primary pointer releases settled inline error', (
    tester,
  ) async {
    var saves = 0;
    final validation = FormValidation(
      validate: () => [const FieldIssue('name', 'Settled error')],
    );
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
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FilledButton)),
    );
    validation.blur('name');
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(validation.errorFor('name'), 'Settled error');
    expect(find.text('Settled error'), findsOneWidget);
    expect(saves, 0);
    await tester.pumpWidget(const SizedBox());
    validation.dispose();
  });

  testWidgets(
    'activation retains callback ownership while validation rebuilds',
    (tester) async {
      final replacement = ValueNotifier<bool>(false);
      var oldSaves = 0, newSaves = 0;
      final validation = FormValidation(
        validate: () => [],
        beforeReview: () {
          replacement.value = true;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: replacement,
              builder: (context, changed, _) => ValidationActionButton(
                validation: validation,
                label: 'Save',
                onSubmit: changed
                    ? () {
                        newSaves++;
                      }
                    : () {
                        oldSaves++;
                      },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(oldSaves, 1);
      expect(newSaves, 0);
      await tester.pumpWidget(const SizedBox());
      validation.dispose();
      replacement.dispose();
    },
  );
}
