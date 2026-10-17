import 'package:flutter/material.dart';

Future<void> showTaskFieldHelp(
  BuildContext context, {
  FocusNode? restoreFocus,
}) async {
  final previousFocus = restoreFocus ?? FocusManager.instance.primaryFocus;
  final ownerRoute = ModalRoute.of(context);
  var answered = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Task field help'),
      scrollable: true,
      content: const SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HelpTopic(
              'Start',
              'Hide this task from Open until this date and time. Show upcoming '
                  'or search can still show it. Without a time, it starts at '
                  'midnight; without a Start date, it is available now.',
            ),
            _HelpTopic(
              'Due',
              'When you want to finish this task. Used to group and sort it '
                  'unless This occurrence or Sort-date bounds changes its list '
                  'position. Due does not hide the task.',
            ),
            _HelpTopic(
              'Repeat',
              'Create the next task when you complete this one. Repeat advances '
                  'from Due, otherwise This occurrence, otherwise Start. Add '
                  '“when done” to calculate from the completion day instead. '
                  'Start and Due keep their gap in calendar days and their times.',
            ),
            _HelpTopic(
              'This occurrence',
              'Choose a different date and time for this task’s list position. '
                  'Set Due and Repeat to edit it. Removing either clears this '
                  'value for the draft; Cancel keeps saved values. '
                  'Start, Due and the Repeat rule stay unchanged. The next task '
                  'uses its next Due date. With “when done”, completing later '
                  'can still move that next Due date.',
            ),
            _HelpTopic(
              'Sort-date bounds',
              'Limit the day used to group and sort this task. Values are calendar '
                  'days from today; 0 means today. Minimum days pushes an earlier '
                  'sorting day forward. Maximum days pulls a later sorting day '
                  'back, or supplies one if there is no date. The limits move '
                  'with today. Start, Due and Repeat stay unchanged.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (answered ||
                !dialogContext.mounted ||
                ModalRoute.of(dialogContext)?.isCurrent != true) {
              return;
            }
            answered = true;
            Navigator.pop(dialogContext);
          },
          child: const Text('Done'),
        ),
      ],
    ),
  );
  if (context.mounted &&
      ownerRoute?.isCurrent == true &&
      previousFocus?.context != null) {
    previousFocus!.requestFocus();
    await WidgetsBinding.instance.endOfFrame;
    final focusedContext = previousFocus.context;
    if (context.mounted &&
        ownerRoute?.isCurrent == true &&
        previousFocus.hasFocus &&
        focusedContext != null &&
        focusedContext.mounted) {
      BuildContext revealContext = focusedContext;
      focusedContext.visitAncestorElements((element) {
        if (element.widget is InputDecorator) {
          revealContext = element;
          return false;
        }
        return true;
      });
      await Scrollable.ensureVisible(
        revealContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  }
}

class _HelpTopic extends StatelessWidget {
  const _HelpTopic(this.title, this.text);
  final String title, text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(height: 4),
        Text(text),
      ],
    ),
  );
}
