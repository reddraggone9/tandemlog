import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where "Update" sends someone: the latest release, which lists every
/// platform's installer.
final appUpdateUri = Uri.parse(
  'https://github.com/reddraggone9/tandemlog/releases/latest',
);

/// History or an operation written by a newer app: every such refusal says
/// "Update the app". Other failures (integrity, access) are not this.
bool needsAppUpdate(String? message) =>
    message != null && message.contains('Update the app');

/// While the workspace opens: the app name and a moving bar, nothing that
/// guesses at onboarding or failure (design/recovery.md).
class StartupLoading extends StatelessWidget {
  const StartupLoading({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      key: const ValueKey('workspace-opening'),
      liveRegion: true,
      label: 'Opening Tandemlog',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tandemlog', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
  );
}

/// Data from a newer version: plain words, one Update action, the exact
/// message behind Technical details.
class UpdateAppScreen extends StatelessWidget {
  const UpdateAppScreen({super.key, required this.details, this.onUpdate});
  final String details;

  /// Defaults to opening [appUpdateUri].
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        key: const ValueKey('update-app'),
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Update Tandemlog',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Another device saved changes with a newer version of '
                'Tandemlog. Update this device to keep going; nothing was lost.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 48),
                  visualDensity: VisualDensity.standard,
                ),
                onPressed:
                    onUpdate ??
                    () => launchUrl(
                      appUpdateUri,
                      mode: LaunchMode.externalApplication,
                    ),
                child: const Text('Update'),
              ),
              const SizedBox(height: 16),
              Theme(
                // A plain disclosure, without the tile's divider lines.
                data: theme.copyWith(dividerColor: Colors.transparent),
                // Its own Material: the stopped-workspace panel paints a
                // ColoredBox that would hide the tile's ink.
                child: Material(
                  type: MaterialType.transparency,
                  child: ExpansionTile(
                    key: const ValueKey('update-app-details'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    expandedAlignment: Alignment.centerLeft,
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    title: Text(
                      'Technical details',
                      style: theme.textTheme.bodyMedium,
                    ),
                    children: [
                      SelectableText(
                        details,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: details)),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
