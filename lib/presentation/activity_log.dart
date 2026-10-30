import 'package:flutter/material.dart';
import '../application/activity_log.dart';
import '../storage/unified_history.dart';

class ActivityLogDialog extends StatefulWidget {
  const ActivityLogDialog({super.key, required this.history});
  final UnifiedHistory history;
  @override
  State<ActivityLogDialog> createState() => _ActivityLogDialogState();
}

class _ActivityLogDialogState extends State<ActivityLogDialog> {
  late List<ActivityEntry> entries;
  late String revision;
  bool failed = false;
  late void Function() removeListener;
  @override
  void initState() {
    super.initState();
    _read();
    removeListener = widget.history.listenChanges(_changed);
  }

  void _read() {
    final snapshot = widget.history.snapshot;
    entries = activityEntries(snapshot);
    revision = snapshot.revision;
    failed = widget.history.safetyFailure != null;
  }

  void _changed() {
    if (!mounted) return;
    final newFailure = widget.history.safetyFailure != null;
    if (revision != widget.history.snapshot.revision) {
      setState(_read);
    } else if (failed != newFailure) {
      // Health-only notifications retain rows without another history sort.
      setState(() => failed = newFailure);
    }
  }

  @override
  void dispose() {
    removeListener();
    super.dispose();
  }

  Future<void> _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('About Activity log'),
      content: const SingleChildScrollView(
        child: Text(
          'Newest recorded device time first, not sync arrival. Device clock skew '
          'and observed changes can shift these timestamps; exact occurrence '
          'order between offline devices is not known.\n\n'
          'The writing device is recorded, but the active user was not stored. '
          'Device names are advisory and may change; task assignees are not '
          'action authors. This view cannot authenticate a person.\n\n'
          'One row is one recorded action, including bulk actions. Imported '
          'history uses the original recorded time and writing device.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  Future<void> _details(ActivityEntry e) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Activity details'),
      content: SingleChildScrollView(
        child: SelectableText(
          [
            e.summary,
            'Operation: ${e.types.join(', ')}',
            'Recorded: ${e.recordedAt.toLocal().toIso8601String()}',
            'User: Not recorded',
            'Device: ${e.device}',
            'Device ID: ${e.writer}',
            'Action: ${e.id}',
            if (e.historical) 'Imported historical record',
            if (e.targets.isNotEmpty) 'Affected IDs:\n${e.targets.join('\n')}',
          ].join('\n\n'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Expanded(child: Text('Activity log')),
        IconButton(
          tooltip: 'About Activity log',
          onPressed: _help,
          icon: const Icon(Icons.help_outline),
        ),
      ],
    ),
    content: SizedBox(
      width: 640,
      height: 480,
      child: Column(
        children: [
          if (failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Activity could not refresh. Showing last admitted history.',
                key: const ValueKey('activity-refresh-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('No activity yet.'))
                : ListView.builder(
                    key: const ValueKey('activity-list'),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final time = e.recordedAt.toLocal();
                      return ListTile(
                        key: ValueKey(e.id),
                        title: Text(
                          e.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${time.toIso8601String().replaceFirst('T', ' ')}\n'
                          '${e.device} · User not recorded',
                        ),
                        isThreeLine: true,
                        onTap: () => _details(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
