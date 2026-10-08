import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/projection.dart';

void main() {
  test(
    'moving a legacy task below a native task uses both creation actions',
    () {
      expect(
        projectOrder(
          ['legacy', 'native'],
          const [
            OrderAction('legacy', 'task.created'),
            OrderAction('native', 'task.createdWithText'),
            OrderAction('legacy', 'task.moved'),
          ],
        ),
        ['native', 'legacy'],
      );
    },
  );

  test('native creation after a move keeps chronological manual ordering', () {
    expect(
      projectOrder(
        ['first', 'second', 'later'],
        const [
          OrderAction('first', 'task.createdWithText'),
          OrderAction('second', 'task.createdWithText'),
          OrderAction('first', 'task.moved'),
          OrderAction('later', 'task.createdWithText'),
        ],
      ),
      ['second', 'first', 'later'],
    );
  });
}
