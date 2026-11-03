import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../application/activity_log.dart';
import '../application/activity_values.dart';
import '../storage/unified_history.dart';

class ActivityLogDialog extends StatefulWidget {
  const ActivityLogDialog({
    super.key,
    required this.history,
    this.targetLabel,
    this.textAt,
  });
  final UnifiedHistory history;
  final String? Function(String id)? targetLabel;

  /// Resolves native title/notes text for the details view.
  final ActivityTextAt? textAt;
  @override
  State<ActivityLogDialog> createState() => _ActivityLogDialogState();
}

class _ActivityLogDialogState extends State<ActivityLogDialog> {
  late List<ActivityEntry> entries;
  late ActivityValues values;
  late String revision;
  // Visible rows with native title/notes edits, resolved one per frame so a
  // shared-text replay never stalls scrolling.
  final _pendingText = <ActivityEntry>[];
  bool _textScheduled = false;
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
    // Values are derived per visible row and per opened details, not here.
    values = ActivityValues(snapshot, textAt: widget.textAt);
    _pendingText.clear();
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

  ActivityDescription _row(ActivityEntry e) {
    final resolved = values.withText(e);
    if (resolved != null) return resolved;
    final d = values.describe(e);
    if (d.needsText && !_pendingText.contains(e)) {
      _pendingText.add(e);
      _scheduleText();
    }
    return d;
  }

  void _scheduleText() {
    if (_textScheduled) return;
    _textScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _textScheduled = false;
      if (!mounted || _pendingText.isEmpty) return;
      final e = _pendingText.removeAt(0);
      values.describe(e, text: true);
      setState(() {});
      if (_pendingText.isNotEmpty) _scheduleText();
    });
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
          'Each row shows the device that made the change, not the person '
          'using it. Device names may change.\n\n'
          'Changed fields show old → new, where old is the value that device '
          'had before the change. When devices changed the same field at the '
          'same time, or an earlier change was undone, only the new value is '
          'shown.\n\n'
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

  /// Names as recorded by the action, else the items' current names.
  String? _subject(ActivityEntry e, ActivityDescription d) {
    if (d.subject != null) return d.subject;
    final names = e.targets
        .map((id) => widget.targetLabel?.call(id))
        .whereType<String>()
        .toSet();
    if (names.isEmpty) return null;
    return '${names.take(2).join(', ')}'
        '${names.length > 2 ? ' and ${names.length - 2} more' : ''}';
  }

  Future<void> _details(ActivityEntry e) {
    final d = values.describe(e, text: true);
    final subject = _subject(e, d);
    final current = e.targets.length == 1
        ? widget.targetLabel?.call(e.targets.single)
        : null;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activity details'),
        content: SingleChildScrollView(
          child: SelectableText(
            [
              [e.summary, ?subject].join(': '),
              if (d.changes.isNotEmpty)
                d.changes.map((change) => change.line).join('\n'),
              if (current != null && d.subject != null && current != d.subject)
                'Now named: $current',
              'Recorded: ${activityTime(e.recordedAt)}',
              if (e.deviceNamed)
                'Device: ${e.device}'
              else
                'Device: Unnamed device\nDevice ID: ${e.writer}',
              if (e.historical) 'Imported historical record',
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
  }

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
      // Attribution and refresh failures share the rows' scroll viewport.
      // Fixed copy above an Expanded list can consume all available height at
      // large text sizes, leaving admitted history present but unreachable.
      child: ListView.builder(
        key: const ValueKey('activity-list'),
        itemCount: entries.length + 1 + (entries.isEmpty ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Activity could not refresh. Showing last admitted history.',
                      key: const ValueKey('activity-refresh-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            );
          }
          if (entries.isEmpty) {
            return const Center(child: Text('No activity yet.'));
          }
          final e = entries[i - 1];
          final d = _row(e);
          final subject = _subject(e, d);
          return ListTile(
            key: ValueKey(e.id),
            title: Text(
              [e.summary, ?subject].join(': '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                ...d.changes.take(3).map((change) => change.line),
                if (d.changes.length > 3) '${d.changes.length - 3} more…',
                '${activityTime(e.recordedAt)} · ${e.device}',
              ].join('\n'),
            ),
            isThreeLine: d.changes.isNotEmpty,
            onTap: () => _details(e),
          );
        },
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

/// Readable local civil time with an explicit numeric zone; never microseconds
/// or an ambiguous zone abbreviation alone. Canonical clock remains untouched.
String activityTime(DateTime instant) {
  final time = instant.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final offset = time.timeZoneOffset.inMinutes;
  final zone =
      '${offset < 0 ? '-' : '+'}${two(offset.abs() ~/ 60)}:${two(offset.abs() % 60)}';
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)} UTC$zone';
}
