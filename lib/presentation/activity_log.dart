import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../application/activity_log.dart';
import '../application/activity_values.dart';
import '../food/food_products.dart' show storeLinkLabel;
import '../storage/unified_history.dart';

class ActivityLogDialog extends StatefulWidget {
  const ActivityLogDialog({
    super.key,
    required this.history,
    this.targetLabel,
    this.textAt,
    this.canOpen,
    this.now = DateTime.now,
  });
  final UnifiedHistory history;
  final String? Function(String id)? targetLabel;

  /// Whether the item still exists and can be opened. The dialog then pops
  /// with that item's ID so the caller can open it.
  final bool Function(String id)? canOpen;

  /// Local clock for day headings and the device's current UTC offset.
  final DateTime Function() now;

  /// Resolves native title/notes text for the details view.
  final ActivityTextAt? textAt;
  @override
  State<ActivityLogDialog> createState() => _ActivityLogDialogState();
}

class _ActivityLogDialogState extends State<ActivityLogDialog> {
  late List<ActivityEntry> entries;

  /// List items: a day heading (String), an index into [entries], or one part
  /// of an expanded batched entry.
  late List<Object> items;

  /// Batched entries (record IDs) expanded inline.
  final _expanded = <String>{};
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
    items = _withDayHeadings();
    _pendingText.clear();
    revision = snapshot.revision;
    failed = widget.history.safetyFailure != null;
  }

  List<Object> _withDayHeadings() {
    final now = widget.now();
    final result = <Object>[];
    String? day;
    for (var i = 0; i < entries.length; i++) {
      final heading = activityDay(entries[i].recordedAt, now);
      if (heading != day) result.add(day = heading);
      result.add(i);
      if (_expanded.contains(entries[i].id)) {
        final parts = values.parts(entries[i]);
        for (final (j, part) in parts.indexed) {
          result.add(_Part(part, entries[i], last: j == parts.length - 1));
        }
      }
    }
    return result;
  }

  void _toggle(ActivityEntry e) => setState(() {
    if (!_expanded.remove(e.id)) _expanded.add(e.id);
    items = _withDayHeadings();
  });

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
          'One row is one recorded action. An action that changed several '
          'items, like a receipt import, expands into one row per item. '
          'Imported history uses the original recorded time and writing '
          'device.',
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

  String _headline(ActivityEntry e, ActivityDescription d) =>
      [e.summary, ?_subject(e, d)].join(': ');

  /// A part's line 1 inside [batch]: just the item when the summary already
  /// states the change (`3 foods added` over `Oat milk`), else the usual line.
  String _partHeadline(
    ActivityEntry e,
    ActivityDescription d,
    ActivityEntry batch,
  ) {
    final subject = _subject(e, d);
    if (subject != null && e.summary == values.summaryKind(batch)) {
      return subject;
    }
    return _headline(e, d);
  }

  String _meta(ActivityEntry e, {bool date = false}) {
    final offset = widget.now().timeZoneOffset;
    return '${date ? activityTime(e.recordedAt, currentOffset: offset) : activityClock(e.recordedAt, currentOffset: offset)}'
        ' · ${e.device}';
  }

  /// The one item this activity changed, when it can still be opened.
  String? _openable(ActivityEntry e) {
    final open = widget.canOpen;
    if (open == null || e.targets.length != 1) return null;
    return open(e.targets.single) ? e.targets.single : null;
  }

  Future<void> _details(ActivityEntry e) async {
    final d = values.describe(e, text: true);
    final current = e.targets.length == 1
        ? widget.targetLabel?.call(e.targets.single)
        : null;
    final target = _openable(e);
    // The row meta line's style (ListTile subtitle).
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('activity-details'),
        insetPadding: activityDialogInsets(context),
        title: Text(
          _headline(e, d),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: SizedBox(
          width: activityDetailsWidth(context),
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (d.changes.isNotEmpty) ...[
                    ActivityChangeList(d.changes),
                    const SizedBox(height: 16),
                  ],
                  Text(_meta(e, date: true), style: muted),
                  if (current != null &&
                      d.subject != null &&
                      current != d.subject)
                    Text('Now named $current', style: muted),
                ],
              ),
            ),
          ),
        ),
        actions: [
          if (target != null)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (open == true && mounted && target != null) {
      Navigator.pop(context, target);
    }
  }

  /// One change: a single-change record, or one part of a batched record.
  /// Parts are indented and leave out the parent's time and device.
  /// [batch] is set for a part shown inside its expanded batch.
  /// [last] marks the group's last part, which keeps a wider gap below.
  Widget _changeRow(
    ActivityEntry e, {
    ActivityEntry? batch,
    bool last = false,
  }) {
    final d = _row(e);
    final part = batch != null;
    final changes = part ? values.partChanges(batch, d.changes) : d.changes;
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey(e.key),
      // One even gap between rows, whatever their line count.
      minTileHeight: 0,
      // Parts sit tight together; the group keeps the usual gap around it.
      minVerticalPadding: part ? 4 : 8,
      // Bare item names would run into the next entry without a wider gap.
      contentPadding: part
          ? EdgeInsets.only(left: 40, right: 16, bottom: last ? 12 : 0)
          : null,
      // Parts read as the group's contents: the collapsed names line's size,
      // not the row title's.
      title: Text(
        part ? _partHeadline(e, d, batch) : _headline(e, d),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: part
            ? theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              )
            : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final change in changes.take(3))
            Text.rich(
              activityChangeSpan(change),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
          if (changes.length > 3) Text('+${changes.length - 3} more'),
          if (!part) Text(_meta(e)),
        ],
      ),
      // Parts open their own details; the chevron says so. It scales with
      // the text, like the summary's chevron.
      trailing: part
          ? Icon(
              Icons.chevron_right,
              key: const ValueKey('activity-part-opens'),
              size: MediaQuery.textScalerOf(context).scale(20),
              color: theme.colorScheme.onSurfaceVariant,
            )
          : null,
      onTap: () => _details(e),
    );
  }

  /// A record that changed several items: a summary that expands inline.
  Widget _batchRow(ActivityEntry e) {
    final summary = values.batchSummary(e);
    final expanded = _expanded.contains(e.id);
    return Semantics(
      expanded: expanded,
      child: ListTile(
        key: ValueKey(e.id),
        minTileHeight: 0,
        minVerticalPadding: 8,
        // The chevron follows the summary's last word: the row keeps the full
        // width, and a wrapped summary isn't split by it. The summary is a
        // short count, so it isn't cut (that would cut the chevron too).
        title: Text.rich(
          TextSpan(
            // No-break space: the chevron wraps with the last word.
            text: '${summary.title}\u00a0',
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ),
            ],
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Expanded, the parts below name the items themselves.
            if (summary.items != null && !expanded)
              Text(
                summary.items!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            Text(_meta(e)),
          ],
        ),
        onTap: () => _toggle(e),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: activityDialogInsets(context),
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
    // The window's height (dialog insets only), at most 640 wide: no fixed
    // box leaving empty space around a long log.
    content: SizedBox(
      width: 640,
      height: double.infinity,
      // Attribution and refresh failures share the rows' scroll viewport.
      // Fixed copy above an Expanded list can consume all available height at
      // large text sizes, leaving admitted history present but unreachable.
      child: ListView.builder(
        key: const ValueKey('activity-list'),
        itemCount: items.length + 1 + (entries.isEmpty ? 1 : 0),
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
          final item = items[i - 1];
          if (item is _Part) {
            return _changeRow(item.entry, batch: item.batch, last: item.last);
          }
          if (item is String) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Semantics(
                header: true,
                child: Text(
                  item,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            );
          }
          final e = entries[item as int];
          return values.parts(e).isEmpty ? _changeRow(e) : _batchRow(e);
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

String _two(int value) => value.toString().padLeft(2, '0');

String _zone(Duration offset) {
  final minutes = offset.inMinutes;
  return 'UTC${minutes < 0 ? '-' : '+'}${_two(minutes.abs() ~/ 60)}:${_two(minutes.abs() % 60)}';
}

/// Local time to the second. The numeric UTC offset is shown only when it
/// differs from [currentOffset], the device's offset now (DST, travel).
/// Canonical clocks remain untouched.
String activityClock(DateTime instant, {required Duration currentOffset}) {
  final time = instant.toLocal();
  final clock = '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';
  return time.timeZoneOffset == currentOffset
      ? clock
      : '$clock ${_zone(time.timeZoneOffset)}';
}

/// Full local date and time, for details where no day heading is shown.
String activityTime(DateTime instant, {required Duration currentOffset}) {
  final time = instant.toLocal();
  return '${time.year}-${_two(time.month)}-${_two(time.day)} '
      '${activityClock(instant, currentOffset: currentOffset)}';
}

/// Day heading: Today, Yesterday, else the Tasks heading `Monday · 2026-10-26`.
String activityDay(DateTime instant, DateTime now) {
  final time = instant.toLocal();
  final local = now.toLocal();
  final days = DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime.utc(time.year, time.month, time.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return '${weekdays[time.weekday - 1]} · '
      '${time.year}-${_two(time.month)}-${_two(time.day)}';
}

/// Phone-width Activity dialogs keep 16px margins instead of 40, so rows and
/// change values get the width instead of the margins.
EdgeInsets activityDialogInsets(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600
    ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
    : const EdgeInsets.symmetric(horizontal: 40, vertical: 24);

/// The details dialog's content width: at most 560, inside the dialog's
/// insets and content padding (24 each side).
double activityDetailsWidth(BuildContext context) => math.max(
  0,
  math.min(
    560,
    MediaQuery.sizeOf(context).width -
        activityDialogInsets(context).horizontal -
        48,
  ),
);

/// `Label: old → new`, label in medium weight.
TextSpan activityChangeSpan(ActivityChange change) => TextSpan(
  children: [
    TextSpan(
      text: '${change.label}: ',
      style: const TextStyle(fontWeight: FontWeight.w500),
    ),
    TextSpan(text: change.value),
  ],
);

/// Every change, one per line: a label column, then `old → new`, so long
/// values wrap under their own value. Narrow or large-text layouts that would
/// squeeze the values stack each value under its label instead.
class ActivityChangeList extends StatelessWidget {
  const ActivityChangeList(this.changes, {super.key});
  final List<ActivityChange> changes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium!.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final label = base.copyWith(fontWeight: FontWeight.w500);
    // Measured against the dialog's fixed content width: AlertDialog sizes
    // by intrinsic width, which a LayoutBuilder can't report.
    final width = activityDetailsWidth(context);
    return Builder(
      builder: (context) {
        // One rule for every dialog at a given width and text size: measure
        // a typical label, not this dialog's own, so food and task details
        // never lay out differently side by side.
        final painter = TextPainter(
          text: TextSpan(text: 'Expiration', style: label),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final widest = painter.width;
        painter.dispose();
        if (widest + 12 > width * 0.4) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final change in changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(change.label, style: label),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: _ChangeValue(change, style: base),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }
        return Table(
          columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
          children: [
            for (final change in changes)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12, bottom: 4),
                    child: Text(change.label, style: label),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _ChangeValue(change, style: base),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _Part {
  const _Part(this.entry, this.batch, {required this.last});
  final ActivityEntry entry;
  final ActivityEntry batch;
  final bool last;
}

/// `old → new`; store links in the new value open the store, labelled by its
/// name rather than the URL.
class _ChangeValue extends StatelessWidget {
  const _ChangeValue(this.change, {required this.style});
  final ActivityChange change;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final links = change.links;
    if (links == null || links.isEmpty) return Text(change.value, style: style);
    final link = style.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return Wrap(
      children: [
        if (change.before != null) Text('${change.before} → ', style: style),
        for (final (i, url) in links.indexed) ...[
          if (i > 0) Text(', ', style: style),
          Semantics(
            link: true,
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(storeLinkLabel(url), style: link),
            ),
          ),
        ],
      ],
    );
  }
}
