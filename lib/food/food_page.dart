import 'package:flutter/material.dart';

import '../presentation/tag_input.dart';
import 'inventory.dart';

/// The host owns commands/durability. The page only captures observed targets.
class FoodInventoryPage extends StatefulWidget {
  const FoodInventoryPage({
    super.key,
    required this.state,
    required this.onAdd,
    required this.onRemove,
    required this.onRestore,
    required this.onContents,
    required this.onDetails,
    this.onUndo,
    this.busy = false,
    this.error,
  });
  final FoodState state;
  final void Function(FoodDetails, int) onAdd;
  final ValueChanged<List<String>> onRemove;
  final ValueChanged<FoodContainer> onRestore;
  final void Function(FoodContainer, Contents) onContents;
  final void Function(List<FoodContainer>, FoodDetails, List<String>) onDetails;
  final VoidCallback? onUndo;
  final bool busy;
  final String? error;
  @override
  State<FoodInventoryPage> createState() => _FoodInventoryPageState();
}

class _FoodInventoryPageState extends State<FoodInventoryPage> {
  FoodView view = FoodView.inventory;
  final search = TextEditingController(), reasonQuery = TextEditingController();
  Set<String> reasons = {};
  final expanded = <String>{}, selected = <String>{};
  @override
  void dispose() {
    search.dispose();
    reasonQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.state.view(
      view,
      search: search.text,
      reasons: reasons,
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Food inventory',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Undo removal',
                        onPressed: widget.busy ? null : widget.onUndo,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: 'Add food',
                        onPressed: widget.busy ? null : () => _edit(),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final mode in FoodView.values)
                        ChoiceChip(
                          label: Text(switch (mode) {
                            FoodView.inventory => 'Stock',
                            FoodView.inbox => 'Inbox',
                            FoodView.retained => 'Retained',
                            FoodView.deleted => 'Deleted',
                          }),
                          selected: view == mode,
                          onSelected: (_) => setState(() => view = mode),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                              onPressed: () => setState(() => search.clear()),
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
                if (view == FoodView.retained && search.text.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TagInput(
                      tags: widget.state.reasons,
                      selected: reasons,
                      onChanged: (value) => setState(() => reasons = value),
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
                if (widget.error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (view == FoodView.inbox && search.text.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Needs an expiration date. A known or estimated date moves food into stock.',
                    ),
                  ),
                Expanded(
                  child: groups.isEmpty
                      ? Center(
                          child: Text(
                            search.text.isNotEmpty
                                ? 'No matching food'
                                : switch (view) {
                                    FoodView.inventory => 'No dated stock',
                                    FoodView.inbox =>
                                      'Everything has an expiration date',
                                    FoodView.retained => 'No retained food',
                                    FoodView.deleted => 'No deleted containers',
                                  },
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
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
        ),
      ),
    );
  }

  Widget _group(FoodGroup group) {
    final details = group.details, key = details.groupKey;
    final opened = expanded.contains(key), deleted = view == FoodView.deleted;
    final metadata = [
      if (details.brand.isNotEmpty) details.brand,
      if (details.size.isNotEmpty) details.size,
      if (details.location.isNotEmpty) details.location,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                      Text(
                        details.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (metadata.isNotEmpty)
                        Text(
                          metadata.join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      Text(
                        group.summary,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (group.containers.any(
                        (e) => !e.contents.full && !e.contents.unknown,
                      ))
                        Text(
                          '${group.containers.length} ${group.containers.length == 1 ? 'container' : 'containers'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      Text(
                        details.expiry == null
                            ? 'Needs expiration'
                            : '${details.estimated ? 'Estimated · ' : ''}${details.expiry}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (details.retention.isNotEmpty)
                        Text(
                          details.retention,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      if (group.contentsConflict)
                        Text(
                          'Contents changed on another device. Inspect to resolve.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!deleted && group.quickRemoveTarget != null)
                  IconButton(
                    tooltip: 'Remove one ${details.name} container',
                    onPressed: widget.busy
                        ? null
                        : () => widget.onRemove([group.quickRemoveTarget!]),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                if (deleted)
                  IconButton(
                    tooltip: 'Restore ${details.name} containers',
                    onPressed: widget.busy
                        ? null
                        : () {
                            for (final item in group.containers) {
                              widget.onRestore(item);
                            }
                          },
                    icon: const Icon(Icons.restore),
                  ),
                IconButton(
                  tooltip:
                      '${opened ? 'Collapse' : 'Inspect'} ${details.name} containers',
                  onPressed: () => setState(() {
                    if (!expanded.add(key)) expanded.remove(key);
                  }),
                  icon: Icon(opened ? Icons.expand_less : Icons.expand_more),
                ),
                if (!deleted)
                  PopupMenuButton<String>(
                    tooltip: 'Actions for ${details.name}',
                    enabled: !widget.busy,
                    onSelected: (action) {
                      if (action == 'edit') _edit(group: group);
                      if (action == 'remove') _confirmRemove(group);
                    },
                    itemBuilder: (_) => [
                      if (!deleted)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit group details'),
                        ),
                      if (!deleted)
                        PopupMenuItem(
                          value: 'remove',
                          child: Text(
                            'Remove ${group.containers.length} containers',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            if (opened) ...[
              const Divider(),
              for (final (index, item) in group.containers.indexed)
                Row(
                  children: [
                    if (!deleted)
                      Checkbox(
                        semanticLabel:
                            '${details.name} container ${index + 1}, ${item.contents.label}',
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
                            'Container ${index + 1} · ${item.contents.label}',
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
                            'Edit ${details.name} container ${index + 1} contents',
                        onPressed: widget.busy ? null : () => _contents(item),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (deleted)
                      IconButton(
                        tooltip:
                            'Restore ${details.name} container ${index + 1}',
                        onPressed: widget.busy
                            ? null
                            : () => widget.onRestore(item),
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
                        : () {
                            final targets = group.containers
                                .where((e) => selected.contains(e.id))
                                .map((e) => e.id)
                                .toList();
                            widget.onRemove(targets);
                            setState(() => selected.removeAll(targets));
                          },
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

  Future<void> _confirmRemove(FoodGroup group) async {
    final targets = group.containers.map((e) => e.id).toList();
    final remove = widget.onRemove;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        final answer = _answerOnce<bool>(context);
        return AlertDialog(
          title: Text(
            'Remove ${targets.length} ${group.details.name} containers?',
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
    if (accepted == true && mounted) remove(targets);
  }

  Future<void> _contents(FoodContainer item) async {
    final changeContents = widget.onContents;
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
    if (value != null && mounted) changeContents(item, value);
  }

  Future<void> _edit({FoodGroup? group}) async {
    final add = widget.onAdd, changeDetails = widget.onDetails;
    final original = group?.details;
    final name = TextEditingController(text: original?.name ?? ''),
        brand = TextEditingController(text: original?.brand ?? ''),
        expiry = TextEditingController(text: original?.expiry ?? ''),
        size = TextEditingController(text: original?.size ?? ''),
        location = TextEditingController(text: original?.location ?? ''),
        count = TextEditingController(text: '1'),
        retentionQuery = TextEditingController();
    var retention = original?.retention ?? '',
        estimated = original?.estimated ?? false;
    String? error;
    var answered = false;
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
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            group == null
                ? 'Add food'
                : 'Edit ${group.containers.length} containers',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Food name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: brand,
                    decoration: const InputDecoration(
                      labelText: 'Brand (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: expiry,
                    decoration: const InputDecoration(
                      labelText: 'Expiration · YYYY-MM-DD',
                      helperText: 'Leave blank for needs-expiration Inbox',
                      helperMaxLines: 2,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Estimated expiration'),
                    value: estimated,
                    onChanged: (v) => setDialog(() => estimated = v!),
                  ),
                  TextField(
                    controller: size,
                    decoration: const InputDecoration(
                      labelText: 'Container size (optional)',
                      hintText: 'e.g. 1 lb',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(
                      labelText: 'Location (optional)',
                    ),
                  ),
                  if (group == null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: count,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Containers to add',
                        helperText: 'Creates a separate container for each one',
                        helperMaxLines: 2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TagInput(
                    tags: widget.state.reasons,
                    selected: retention.isEmpty ? {} : {retention},
                    queryController: retentionQuery,
                    onDropdownChanged: (_) {},
                    allowCreate: true,
                    clearQueryOnSelection: true,
                    queryLabel: 'Retention reason (optional)',
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
          ),
          actions: [
            TextButton(
              onPressed: () => answer(dialogContext, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
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
                      () => error = 'Finish composing text before saving.',
                    );
                    return;
                  }
                  final amount = int.tryParse(count.text);
                  if (amount == null || amount < 1 || amount > 100) {
                    throw const FormatException(
                      'Add 1 to 100 containers at a time.',
                    );
                  }
                  final details = FoodDetails(
                    name: name.text.trim(),
                    brand: brand.text.trim(),
                    expiry: expiry.text.trim().isEmpty
                        ? null
                        : expiry.text.trim(),
                    estimated: estimated,
                    retention: retentionQuery.text.trim().isEmpty
                        ? retention
                        : retentionQuery.text.trim(),
                    size: size.text.trim(),
                    location: location.text.trim(),
                  );
                  details.validate();
                  answer(dialogContext, (details, amount));
                } on FormatException catch (e) {
                  setDialog(() => error = e.message);
                }
              },
              child: Text(group == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
    final accepted = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    // Wait for the route's exit animation and overlay disposal before inputs.
    await route.completed;
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
      add(accepted.$1, accepted.$2);
      setState(
        () => view = accepted.$1.expiry == null
            ? FoodView.inbox
            : accepted.$1.retention.isNotEmpty
            ? FoodView.retained
            : FoodView.inventory,
      );
    } else {
      final before = original!.toJson(), after = accepted.$1.toJson();
      final fields = after.keys
          .where((key) => before[key] != after[key])
          .toList();
      if (fields.isNotEmpty) {
        changeDetails(group.containers, accepted.$1, fields);
      }
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
