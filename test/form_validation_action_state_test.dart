import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/form_validation.dart';

void main() {
  test('revealed issues and action share validity after each correction', () {
    var badDate = true, badTime = true;
    final validation = FormValidation(
      validate: () => [
        if (badDate) const FieldIssue('date', 'Invalid date'),
        if (badTime) const FieldIssue('time', 'Invalid time'),
      ],
    );
    validation.blur('date');
    expect(validation.reviewRequired, isTrue);
    badDate = false;
    validation.changed('date');
    expect(validation.errorFor('date'), isNull);
    expect(validation.errorFor('time'), isNull);
    expect(
      validation.reviewRequired,
      isFalse,
      reason: 'An unrevealed unrelated issue does not leave a stale Review.',
    );
    validation.blur('time');
    expect(validation.reviewRequired, isTrue);
    badTime = false;
    validation.changed('time');
    expect(validation.errorFor('time'), isNull);
    expect(validation.reviewRequired, isFalse);
    badDate = true;
    validation.changed('date');
    expect(validation.errorFor('date'), 'Invalid date');
    expect(validation.reviewRequired, isTrue);
    validation.dispose();
  });

  test(
    'related field correction clears its primary error and action together',
    () {
      var invalidOrder = true;
      final validation = FormValidation(
        validate: () => [
          if (invalidOrder)
            const FieldIssue('due', 'Before Start', relatedFields: ['start']),
        ],
      );
      validation.blur('start');
      expect(validation.errorFor('due'), 'Before Start');
      expect(validation.reviewRequired, isTrue);
      invalidOrder = false;
      validation.changed('start');
      expect(validation.errorFor('due'), isNull);
      expect(validation.reviewRequired, isFalse);
      validation.dispose();
    },
  );

  test(
    'composition commits settle validity without requiring a second blur',
    () {
      var invalid = true, composing = false;
      final validation = FormValidation(
        validate: () => invalid ? [const FieldIssue('date', 'Invalid')] : [],
        isComposing: (_) => composing,
      );
      validation.blur('date');
      composing = true;
      invalid = false;
      validation.changed('date');
      expect(validation.errorFor('date'), 'Invalid');
      expect(validation.reviewRequired, isTrue);
      composing = false;
      validation.changed('date');
      expect(validation.errorFor('date'), isNull);
      expect(validation.reviewRequired, isFalse);
      validation.dispose();
    },
  );

  test(
    'pristine invalid typing stays quiet; reset clears old revealed state',
    () {
      var invalid = true;
      final validation = FormValidation(
        validate: () => invalid ? [const FieldIssue('date', 'Invalid')] : [],
      );
      validation.changed('date');
      expect(validation.errorFor('date'), isNull);
      expect(validation.reviewRequired, isFalse);
      validation.blur('date');
      expect(validation.reviewRequired, isTrue);
      validation.reset();
      validation.changed('date');
      expect(validation.errorFor('date'), isNull);
      expect(validation.reviewRequired, isFalse);
      invalid = false;
      validation.changed('date');
      expect(validation.reviewRequired, isFalse);
      validation.dispose();
    },
  );
}
