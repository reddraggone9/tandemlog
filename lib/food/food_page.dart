import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../presentation/tag_input.dart';
import '../presentation/sticky_task_group.dart';
import '../presentation/task_toolbar.dart';
import '../presentation/section_content.dart';
import '../presentation/list_row_surface.dart';
import '../presentation/list_selection.dart';
import '../presentation/task_entry_area.dart';
import '../presentation/toolbar_action.dart';
import '../presentation/editor_surface.dart';
import 'food_editor.dart';
import 'expiration_presentation.dart';
import 'inventory.dart';

/// The host owns commands/durability. The page only captures observed targets.
class FoodInventoryPage extends StatefulWidget {
  const FoodInventoryPage({
    super.key,
    required this.state,
    this.workspaceIdentity,
    required this.onAdd,
    required this.onRemove,
    required this.onRestore,
    this.onRestoreBatch,
    required this.onDetails,
    this.onUndo,
    this.undoLabel = 'Undo',
    this.sectionMenu,
    this.settings,
    this.progress,
    this.userName,
    this.identityMenu,
    this.now,
    this.busy = false,
    this.error,
    this.savePending = false,
    this.hasPendingSave,
    this.onCloseReadinessChanged,
  });
  final Widget Function(bool compact)? sectionMenu;
  final Widget? settings, progress;
  final String? userName;
  final Widget Function(Widget?)? identityMenu;
  final DateTime Function()? now;
  final FoodState state;
  final Object? workspaceIdentity;
  final FutureOr<void> Function(FoodDetails, int) onAdd;
  final FutureOr<void> Function(List<String>) onRemove;
  final FutureOr<void> Function(FoodContainer) onRestore;
  final FutureOr<void> Function(List<FoodContainer>)? onRestoreBatch;
  final FutureOr<void> Function(List<FoodContainer>, FoodDetails, List<String>)
  onDetails;
  final FutureOr<void> Function()? onUndo;
  final String undoLabel;
  final bool busy, savePending;
  final bool Function()? hasPendingSave;
  final String? error;
  final VoidCallback? onCloseReadinessChanged;
  @override
  State<FoodInventoryPage> createState() => FoodInventoryPageState();
}

/// One grouping result per immutable Food projection and local filter tuple.
/// Clock/focus/busy rebuilds reuse the partition; row date paint stays live.
class _FoodGrouping {
  _FoodGrouping({
    required this.state,
    required this.workspace,
    required this.view,
    required this.query,
    required Set<String> reasons,
    required Set<String> brands,
    required Set<String> locations,
  }) : reasons = Set.unmodifiable(reasons),
       brands = Set.unmodifiable(brands),
       locations = Set.unmodifiable(locations) {
    final querying = query.trim().isNotEmpty;
    matches = List.unmodifiable(
      state.view(
        view == FoodView.inbox ? FoodView.inventory : view,
        search: query,
        reasons: reasons,
        brands: brands,
        locations: locations,
      ),
    );
    inbox = List.unmodifiable(
      (view == FoodView.inventory || view == FoodView.inbox) && !querying
          ? state.view(FoodView.inbox, brands: brands, locations: locations)
          : <FoodGroup>[],
    );
    groups = querying
        ? List.unmodifiable(matches.where((g) => !g.containers.first.deleted))
        : matches;
    deletedGroups = querying
        ? List.unmodifiable(matches.where((g) => g.containers.first.deleted))
        : const [];
    rows = List.unmodifiable([...inbox, ...groups, ...deletedGroups]);
    shown = List.unmodifiable([for (final g in rows) ...g.containers]);
    visibleIds = Set.unmodifiable(shown.map((item) => item.id));
  }

  final FoodState state;
  final Object? workspace;
  final FoodView view;
  final String query;
  final Set<String> reasons, brands, locations;
  late final List<FoodGroup> matches, inbox, groups, deletedGroups;

  /// Visible rows in display order, including Deleted rows; selection ranges
  /// and selectable IDs follow exactly what is shown.
  late final List<FoodGroup> rows;
  late final List<FoodContainer> shown;
  late final Set<String> visibleIds;

  bool accepts(
    FoodState nextState,
    Object? nextWorkspace,
    FoodView nextView,
    String nextQuery,
    Set<String> nextReasons,
    Set<String> nextBrands,
    Set<String> nextLocations,
  ) =>
      identical(state, nextState) &&
      workspace == nextWorkspace &&
      view == nextView &&
      query == nextQuery &&
      setEquals(reasons, nextReasons) &&
      setEquals(brands, nextBrands) &&
      setEquals(locations, nextLocations);
}

