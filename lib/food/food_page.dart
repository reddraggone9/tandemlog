import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../presentation/tag_input.dart';
import '../presentation/task_toolbar.dart';
import '../presentation/civil_date_input.dart';
import 'expiration_presentation.dart';
import 'inventory.dart';

/// The host owns commands/durability. The page only captures observed targets.
class FoodInventoryPage extends StatefulWidget {
  const FoodInventoryPage({
    super.key,
    required this.state,
    required this.onAdd,
    required this.onRemove,
    required this.onRestore,
    this.onRestoreBatch,
    required this.onContents,
    required this.onDetails,
    this.onUndo,
    this.undoLabel = 'Undo',
    this.sectionMenu,
    this.settings,
    this.userName,
    this.identityMenu,
    this.now,
    this.busy = false,
    this.error,
    this.savePending = false,
    this.hasPendingSave,
  });
  final Widget Function(bool compact)? sectionMenu;
  final Widget? settings;
  final String? userName;
  final Widget Function(Widget?)? identityMenu;
  final DateTime Function()? now;
  final FoodState state;
  final FutureOr<void> Function(FoodDetails, int) onAdd;
  final FutureOr<void> Function(List<String>) onRemove;
  final FutureOr<void> Function(FoodContainer) onRestore;
  final FutureOr<void> Function(List<FoodContainer>)? onRestoreBatch;
  final FutureOr<void> Function(FoodContainer, Contents) onContents;
  final FutureOr<void> Function(List<FoodContainer>, FoodDetails, List<String>)
  onDetails;
  final FutureOr<void> Function()? onUndo;
  final String undoLabel;
  final bool busy, savePending;
  final bool Function()? hasPendingSave;
  final String? error;
  @override
  State<FoodInventoryPage> createState() => FoodInventoryPageState();
}

