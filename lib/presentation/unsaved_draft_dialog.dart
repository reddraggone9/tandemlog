import 'package:flutter/material.dart';

Future<String?> askUnsavedDraft(BuildContext context, {bool allowSave = true}) {
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
        content: Text(
          allowSave
              ? 'Save your draft before continuing?'
              : 'The selection changed. Discard this unsaved draft to review the current selection?',
        ),
        actions: [
          TextButton(
            onPressed: () => answer('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => answer('discard'),
            child: const Text('Discard'),
          ),
          if (allowSave)
            FilledButton(
              onPressed: () => answer('save'),
              child: const Text('Save'),
            ),
        ],
      );
    },
  );
}
