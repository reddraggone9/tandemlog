import 'package:flutter/material.dart';

import '../domain/wall_time.dart';

/// Consent only. The caller owns capability admission and durable metadata.
Future<bool> confirmAdditionalTimeZones(
  BuildContext context, {
  int readerFloorBuild = additionalTimeZoneMinimumBuild,
  String readerFloorVersion = '2026.10.7-rc.3',
}) async {
  var answered = false;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          void answer(bool enable) {
            if (answered ||
                !dialogContext.mounted ||
                !(ModalRoute.isCurrentOf(dialogContext) ?? false)) {
              return;
            }
            answered = true;
            Navigator.of(dialogContext).pop(enable);
          }

          return AlertDialog(
            scrollable: true,
            title: const Text('Enable additional time zones?'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enable these additional time zones for this shared workspace:',
                  ),
                  const SizedBox(height: 12),
                  Text(additionalTimeZoneNames.join('\n')),
                  const SizedBox(height: 16),
                  Text(
                    'Use Tandemlog $readerFloorVersion (build $readerFloorBuild) '
                    'or later on every device. Update Tandemlog on every device '
                    'before continuing.',
                  ),
                  const SizedBox(height: 12),
                  const Text('Older apps will stop opening this workspace.'),
                  const SizedBox(height: 12),
                  const Text('This workspace upgrade cannot be undone.'),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('additional-time-zones-later'),
                autofocus: true,
                onPressed: () => answer(false),
                child: const Text('Later'),
              ),
              FilledButton(
                key: const ValueKey('additional-time-zones-enable'),
                onPressed: () => answer(true),
                child: const Text('Enable'),
              ),
            ],
          );
        },
      ) ??
      false;
}