class FoodInventoryPageState extends State<FoodInventoryPage> {
  FoodView view = FoodView.inventory;
  final search = TextEditingController(), reasonQuery = TextEditingController();
  Set<String> reasons = {};
  final expanded = <String>{}, selected = <String>{};
  Future<bool> Function()? _requestEditorClose;
  Completer<void>? _editorDone;
  Future<void>? get editorDone => _editorDone?.future;
  Future<bool> requestCloseEditor() async =>
      await _requestEditorClose?.call() ?? true;
  String? _actionError;
  late final FoodExpirationClock _expirationClock;
  @override
  void initState() {
    super.initState();
    _expirationClock = FoodExpirationClock(now: widget.now)
      ..addListener(_focusChanged);
    FocusManager.instance.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  bool get _textHasFocus {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus is! Element || focus.renderObject?.attached != true) return false;
    return focus.widget is EditableText ||
        focus.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Future<void> _invoke(FutureOr<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _actionError = null);
    } catch (e) {
      if (mounted) setState(() => _actionError = e.toString());
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _expirationClock.removeListener(_focusChanged);
    _expirationClock.dispose();
    search.dispose();
    reasonQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final addCommand = widget.onAdd, undoCommand = widget.onUndo;
    final pending = widget.hasPendingSave?.call() ?? widget.savePending;
    final querying = search.text.trim().isNotEmpty;
    // Inbox remains a domain partition. Stock alone composes its unsearched
    // undated partition; queried partitions would each return all active food.
    final currentView = view == FoodView.inbox ? FoodView.inventory : view;
    final inboxGroups = currentView == FoodView.inventory && !querying
        ? widget.state.view(FoodView.inbox)
        : <FoodGroup>[];
    final groups = widget.state.view(
      currentView,
      search: search.text,
      reasons: reasons,
    );
    return Theme(
      data: Theme.of(context).copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size.square(48)),
        ),
      ),
      child: Scaffold(
        // Modals own their insets. A closing keyboard without an active input
        // must not compress the page while its route becomes current again.
        resizeToAvoidBottomInset:
            (ModalRoute.isCurrentOf(context) ?? true) && _textHasFocus,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  FoodInventoryToolbar(
                    sectionMenu: widget.sectionMenu,
                    settings: widget.settings,
                    userName: widget.userName,
                    identityMenu: widget.identityMenu,
                    filter: _filterControl,
                    undoLabel: widget.undoLabel,
                    onUndo: widget.busy || widget.onUndo == null
                        ? null
                        : () => _invoke(undoCommand!),
                    onAdd: widget.busy || pending
                        ? null
                        : () => _edit(addCommand: addCommand),
                  ),
                  Expanded(
                    // Controls and guidance yield space to rows and focused
                    // inputs at large text sizes, instead of exhausting it.
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  8,
                                ),
                                child: TextField(
                                  key: const ValueKey('food-search'),
                                  controller: search,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    labelText: view == FoodView.deleted
                                        ? 'Search deleted food'
                                        : 'Search all active food',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: search.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear food search',
                                            onPressed: () =>
                                                setState(() => search.clear()),
                                            icon: const Icon(Icons.close),
                                          ),
                                  ),
                                ),
                              ),
                              if (view == FoodView.retained &&
                                  search.text.trim().isEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    8,
                                  ),
                                  child: TagInput(
                                    tags: widget.state.reasons,
                                    selected: reasons,
                                    onChanged: (value) =>
                                        setState(() => reasons = value),
                                    queryController: reasonQuery,
                                    onDropdownChanged: (_) {},
                                    queryLabel: 'Retention reasons',
                                    hint: 'Find retention reasons',
                                    clearLabel: 'Clear retention filters',
                                    chipContext: 'retention filters',
                                    expandLabel: 'Show retention reasons',
                                    collapseLabel: 'Hide retention reasons',
                                  ),
                                ),
                              if (widget.error != null || _actionError != null)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    widget.error ?? _actionError!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (inboxGroups.isNotEmpty) ...[
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Inbox',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Add an expiration date to move food out of Inbox.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            sliver: SliverList.builder(
                              itemCount: inboxGroups.length,
                              itemBuilder: (_, index) =>
                                  _group(inboxGroups[index]),
                            ),
                          ),
                          if (groups.isNotEmpty)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                                child: Text(
                                  'Stock',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                        ],
                        if (groups.isEmpty && inboxGroups.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                querying
                                    ? 'No matching food'
                                    : switch (view) {
                                        FoodView.inventory =>
                                          'No food in stock',
                                        FoodView.inbox =>
                                          'Everything has an expiration date',
                                        FoodView.retained => 'No retained food',
                                        FoodView.deleted =>
                                          'No deleted containers',
                                      },
                              ),
                            ),
                          )
                        else if (groups.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                            sliver: SliverList.builder(
                              itemCount:
                                  view == FoodView.retained &&
                                      search.text.trim().isEmpty
                                  ? groups
                                        .map((e) => e.details.retention)
                                        .toSet()
                                        .length
                                  : groups.length,
                              itemBuilder: (_, index) {
                                if (view != FoodView.retained ||
                                    search.text.trim().isNotEmpty) {
                                  return _group(groups[index]);
                                }
                                final labels =
                                    groups
                                        .map((e) => e.details.retention)
                                        .toSet()
                                        .toList()
                                      ..sort();
                                final label = labels[index];
                                final section = groups
                                    .where((e) => e.details.retention == label)
                                    .toList();
                                final count = section.fold<int>(
                                  0,
                                  (total, e) => total + e.containers.length,
                                );
                                return ExpansionTile(
                                  key: PageStorageKey('food-retention:$label'),
                                  title: Text(label),
                                  subtitle: Text(
                                    '$count ${count == 1 ? 'container' : 'containers'}',
                                  ),
                                  children: section.map(_group).toList(),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterControl(bool compact) {
    final querying = search.text.trim().isNotEmpty;
    final active =
        view == FoodView.deleted || (view == FoodView.retained && !querying);
    final count = active
        ? 1 + (view == FoodView.retained ? reasons.length : 0)
        : 0;
    final label = switch (view) {
      FoodView.deleted => 'Deleted',
      FoodView.retained => 'Retained',
      _ => 'Stock',
    };
    final icon = Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: const Icon(Icons.filter_list),
    );
    return PopupMenuButton<FoodView>(
      key: const ValueKey('food-filter'),
      tooltip: querying && view != FoodView.deleted
          ? 'Filter food: all active; saved $label filters paused'
          : 'Filter food: $label',
      enabled: !widget.busy,
      onSelected: (next) => setState(() => view = next),
      itemBuilder: (_) => [
        for (final mode in [
          FoodView.inventory,
          FoodView.retained,
          FoodView.deleted,
        ])
          PopupMenuItem(
            value: mode,
            child: Semantics(
              selected: mode == view,
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: mode == view ? const Icon(Icons.check) : null,
                  ),
                  Flexible(
                    child: Text(switch (mode) {
                      FoodView.inventory => 'Stock',
                      FoodView.retained => 'Retained',
                      FoodView.deleted => 'Deleted',
                      FoodView.inbox => 'Inbox',
                    }),
                  ),
                ],
              ),
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
          child: compact
              ? Center(child: icon)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 8),
                    const Text('Filter'),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _group(FoodGroup group) {
    final removeCommand = widget.onRemove,
        restoreCommand = widget.onRestore,
        restoreBatchCommand = widget.onRestoreBatch,
        contentsCommand = widget.onContents,
        detailsCommand = widget.onDetails;
    final details = group.details, key = details.displayGroupKey;
    final opened = expanded.contains(key), deleted = view == FoodView.deleted;
    final singleKnownFull =
        group.containers.length == 1 &&
        group.containers.single.contents.full &&
        !group.contentsConflict;
    final metadata = [
      if (details.size.isNotEmpty) details.size,
      if (details.location.isNotEmpty) details.location,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            details.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (opened || !singleKnownFull)
                            Text(
                              group.summary,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            details.expiry == null
                                ? 'Needs expiration'
                                : details.expiry!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: foodExpiryColor(
                                    details.expiry,
                                    _expirationClock.today,
                                    Theme.of(context).colorScheme,
                                  ),
                                ),
                          ),
                          if (details.brand.isNotEmpty)
                            Text(
                              details.brand,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (details.retention.isNotEmpty &&
                              (view != FoodView.retained ||
                                  search.text.trim().isNotEmpty))
                            Text(
                              details.retention,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!deleted && group.quickRemoveTarget != null)
                  IconButton(
                    tooltip: 'Remove one ${details.name} container',
                    visualDensity: VisualDensity.standard,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: widget.busy
                        ? null
                        : () => _invoke(
                            () => removeCommand([group.quickRemoveTarget!]),
                          ),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                if (deleted)
                  IconButton(
                    tooltip: 'Restore ${details.name} containers',
                    visualDensity: VisualDensity.standard,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: widget.busy
                        ? null
                        : () => _invoke(() async {
                            if (restoreBatchCommand != null) {
                              await restoreBatchCommand(group.containers);
                            } else {
                              for (final item in group.containers) {
                                await restoreCommand(item);
                              }
                            }
                          }),
                    icon: const Icon(Icons.restore),
                  ),
                IconButton(
                  tooltip:
                      '${opened ? 'Collapse' : 'Inspect'} ${details.name} containers',
                  visualDensity: VisualDensity.standard,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: () => setState(() {
                    if (!expanded.add(key)) expanded.remove(key);
                  }),
                  icon: Icon(opened ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
            if (opened) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${group.containers.length} ${group.containers.length == 1 ? 'container' : 'containers'}${metadata.isEmpty ? '' : ' · ${metadata.join(' · ')}'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (!deleted)
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: PopupMenuButton<String>(
                        tooltip: 'Actions for ${details.name}',
                        enabled: !widget.busy,
                        onSelected: (action) {
                          if (action == 'edit') {
                            _edit(group: group, detailsCommand: detailsCommand);
                          }
                          if (action == 'remove') {
                            _confirmRemove(group, removeCommand);
                          }
                        },
                        itemBuilder: (_) => [
                          if (!deleted)
                            PopupMenuItem(
                              enabled:
                                  !(widget.hasPendingSave?.call() ??
                                      widget.savePending),
                              value: 'edit',
                              child: Text('Edit group details'),
                            ),
                          if (!deleted)
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(
                                'Remove ${group.containers.length} ${group.containers.length == 1 ? 'container' : 'containers'}',
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              if (group.contentsConflict)
                const Text(
                  'Contents changed on another device. Choose contents to resolve.',
                ),
              const Divider(),
              for (final item in group.containers)
                Row(
                  children: [
                    if (!deleted)
                      Checkbox(
                        semanticLabel:
                            '${details.name} container ${item.id.substring(item.id.length - 8)}, ${item.contents.label}',
                        value: selected.contains(item.id),
                        onChanged: widget.busy
                            ? null
                            : (value) => setState(() {
                                if (value == true) {
                                  selected.add(item.id);
                                } else {
                                  selected.remove(item.id);
                                }
                              }),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Container ${item.id.substring(item.id.length - 8)} · ${item.contents.label}',
                          ),
                          if (item.contentsConflict)
                            Text(
                              'Observed alternatives: ${item.contentsEdits.values.map((e) => e.label).toSet().join(' / ')}',
                            ),
                        ],
                      ),
                    ),
                    if (!deleted)
                      IconButton(
                        tooltip:
                            'Edit ${details.name} container ${item.id.substring(item.id.length - 8)} contents',
                        onPressed: widget.busy
                            ? null
                            : () => _contents(item, contentsCommand),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (deleted)
                      IconButton(
                        tooltip:
                            'Restore ${details.name} container ${item.id.substring(item.id.length - 8)}',
                        onPressed: widget.busy
                            ? null
                            : () => _invoke(() => restoreCommand(item)),
                        icon: const Icon(Icons.restore),
                      ),
                  ],
                ),
              if (!deleted)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed:
                        widget.busy ||
                            !group.containers.any(
                              (e) => selected.contains(e.id),
                            )
                        ? null
                        : () => _invoke(() async {
                            final targets = group.containers
                                .where((e) => selected.contains(e.id))
                                .map((e) => e.id)
                                .toList();
                            await removeCommand(targets);
                            if (mounted) {
                              setState(() => selected.removeAll(targets));
                            }
                          }),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: Text(
                      'Remove selected (${group.containers.where((e) => selected.contains(e.id)).length})',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    FoodGroup group,
    FutureOr<void> Function(List<String>) remove,
  ) async {
    final targets = group.containers.map((e) => e.id).toList();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        final answer = _answerOnce<bool>(context);
        return AlertDialog(
          title: Text(
            'Remove ${targets.length} ${group.details.name} ${targets.length == 1 ? 'container' : 'containers'}?',
          ),
          content: Text(
            '${group.summary}. Only these observed containers will be removed. You can restore them from Deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => answer(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => answer(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (accepted == true && mounted) await _invoke(() => remove(targets));
  }

  Future<void> _contents(
    FoodContainer item,
    FutureOr<void> Function(FoodContainer, Contents) changeContents,
  ) async {
    final value = await showDialog<Contents>(
      context: context,
      builder: (context) {
        final answer = _answerOnce<Contents>(context);
        return SimpleDialog(
          title: const Text('Remaining contents'),
          children: [
            for (final choice in [
              const Contents.fraction(1, 1),
              const Contents.fraction(1, 2),
              const Contents.fraction(1, 3),
              const Contents.fraction(1, 4),
              const Contents.unknown(),
            ])
              SimpleDialogOption(
                onPressed: () => answer(choice),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(choice.label),
                ),
              ),
          ],
        );
      },
    );
    if (value != null && mounted) {
      await _invoke(() => changeContents(item, value));
    }
  }

  Future<void> _edit({
    FoodGroup? group,
    FutureOr<void> Function(FoodDetails, int)? addCommand,
    FutureOr<void> Function(List<FoodContainer>, FoodDetails, List<String>)?
    detailsCommand,
  }) async {
    if (_editorDone != null ||
        (widget.hasPendingSave?.call() ?? widget.savePending)) {
      return;
    }
    final done = _editorDone = Completer<void>();
    final add = addCommand ?? widget.onAdd,
        changeDetails = detailsCommand ?? widget.onDetails;
    final original = group?.details;
    final name = TextEditingController(text: original?.name ?? ''),
        brand = TextEditingController(text: original?.brand ?? ''),
        expiry = TextEditingController(text: original?.expiry ?? ''),
        size = TextEditingController(text: original?.size ?? ''),
        location = TextEditingController(text: original?.location ?? ''),
        count = TextEditingController(text: '1'),
        retentionQuery = TextEditingController();
    var retention = original?.retention ?? '';
    // Preserve each existing container's legacy value through fieldwise edits.
    // New additions make no assertion about a deprecated certainty fact.
    final estimated = original?.estimated;
    String? error;
    double? editorViewportHeight;
    var answered = false, saving = false, deciding = false;
    bool pending() => widget.hasPendingSave?.call() ?? widget.savePending;
    String snapshot() => jsonEncode([
      name.text,
      brand.text,
      expiry.text,
      size.text,
      location.text,
      count.text,
      retentionQuery.text,
      retention,
      estimated,
    ]);
    final initial = snapshot();
    void answer(BuildContext context, (FoodDetails, int)? result) {
      if (answered ||
          !context.mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      answered = true;
      Navigator.pop(context, result);
    }

    final route = DialogRoute<(FoodDetails, int)>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) {
          Future<bool> cancel() async {
            if (saving || answered || deciding) return false;
            if (snapshot() != initial) {
              deciding = true;
              bool? discard;
              try {
                discard = await showDialog<bool>(
                  context: dialogContext,
                  builder: (ctx) {
                    final decide = _answerOnce<bool>(ctx);
                    return AlertDialog(
                      scrollable: true,
                      title: Text(
                        pending()
                            ? 'Close food editor?'
                            : 'Discard food changes?',
                      ),
                      content: Text(
                        pending()
                            ? 'The earlier save still needs confirmation. You can retry it from Food.'
                            : 'Your unsaved changes will be lost.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => decide(false),
                          child: const Text('Keep editing'),
                        ),
                        FilledButton(
                          onPressed: () => decide(true),
                          child: Text(pending() ? 'Close editor' : 'Discard'),
                        ),
                      ],
                    );
                  },
                );
              } finally {
                deciding = false;
              }
              if (discard != true || !dialogContext.mounted) return false;
            }
            answer(dialogContext, null);
            return true;
          }

          _requestEditorClose = cancel;
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) unawaited(cancel());
            },
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                if (notification.depth == 0 &&
                    notification.metrics.axis == Axis.vertical &&
                    editorViewportHeight !=
                        notification.metrics.viewportDimension) {
                  editorViewportHeight = notification.metrics.viewportDimension;
                  // Dialog inset animation can resize the viewport after the
                  // input's initial keyboard-metrics caret reveal.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final focused = FocusManager.instance.primaryFocus?.context;
                    if (!answered &&
                        dialogContext.mounted &&
                        ModalRoute.of(dialogContext)?.isCurrent == true &&
                        _textHasFocus &&
                        focused != null &&
                        focused.mounted &&
                        identical(
                          ModalRoute.of(focused),
                          ModalRoute.of(dialogContext),
                        )) {
                      Scrollable.ensureVisible(
                        focused,
                        alignmentPolicy:
                            ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                      );
                    }
                  });
                }
                return false;
              },
              child: AlertDialog(
                // Title and fields share the constrained space above the actions.
                scrollable: true,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Text(
                  group == null
                      ? 'Add food'
                      : 'Edit ${group.containers.length} ${group.containers.length == 1 ? 'container' : 'containers'}',
                ),
                content: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        enabled: !saving && !pending(),
                        controller: name,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Food name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        enabled: !saving && !pending(),
                        controller: brand,
                        decoration: const InputDecoration(labelText: 'Brand'),
                      ),
                      const SizedBox(height: 12),
                      CivilDateInput(
                        enabled: !saving && !pending(),
                        controller: expiry,
                        fieldKey: const ValueKey('food-expiration'),
                        label: 'Expiration',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        enabled: !saving && !pending(),
                        controller: size,
                        decoration: const InputDecoration(
                          labelText: 'Container size',
                          hintText: 'e.g. 1 lb',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        enabled: !saving && !pending(),
                        controller: location,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                        ),
                      ),
                      if (group == null) ...[
                        const SizedBox(height: 12),
                        TextField(
                          enabled: !saving && !pending(),
                          controller: count,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Containers to add',
                            helperText:
                                'Creates a separate container for each one',
                            helperMaxLines: 2,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TagInput(
                        enabled: !saving && !pending(),
                        tags: widget.state.reasons,
                        selected: retention.isEmpty ? {} : {retention},
                        queryController: retentionQuery,
                        onDropdownChanged: (_) {},
                        allowCreate: true,
                        clearQueryOnSelection: true,
                        queryLabel: 'Retention reason',
                        hint: 'Retention reason',
                        clearLabel: 'Clear retention reason',
                        chipContext: 'retention reason',
                        expandLabel: 'Show retention reasons',
                        collapseLabel: 'Hide retention reasons',
                        onSubmitQuery: () {
                          final text = retentionQuery.text.trim();
                          if (text.isEmpty || _composing(retentionQuery)) {
                            return false;
                          }
                          if (text.length > 200) {
                            setDialog(
                              () => error =
                                  'Retention reason must be 200 characters or fewer.',
                            );
                            return false;
                          }
                          setDialog(() => retention = text);
                          retentionQuery.clear();
                          return true;
                        },
                        onChanged: (next) => setDialog(
                          () => retention =
                              next.difference({retention}).firstOrNull ?? '',
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : cancel,
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            try {
                              if ([
                                name,
                                brand,
                                expiry,
                                size,
                                location,
                                count,
                                retentionQuery,
                              ].any(_composing)) {
                                setDialog(
                                  () => error =
                                      'Finish composing text before saving.',
                                );
                                return;
                              }
                              final amount = int.tryParse(count.text);
                              if (amount == null ||
                                  amount < 1 ||
                                  amount > 100) {
                                throw const FormatException(
                                  'Add 1 to 100 containers at a time.',
                                );
                              }
                              if (expiry.text.trim().isEmpty) {
                                throw const FormatException(
                                  'Expiration is required.',
                                );
                              }
                              final details = FoodDetails(
                                name: name.text.trim(),
                                brand: brand.text.trim(),
                                expiry: expiry.text.trim(),
                                estimated: estimated,
                                retention: retentionQuery.text.trim().isEmpty
                                    ? retention
                                    : retentionQuery.text.trim(),
                                size: size.text.trim(),
                                location: location.text.trim(),
                              );
                              details.validate();
                              setDialog(() => saving = true);
                              if (group == null) {
                                await add(details, amount);
                              } else {
                                final before = original!.toJson(),
                                    after = details.toJson();
                                final fields = after.keys
                                    .where(
                                      (key) =>
                                          key != 'estimated' &&
                                          before[key] != after[key],
                                    )
                                    .toList();
                                if (fields.isNotEmpty) {
                                  await changeDetails(
                                    group.containers,
                                    details,
                                    fields,
                                  );
                                }
                              }
                              if (dialogContext.mounted) {
                                answer(dialogContext, (details, amount));
                              }
                            } catch (e) {
                              if (dialogContext.mounted) {
                                setDialog(() {
                                  saving = false;
                                  error = e is FormatException
                                      ? e.message
                                      : e.toString();
                                });
                              }
                            }
                          },
                    child: Text(
                      pending()
                          ? 'Retry save'
                          : group == null
                          ? 'Add'
                          : 'Save',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    (FoodDetails, int)? accepted;
    unawaited(
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(route).then((value) => accepted = value),
    );
    // Wait for the route's exit animation and overlay disposal before inputs.
    await route.completed;
    _requestEditorClose = null;
    _editorDone = null;
    done.complete();
    for (final controller in [
      name,
      brand,
      expiry,
      size,
      location,
      count,
      retentionQuery,
    ]) {
      controller.dispose();
    }
    if (accepted == null || !mounted) return;
    if (group == null) {
      setState(
        () => view = accepted!.$1.retention.isNotEmpty
            ? FoodView.retained
            : FoodView.inventory,
      );
    }
  }
}

void Function(T?) _answerOnce<T>(BuildContext context) {
  var answered = false;
  return (value) {
    if (answered ||
        !context.mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    answered = true;
    Navigator.pop(context, value);
  };
}

bool _composing(TextEditingController controller) =>
    controller.value.composing.isValid &&
    !controller.value.composing.isCollapsed;

/// The host owns section navigation and the app-wide account menu.
class FoodInventoryToolbar extends StatelessWidget {
  const FoodInventoryToolbar({
    super.key,
    this.sectionMenu,
    this.settings,
    this.userName,
    this.identityMenu,
    this.filter,
    this.onUndo,
    this.undoLabel = 'Undo',
    this.onAdd,
    this.showActions = true,
  });
  final Widget Function(bool compact)? sectionMenu;
  // Kept for isolated previews whose host does not provide an account menu.
  final Widget? settings;
  final String? userName;
  final Widget Function(Widget?)? identityMenu;
  final Widget Function(bool compact)? filter;
  final VoidCallback? onUndo, onAdd;
  final String undoLabel;
  final bool showActions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
    child: TaskToolbar(
      userName: userName,
      identityMenu: identityMenu ?? (_) => settings ?? const SizedBox.shrink(),
      sectionName: 'Food inventory',
      sectionIcon: Icons.kitchen_outlined,
      sectionMenu: sectionMenu,
      filter: showActions ? filter : null,
      inputModeAction: !showActions
          ? null
          : (compact) => compact
                ? IconButton(
                    tooltip: 'Add food',
                    onPressed: onAdd,
                    visualDensity: VisualDensity.standard,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(Icons.add),
                  )
                : Tooltip(
                    message: 'Add food',
                    child: OutlinedButton.icon(
                      onPressed: onAdd,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.standard,
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ),
      undo: !showActions
          ? const SizedBox.shrink()
          : IconButton(
              key: const ValueKey('undo-food-action'),
              tooltip: undoLabel,
              onPressed: onUndo,
              visualDensity: VisualDensity.standard,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.undo),
            ),
    ),
  );
}