class FoodInventoryPageState extends State<FoodInventoryPage> {
  FoodView view = FoodView.inventory;
  final search = TextEditingController();
  Set<String> reasons = {}, brands = {}, locations = {};
  final bulkSelected = <String>{};
  bool selecting = false;
  String? _selectionAnchor;
  // The group open in a single-group editor; explicit selection starts with it.
  FoodGroup? _editingGroup;
  Object? _focusedGroup;

  void _clearBulkSelection() {
    selecting = false;
    bulkSelected.clear();
    _selectionAnchor = null;
  }

  static String _rowKey(FoodGroup group) =>
      '${group.containers.first.deleted ? 'deleted' : 'active'}:'
      '${group.details.displayGroupKey}';

  /// Applies the shared Tasks/Food selection rules to the visible rows.
  /// Starting explicit selection while the wide pane edits one group selects
  /// that group too, as on Tasks, after the usual unsaved-draft decision.
  Future<void> _select(
    FoodGroup group,
    SelectionGesture gesture,
    Object? workspace,
  ) async {
    bool usable() =>
        !(widget.hasPendingSave?.call() ?? widget.savePending) &&
        _canUseGroupMenu(group, workspace);
    if (!usable()) return;
    final rows = {for (final row in _grouping.rows) _rowKey(row): row};
    var selected = Set<String>.of(bulkSelected);
    var anchor = _selectionAnchor;
    final editing = _editingGroup == null
        ? null
        : rows[_rowKey(_editingGroup!)];
    if (!selecting && editing != null) {
      selected = editing.containers.map((e) => e.id).toSet();
      anchor = _rowKey(editing);
    }
    final result = nextListSelection<String>(
      selected: selected,
      selecting: selecting,
      anchor: anchor,
      target: _rowKey(group),
      order: rows.keys.toList(),
      members: (key) => rows[key]?.containers.map((e) => e.id) ?? const [],
      gesture: gesture,
    );
    if (result.selecting && _editorBuilder != null && !_editorModal) {
      if (!await requestCloseEditor()) return;
      await editorDone;
      if (!mounted || !usable()) return;
    }
    setState(() {
      bulkSelected
        ..clear()
        ..addAll(
          result.selecting
              ? result.selected.intersection(_grouping.visibleIds)
              : const <String>{},
        );
      selecting = bulkSelected.isNotEmpty;
      _selectionAnchor = selecting ? result.anchor : null;
    });
  }

