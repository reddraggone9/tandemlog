import 'package:flutter/material.dart';

Future<String?> askUnsavedDraft(BuildContext context) {
  var answered = false;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      void answer(String choice) {
        // A second queued activation still holds the closing dialog's context.
        // It must never pop the editor or a newer route underneath/above it.
        if (answered ||
            !dialogContext.mounted ||
            !(ModalRoute.isCurrentOf(dialogContext) ?? false)) {
          return;
        }
        answered = true;
        Navigator.of(dialogContext).pop(choice);
      }

      return AlertDialog(
        scrollable: true,
        title: const Text('Unsaved changes'),
        content: const Text('Save your draft before continuing?'),
        actions: [
          TextButton(
            onPressed: () => answer('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => answer('discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => answer('save'),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}
