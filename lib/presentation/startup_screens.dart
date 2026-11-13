import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
class StartupLoading extends StatefulWidget {
  const StartupLoading({super.key});

  @override
  State<StartupLoading> createState() => _StartupLoadingState();
}

class _StartupLoadingState extends State<StartupLoading> {
  late final _warmup = TextStyleWarmup(Theme.of(context).textTheme);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmup.start();
  }

  @override
  void dispose() {
    _warmup.stop();
    super.dispose();
  }

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

/// Lee 11-13 (60 fps): the first text laid out in a font weight or slant
/// the engine has not matched yet makes it match one (Fontconfig on Linux,
/// about 18 ms each on Bender), and the first list needed several at once:
/// one 57-74 ms frame. While the loading bar runs, lay out one sample per
/// variant the first list uses (weights 500 and 700 besides the title's 400,
/// and the icon font), each in its own event-loop turn between frames, so
/// the list finds them matched. Variants already matched cost microseconds.
/// Starts after the opening's first frames so it does not delay reading
/// settings; nothing is drawn.
class TextStyleWarmup {
  TextStyleWarmup(TextTheme theme)
    : _samples = [
        if (theme.bodyMedium case final base?)
          for (final weight in const [FontWeight.w500, FontWeight.w700])
            TextSpan(
              text: _sample,
              style: base.copyWith(fontWeight: weight),
            ),
        TextSpan(
          text: String.fromCharCode(Icons.check.codePoint),
          style: TextStyle(
            fontFamily: Icons.check.fontFamily,
            package: Icons.check.fontPackage,
          ),
        ),
      ];

  final List<TextSpan> _samples;
  var _next = 0;
  var _running = false;
  Timer? _delay;
  static const _startAfter = Duration(milliseconds: 150);
  static const _sample = 'Tandemlog 0123456789';

  void start() {
    if (_running || _next >= _samples.length) return;
    _running = true;
    _delay = Timer(_startAfter, _afterNextFrame);
  }

  void stop() {
    _running = false;
    _delay?.cancel();
  }

  void _afterNextFrame() {
    if (!_running) return;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        // Its own event-loop turn, never inside a frame.
        if (_running) Timer.run(_turn);
      })
      ..ensureVisualUpdate();
  }

  void _turn() {
    if (!_running) return;
    TextPainter(text: _samples[_next++], textDirection: TextDirection.ltr)
      ..layout()
      ..dispose();
    if (_next >= _samples.length) {
      _running = false;
    } else {
      _afterNextFrame();
    }
  }
}

/// Data from a newer version: plain words, Update first, then [actions];
/// the exact message behind Technical details.
class UpdateAppScreen extends StatelessWidget {
  const UpdateAppScreen({
    super.key,
    required this.details,
    this.onUpdate,
    this.actions = const [],
  });
  final String details;

  /// Secondary actions beside Update (Retry, Settings): someone who can't
  /// update yet still needs to check again or reach Settings.
  final List<Widget> actions;

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
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
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
                  ...actions,
                ],
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