  @override
  void didUpdateWidget(covariant FoodInventoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceIdentity != widget.workspaceIdentity) {
      _clearBulkSelection();
      _focusedGroup = null;
    }
  }

  _FoodGrouping? _groupingMemo;
  _FoodGrouping get _grouping {
    final memo = _groupingMemo;
    if (memo != null &&
        memo.accepts(
          widget.state,
          widget.workspaceIdentity,
          view,
          search.text,
          reasons,
          brands,
          locations,
        )) {
      return memo;
    }
    return _groupingMemo = _FoodGrouping(
      state: widget.state,
      workspace: widget.workspaceIdentity,
      view: view,
      query: search.text,
      reasons: reasons,
      brands: brands,
      locations: locations,
    );
  }

  List<FoodGroup> _matches() => _grouping.matches;
  List<FoodGroup> _inbox() => _grouping.inbox;
  List<FoodContainer> _shown() => _grouping.shown;
  Widget Function(bool panel)? _editorBuilder;
  bool _editorModal = false;
  int _editorRequest = 0;
  final _inventoryKey = GlobalKey();
  bool Function()? _editorCloseBusy;
  bool get closeBusy =>
      _editorDone != null && (_editorCloseBusy?.call() ?? true);
  Future<bool> Function()? _requestEditorClose;
  Completer<void>? _editorDone;
  Future<void>? get editorDone => _editorDone?.future;
  Future<bool> requestCloseEditor() async =>
      await _requestEditorClose?.call() ?? true;
  String? _actionError;
  late final FoodExpirationClock _expirationClock;
  late bool _lastTextFocus;
  @override
  void initState() {
    super.initState();
    _lastTextFocus = _textHasFocus;
    _expirationClock = FoodExpirationClock(now: widget.now)
      ..addListener(_expirationChanged);
    FocusManager.instance.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!mounted) return;
    final textHasFocus = _textHasFocus;
    if (textHasFocus == _lastTextFocus) return;
    setState(() => _lastTextFocus = textHasFocus);
  }

  void _expirationChanged() {
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
    _expirationClock.removeListener(_expirationChanged);
    _expirationClock.dispose();
    search.dispose();
    // An editor requested just before page disposal may never mount, so no
    // child dispose callback exists to release the host's readiness wait.
    final done = _editorDone;
    if (done != null && !done.isCompleted) done.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textHasFocus = _textHasFocus;
    _lastTextFocus = textHasFocus;
    final addCommand = widget.onAdd, undoCommand = widget.onUndo;
    final pending = widget.hasPendingSave?.call() ?? widget.savePending;
    final querying = search.text.trim().isNotEmpty;
    // Inbox remains a domain partition. Stock alone composes its unsearched
    // undated partition; search includes both active and deleted food.
    final grouping = _grouping;
    final inboxGroups = grouping.inbox;
    final visibleIds = grouping.visibleIds;
    bulkSelected.retainAll(visibleIds);
    final groups = grouping.groups;
    final deletedGroups = grouping.deletedGroups;
    return Theme(
      data: Theme.of(context).copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size.square(48)),
        ),
      ),
      child: Scaffold(
        // Embedded editors reserve keyboard space even when pointer actions
        // end field focus. Auxiliary routes still reserve their own insets.
        resizeToAvoidBottomInset:
            (ModalRoute.isCurrentOf(context) ?? true) &&
            (_editorBuilder != null || textHasFocus),
        body: Actions(
          actions: {
            if (_editorBuilder != null)
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  unawaited(requestCloseEditor());
                  return null;
                },
              ),
          },
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: sectionContentConstraints,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final panel =
                        constraints.maxWidth >= EditorSurface.breakpoint &&
                        !_editorModal;
                    final editor = _editorBuilder?.call(panel);
                    final body = Column(
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
                        ?widget.progress,
                        Expanded(
                          // Controls and guidance yield space to rows and focused
                          // inputs at large text sizes, instead of exhausting it.
                          child: EditorSurface(
                            panel: true,
                            editor: panel ? editor : null,
                            list: LayoutBuilder(
                              builder: (context, listConstraints) {
                                final rowInset = listConstraints.maxWidth < 600
                                    ? 0.0
                                    : 16.0;
                                return CustomScrollView(
                                  key: _inventoryKey,
                                  slivers: [
                                    SliverToBoxAdapter(
                                      child: Column(
                                        children: [
                                          TaskEntryArea(
                                            selecting: selecting,
                                            captureVisible: true,
                                            selectionCount: bulkSelected.length,
                                            maximumSelectionCount:
                                                visibleIds.length,
                                            onClear: () =>
                                                setState(_clearBulkSelection),
                                            onEdit:
                                                widget.busy ||
                                                    pending ||
                                                    bulkSelected.isEmpty
                                                ? null
                                                : () => _edit(
                                                    bulkTargets: [
                                                      for (final item
                                                          in _shown())
                                                        if (bulkSelected
                                                            .contains(item.id))
                                                          item,
                                                    ],
                                                  ),
                                            capture: TextField(
                                              key: const ValueKey(
                                                'food-search',
                                              ),
                                              controller: search,
                                              onChanged: (_) =>
                                                  setState(_clearBulkSelection),
                                              decoration: InputDecoration(
                                                labelText: 'Search food',
                                                prefixIcon: const Icon(
                                                  Icons.search,
                                                ),
                                                suffixIcon: search.text.isEmpty
                                                    ? null
                                                    : IconButton(
                                                        tooltip:
                                                            'Clear food search',
                                                        onPressed: () =>
                                                            setState(() {
                                                              search.clear();
                                                              _clearBulkSelection();
                                                            }),
                                                        icon: const Icon(
                                                          Icons.close,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                          if (widget.error != null ||
                                              _actionError != null)
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
                                          padding: EdgeInsets.fromLTRB(
                                            16,
                                            4,
                                            16,
                                            8,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                        padding: EdgeInsets.symmetric(
                                          horizontal: rowInset,
                                        ),
                                        sliver: SliverList.builder(
                                          itemCount: inboxGroups.length,
                                          itemBuilder: (_, index) =>
                                              _group(inboxGroups[index]),
                                        ),
                                      ),
                                      if (groups.isNotEmpty)
                                        const SliverToBoxAdapter(
                                          child: Padding(
                                            padding: EdgeInsets.fromLTRB(
                                              16,
                                              12,
                                              16,
                                              8,
                                            ),
                                            child: Text(
                                              'Stock',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                    if (groups.isEmpty &&
                                        inboxGroups.isEmpty &&
                                        deletedGroups.isEmpty)
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
                                                    FoodView.retained =>
                                                      'No retained food',
                                                    FoodView.deleted =>
                                                      'No deleted containers',
                                                  },
                                          ),
                                        ),
                                      )
                                    else if (groups.isNotEmpty)
                                      SliverPadding(
                                        padding: EdgeInsets.fromLTRB(
                                          rowInset,
                                          0,
                                          rowInset,
                                          16,
                                        ),
                                        sliver: SliverList.builder(
                                          itemCount: groups.length,
                                          itemBuilder: (_, index) =>
                                              _group(groups[index]),
                                        ),
                                      ),
                                    if (deletedGroups.isNotEmpty)
                                      SliverPadding(
                                        padding: EdgeInsets.fromLTRB(
                                          rowInset,
                                          0,
                                          rowInset,
                                          16,
                                        ),
                                        sliver: SliverMainAxisGroup(
                                          slivers: [
                                            SliverPadding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: rowInset == 0
                                                    ? 16
                                                    : 0,
                                              ),
                                              sliver:
                                                  const StickyTaskGroupHeading(
                                                    title: 'Deleted',
                                                    headingKey: ValueKey(
                                                      'food-deleted-heading',
                                                    ),
                                                  ),
                                            ),
                                            SliverList.builder(
                                              itemCount: deletedGroups.length,
                                              itemBuilder: (_, index) =>
                                                  _group(deletedGroups[index]),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                    return panel || editor == null
                        ? body
                        : EditorSurface(
                            panel: false,
                            list: body,
                            editor: editor,
                          );
                  },
                ),
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
        !querying &&
        (view == FoodView.deleted ||
            view == FoodView.retained ||
            brands.isNotEmpty ||
            locations.isNotEmpty);
    final label = switch (view) {
      FoodView.deleted => 'Deleted',
      FoodView.retained => 'Retained',
      _ => 'Stock',
    };
    final icon = toolbarFilterIcon(active: active);
    return toolbarMenuAction<FoodView>(
      context: context,
      compact: compact,
      label: 'Filter',
      icon: icon,
      key: const ValueKey('food-filter'),
      tooltip: querying
          ? 'Filter food: all food; saved $label filters paused'
          : 'Filter food: $label${active ? ' · active filters' : ''}',
      enabled: !widget.busy,
      onSelected: (next) => setState(() {
        view = next;
        _clearBulkSelection();
      }),
      itemBuilder: (_) {
        final observed = _shown().map((e) => e.id).toSet();
        return [
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
          const PopupMenuDivider(),
          PopupMenuItem<FoodView>(
            onTap: _fieldFilters,
            child: const Text('More filters…'),
          ),
          PopupMenuItem<FoodView>(
            enabled:
                observed.isNotEmpty &&
                !(widget.hasPendingSave?.call() ?? widget.savePending),
            onTap: () => setState(() {
              selecting = true;
              _selectionAnchor = null;
              bulkSelected
                ..clear()
                ..addAll(
                  observed.intersection(_shown().map((e) => e.id).toSet()),
                );
            }),
            child: const Text('Select matching containers'),
          ),
        ];
      },
    );
  }

  Future<void> _fieldFilters() async {
    var selectedBrands = Set<String>.of(brands);
    var selectedLocations = Set<String>.of(locations);
    var selectedReasons = Set<String>.of(reasons);
    final retained = view == FoodView.retained;
    final brandValues = widget.state.brands,
        locationValues = widget.state.locations;
    final brandQuery = TextEditingController(),
        locationQuery = TextEditingController(),
        reasonQuery = TextEditingController();
    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) {
        final answer = _answerOnce<void>(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            scrollable: true,
            title: const Text('More filters…'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TagInput(
                    tags: brandValues,
                    selected: selectedBrands,
                    queryController: brandQuery,
                    queryKey: const ValueKey('food-brand-filter-query'),
                    queryLabel: 'Brands',
                    hint: 'Find brands',
                    valuePrefix: '',
                    emptyLabel: 'No brands yet',
                    noMatchesLabel: 'No matching brands',
                    clearLabel: 'Clear brand filters',
                    chipContext: 'brand filters',
                    expandLabel: 'Show brands',
                    collapseLabel: 'Hide brands',
                    onDropdownChanged: (_) {},
                    onChanged: (next) => setDialog(() => selectedBrands = next),
                  ),
                  const SizedBox(height: 16),
                  TagInput(
                    tags: locationValues,
                    selected: selectedLocations,
                    queryController: locationQuery,
                    queryKey: const ValueKey('food-location-filter-query'),
                    queryLabel: 'Locations',
                    hint: 'Find locations',
                    valuePrefix: '',
                    emptyLabel: 'No locations yet',
                    noMatchesLabel: 'No matching locations',
                    clearLabel: 'Clear location filters',
                    chipContext: 'location filters',
                    expandLabel: 'Show locations',
                    collapseLabel: 'Hide locations',
                    onDropdownChanged: (_) {},
                    onChanged: (next) =>
                        setDialog(() => selectedLocations = next),
                  ),
                  if (retained) ...[
                    const SizedBox(height: 16),
                    TagInput(
                      tags: widget.state.reasons,
                      selected: selectedReasons,
                      queryController: reasonQuery,
                      queryKey: const ValueKey('food-reason-filter-query'),
                      label: 'Retention reason',
                      queryLabel: 'Retention reason',
                      hint: selectedReasons.isEmpty
                          ? 'All reasons'
                          : 'Find reasons',
                      valuePrefix: '',
                      emptyLabel: 'No reasons yet',
                      noMatchesLabel: 'No matching reasons',
                      clearLabel: 'Clear retention filters',
                      chipContext: 'retention filters',
                      expandLabel: 'Show retention reasons',
                      collapseLabel: 'Hide retention reasons',
                      onDropdownChanged: (_) {},
                      onChanged: (next) =>
                          setDialog(() => selectedReasons = next),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => answer(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!mounted ||
                      !dialogContext.mounted ||
                      ModalRoute.of(dialogContext)?.isCurrent != true) {
                    return;
                  }
                  setState(() {
                    brands = selectedBrands;
                    locations = selectedLocations;
                    if (retained && view == FoodView.retained) {
                      reasons = selectedReasons;
                    }
                    _clearBulkSelection();
                  });
                  answer(null);
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        );
      },
    );
    try {
      unawaited(Navigator.of(context).push(route));
      await route.completed;
    } finally {
      brandQuery.dispose();
      locationQuery.dispose();
      reasonQuery.dispose();
    }
  }

  String _groupMenuIdentity(FoodGroup group) => jsonEncode([
    group.containers.first.deleted,
    group.details.displayGroupKey,
    for (final item in group.containers)
      [item.id, item.deletions.toList()..sort()],
  ]);

  bool _canUseGroupMenu(FoodGroup observed, Object? workspace) =>
      mounted &&
      !widget.busy &&
      widget.workspaceIdentity == workspace &&
      [..._inbox(), ..._matches()].any(
        (current) =>
            _groupMenuIdentity(current) == _groupMenuIdentity(observed),
      );

  bool _groupSelected(FoodGroup group) =>
      selecting && group.containers.every((e) => bulkSelected.contains(e.id));

  List<PopupMenuEntry<String>> _groupMenuItems(FoodGroup group) => [
    PopupMenuItem<String>(
      enabled: !(widget.hasPendingSave?.call() ?? widget.savePending),
      value: 'add-another',
      child: const Text('Add another…'),
    ),
    // Keyboard and assistive-technology route to the long-press selection.
    PopupMenuItem<String>(
      enabled: !(widget.hasPendingSave?.call() ?? widget.savePending),
      value: 'select',
      child: Text(_groupSelected(group) ? 'Deselect' : 'Select'),
    ),
    if (group.containers.first.deleted) ...[
      PopupMenuItem<String>(
        value: 'restore',
        child: Text(
          'Restore ${group.containers.length} ${group.containers.length == 1 ? 'container' : 'containers'}',
        ),
      ),
    ] else
      PopupMenuItem<String>(
        value: 'remove',
        child: Text(
          'Remove ${group.containers.length} ${group.containers.length == 1 ? 'container' : 'containers'}',
        ),
      ),
  ];

  Future<void> _showGroupMenu(
    FoodGroup group,
    Offset position,
    void Function(String) selectAction,
  ) async {
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) return;
    final point = overlay.globalToLocal(position);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(point.dx, point.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      requestFocus: true,
      items: _groupMenuItems(group),
    );
    if (action != null) selectAction(action);
  }

  Widget _group(FoodGroup group) {
    final removeCommand = widget.onRemove,
        restoreCommand = widget.onRestore,
        restoreBatchCommand = widget.onRestoreBatch,
        detailsCommand = widget.onDetails;
    final details = group.details, deleted = group.containers.first.deleted;
    final key = '${deleted ? 'deleted' : 'active'}:${details.displayGroupKey}';
    final identity = _groupMenuIdentity(group);
    final countLabel =
        '${group.containers.length} ${group.containers.length == 1 ? 'container' : 'containers'}';
    final metadata = [
      if (details.size.isNotEmpty) details.size,
      if (details.location.isNotEmpty) details.location,
    ];
    final workspace = widget.workspaceIdentity;
    final addCommand = widget.onAdd;
    final pending = widget.hasPendingSave?.call() ?? widget.savePending;
    void select(SelectionGesture gesture) =>
        unawaited(_select(group, gesture, workspace));

    void editGroup() {
      if (pending || !_canUseGroupMenu(group, workspace)) return;
      final gesture = pointerSelectionGesture();
      if (gesture != SelectionGesture.plain || selecting) {
        select(gesture);
      } else {
        _edit(group: group, detailsCommand: detailsCommand);
      }
    }

    void restoreGroup() {
      if (!_canUseGroupMenu(group, workspace)) return;
      _invoke(() async {
        if (restoreBatchCommand != null) {
          await restoreBatchCommand(group.containers);
        } else {
          for (final item in group.containers) {
            await restoreCommand(item);
          }
        }
      });
    }

    void selectAction(String action) {
      if (!_canUseGroupMenu(group, workspace)) return;
      if (action == 'add-another' &&
          !(widget.hasPendingSave?.call() ?? widget.savePending)) {
        _edit(template: group.details, addCommand: addCommand);
      }
      if (action == 'select') select(SelectionGesture.longPress);
      if (action == 'remove') _confirmRemove(group, removeCommand);
      if (action == 'restore') restoreGroup();
    }

    final editable = !widget.busy && !pending;
    return GestureDetector(
      // Replacing gesture state also binds pointer-down to the observed IDs and
      // deletion tokens. A peer arrival must not retarget pointer-up actions.
      key: ValueKey((workspace, identity)),
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: widget.busy
          ? null
          : (details) =>
                _showGroupMenu(group, details.globalPosition, selectAction),
      child: ListRowSurface(
        key: ValueKey('food-group:$key'),
        color: _groupSelected(group)
            ? Theme.of(context).colorScheme.primaryContainer
            : deleted
            ? Theme.of(context).colorScheme.surfaceContainerLow
            : null,
        focused: _focusedGroup == (workspace, identity),
        interactive: editable,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          // Space on the focused row selects, as on Task rows; Enter still
          // edits. Only the row's own InkWell focus node is a direct child;
          // its checkbox and buttons keep their own Space activation.
          onKeyEvent: (node, event) {
            if (event.logicalKey != LogicalKeyboardKey.space ||
                event is KeyUpEvent ||
                FocusManager.instance.primaryFocus?.parent != node) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent && editable) {
              select(SelectionGesture.longPress);
            }
            return KeyEventResult.handled;
          },
          child: InkWell(
            overlayColor: listRowInkOverlay(Theme.of(context).colorScheme),
            splashFactory: InkRipple.splashFactory,
            onFocusChange: (focused) {
              if (!mounted) return;
              setState(() {
                if (focused) {
                  _focusedGroup = (workspace, identity);
                } else if (_focusedGroup == (workspace, identity)) {
                  _focusedGroup = null;
                }
              });
            },
            onTap: editable ? editGroup : null,
            onLongPress: editable
                ? () => select(SelectionGesture.longPress)
                : null,
            excludeFromSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selecting)
                    Checkbox(
                      key: ValueKey('food-group-selection:$key'),
                      semanticLabel:
                          'Select ${group.containers.length} ${details.name} containers',
                      tristate: true,
                      value:
                          group.containers.every(
                            (e) => bulkSelected.contains(e.id),
                          )
                          ? true
                          : group.containers.any(
                              (e) => bulkSelected.contains(e.id),
                            )
                          ? null
                          : false,
                      onChanged: widget.busy
                          ? null
                          : (_) => select(SelectionGesture.toggle),
                    ),
                  Expanded(
                    child: Semantics(
                      button: true,
                      enabled: editable,
                      label: [
                        selecting ? 'Select' : 'Edit',
                        details.name,
                        countLabel,
                        details.expiry ?? 'Needs expiration',
                        if (details.brand.isNotEmpty) details.brand,
                        if (details.retention.isNotEmpty) details.retention,
                        ...metadata,
                      ].join(', '),
                      selected: _groupSelected(group),
                      onTap: editable ? editGroup : null,
                      onLongPress: editable
                          ? () => select(SelectionGesture.longPress)
                          : null,
                      customSemanticsActions: editable
                          ? {
                              CustomSemanticsAction(
                                label: _groupSelected(group)
                                    ? 'Deselect food'
                                    : 'Select food',
                              ): () =>
                                  select(SelectionGesture.longPress),
                            }
                          : null,
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                details.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: deleted
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant
                                          : null,
                                      decoration: deleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                              ),
                              if (group.containers.length > 1)
                                Text(
                                  countLabel,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                details.expiry ?? 'Needs expiration',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: deleted
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant
                                          : foodExpiryColor(
                                              details.expiry,
                                              _expirationClock.today,
                                              Theme.of(context).colorScheme,
                                            ),
                                    ),
                              ),
                              for (final value in [
                                details.brand,
                                details.retention,
                              ].where((value) => value.isNotEmpty))
                                Text(
                                  value,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                          if (metadata.isNotEmpty)
                            Text(
                              metadata.join(' · '),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!deleted)
                    IconButton(
                      tooltip: 'Remove one ${details.name} container',
                      visualDensity: VisualDensity.standard,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: widget.busy
                          ? null
                          : () {
                              if (_canUseGroupMenu(group, workspace)) {
                                _invoke(
                                  () => removeCommand([
                                    group.containers.first.id,
                                  ]),
                                );
                              }
                            },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  if (deleted)
                    IconButton(
                      tooltip: 'Restore one ${details.name} container',
                      visualDensity: VisualDensity.standard,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: widget.busy
                          ? null
                          : () {
                              if (_canUseGroupMenu(group, workspace)) {
                                _invoke(
                                  () => restoreCommand(group.containers.first),
                                );
                              }
                            },
                      icon: const Icon(Icons.restore),
                    ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: PopupMenuButton<String>(
                      key: ValueKey('food-actions:$identity'),
                      tooltip: 'Actions for ${details.name}',
                      enabled: !widget.busy,
                      onSelected: selectAction,
                      itemBuilder: (_) => _groupMenuItems(group),
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

  Future<void> _confirmRemove(
    FoodGroup group,
    FutureOr<void> Function(List<String>) remove,
  ) async {
    final targets = group.containers.map((e) => e.id).toList();
    final workspace = widget.workspaceIdentity;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        final answer = _answerOnce<bool>(context);
        return AlertDialog(
          title: Text(
            'Remove ${targets.length} ${group.details.name} ${targets.length == 1 ? 'container' : 'containers'}?',
          ),
          content: Text('You can restore these containers from Deleted.'),
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
    if (accepted == true && _canUseGroupMenu(group, workspace)) {
      await _invoke(() => remove(targets));
    }
  }

  Future<void> _edit({
    FoodGroup? group,
    FoodDetails? template,
    List<FoodContainer>? bulkTargets,
    FutureOr<void> Function(FoodDetails, int)? addCommand,
    FutureOr<void> Function(List<FoodContainer>, FoodDetails, List<String>)?
    detailsCommand,
  }) async {
    final request = ++_editorRequest;
    final workspace = widget.workspaceIdentity;
    final add = addCommand ?? widget.onAdd;
    final changeDetails = detailsCommand ?? widget.onDetails;
    final targets = bulkTargets == null
        ? null
        : List<FoodContainer>.unmodifiable(bulkTargets);
    if (_editorDone != null) {
      if (!await requestCloseEditor()) return;
      await editorDone;
    }
    if (!mounted ||
        request != _editorRequest ||
        workspace != widget.workspaceIdentity ||
        (widget.hasPendingSave?.call() ?? widget.savePending) ||
        (group != null && !_canUseGroupMenu(group, workspace)) ||
        (targets != null &&
            targets.any((e) => !_shown().any((item) => item.id == e.id)))) {
      return;
    }
    final removeCommand = widget.onRemove,
        restoreCommand = widget.onRestore,
        restoreBatchCommand = widget.onRestoreBatch;
    final key = GlobalKey<FoodEditorState>();
    final done = _editorDone = Completer<void>();
    final previousFocus = FocusManager.instance.primaryFocus;
    (FoodDetails, int)? accepted;
    _editorCloseBusy = () => key.currentState?.closeBusy ?? true;
    _requestEditorClose = () async =>
        await key.currentState?.requestClose() ?? false;
    _editingGroup = group;
    setState(
      () => _editorBuilder = (panel) => FoodEditor(
        key: key,
        panel: panel && targets == null,
        group: group,
        template: template,
        targets: targets,
        state: widget.state,
        onAdd: add,
        onDetails: changeDetails,
        pending: () => widget.hasPendingSave?.call() ?? widget.savePending,
        isOriginCurrent: () =>
            mounted &&
            workspace == widget.workspaceIdentity &&
            (group == null ||
                (widget.hasPendingSave?.call() ?? widget.savePending) ||
                group.containers.every(
                  (e) => widget.state.containers.any(
                    (item) =>
                        item.id == e.id &&
                        item.deleted == e.deleted &&
                        item.deletions.length == e.deletions.length &&
                        item.deletions.containsAll(e.deletions),
                  ),
                )),
        areTargetsVisible: () =>
            targets == null ||
            targets.every((e) => _shown().any((item) => item.id == e.id)),
        onBulkApplied: () {
          if (mounted) setState(_clearBulkSelection);
        },
        onRemoveTargets: targets == null
            ? null
            : (items) => removeCommand(items.map((e) => e.id).toList()),
        onRestoreTargets: targets == null
            ? null
            : (items) async {
                if (restoreBatchCommand != null) {
                  await restoreBatchCommand(items);
                } else {
                  for (final item in items) {
                    await restoreCommand(item);
                  }
                }
              },
        onClosed: (result) {
          if (!mounted || !identical(_editorDone, done)) return;
          accepted = result;
          setState(() {
            _editorBuilder = null;
            _editingGroup = null;
          });
        },
        onDisposed: () {
          if (!done.isCompleted) done.complete();
        },
        onReadinessChanged: () {
          if (mounted) widget.onCloseReadinessChanged?.call();
        },
      ),
    );
    _editorModal = targets != null;
    // Completion follows actual input disposal, including whole-page disposal.
    await done.future;
    if (identical(_editorDone, done)) {
      _editingGroup = null;
      _requestEditorClose = null;
      _editorCloseBusy = null;
      _editorDone = null;
    }
    if (!mounted) return;
    if (accepted != null && targets == null && group == null) {
      setState(
        () => view = accepted!.$1.retention.isNotEmpty
            ? FoodView.retained
            : FoodView.inventory,
      );
    }
    if (previousFocus?.context?.mounted ?? false) previousFocus!.requestFocus();
    widget.onCloseReadinessChanged?.call();
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
  Widget build(BuildContext context) => TaskToolbar(
    userName: userName,
    identityMenu: identityMenu ?? (_) => settings ?? const SizedBox.shrink(),
    sectionName: sectionMenu == null ? 'Food inventory' : 'Food',
    sectionIcon: Icons.kitchen_outlined,
    sectionMenu: sectionMenu,
    filter: showActions ? filter : null,
    inputModeAction: !showActions
        ? null
        : (compact) => toolbarAction(
            compact: compact,
            tooltip: 'Add food',
            icon: const Icon(Icons.add),
            label: 'Add',
            onPressed: onAdd,
          ),
    undo: const SizedBox.shrink(),
    undoAction: !showActions
        ? null
        : (compact) => toolbarAction(
            compact: compact,
            label: 'Undo',
            iconSize: 24,
            key: const ValueKey('undo-food-action'),
            tooltip: undoLabel,
            onPressed: onUndo,
            icon: const Icon(Icons.undo),
          ),
  );
}
