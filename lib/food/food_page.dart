import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../presentation/tag_input.dart';
import '../presentation/sticky_task_group.dart';
import '../presentation/task_toolbar.dart';
import '../presentation/section_content.dart';
import '../presentation/list_row_surface.dart';
import '../presentation/list_selection.dart';
import '../presentation/task_entry_area.dart';
import '../presentation/toolbar_action.dart';
import '../presentation/editor_surface.dart';
import '../presentation/free_text_autocomplete.dart';
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
  final FutureOr<void> Function(
    List<FoodContainer>,
    FoodDetails,
    List<String>,
    FoodProductChange,
  )
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
  /// and selectable rows follow exactly what is shown.
  late final List<FoodGroup> rows;
  late final List<FoodContainer> shown;
  late final Set<String> visibleIds;
  late final Set<String> visibleRows = Set.unmodifiable(
    rows.map((row) => row.rowKey),
  );

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
  String _lastSearchText = '';
  Set<String> reasons = {}, brands = {}, locations = {};

  /// Selected rows by [FoodGroup.rowKey]. A selected row means whichever
  /// containers are in it at use time: arrivals join, departures leave.
  final selectedRows = <String>{};
  bool selecting = false;
  String? _selectionAnchor;
  // The group open in a single-group editor; explicit selection starts with it.
  FoodGroup? _editingGroup;
  Object? _focusedGroup;

  /// The selected rows' current container IDs.
  Set<String> get bulkSelected => {
    for (final container in _rowContainers(selectedRows)) container.id,
  };

  /// The current containers of [keys], hidden or shown, in key order.
  List<FoodContainer> _rowContainers(Iterable<String> keys) => [
    for (final key in keys) ...?widget.state.rows[key],
  ];

  void _clearBulkSelection() {
    selecting = false;
    selectedRows.clear();
    _selectionAnchor = null;
  }

  static String _rowKey(FoodGroup group) => group.rowKey;

  /// Wide windows edit a selection in the side pane, as Tasks does.
  bool _wide = false;
  final _scroll = ScrollController();
  final _rowFocus = <String, FocusNode>{};

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
    var selected = Set<String>.of(selectedRows);
    var anchor = _selectionAnchor;
    final editing = _editingGroup == null
        ? null
        : rows[_rowKey(_editingGroup!)];
    if (!selecting && editing != null) {
      selected = {_rowKey(editing)};
      anchor = _rowKey(editing);
    }
    final result = nextListSelection<String>(
      selected: selected,
      selecting: selecting,
      anchor: anchor,
      target: _rowKey(group),
      order: rows.keys.toList(),
      members: (key) => [key],
      gesture: gesture,
    );
    if (gesture == SelectionGesture.plain &&
        setEquals(selected, result.selected)) {
      return;
    }
    // Two-to-one: narrowing a wide selection to one row returns to that
    // row's single editor, as on Tasks.
    final single =
        result.selecting &&
            _wide &&
            selected.length >= 2 &&
            result.selected.length == 1
        ? rows[result.selected.single]
        : null;
    if (_editorBuilder != null) {
      if (result.selected.isEmpty) {
        if (!await requestCloseEditor()) return;
        await editorDone;
      } else if (!await (_canReplaceEditor?.call() ?? Future.value(false))) {
        return;
      }
      if (!mounted || !usable()) return;
    }
    if (single != null) {
      setState(_clearBulkSelection);
      unawaited(
        _edit(
          group: single,
          rows: {_rowKey(single)},
          detailsCommand: widget.onDetails,
          replacingApproved: true,
        ),
      );
      return;
    }
    setState(() {
      selectedRows
        ..clear()
        ..addAll(
          result.selecting
              ? result.selected.intersection(_grouping.visibleRows)
              : const <String>{},
        );
      selecting = selectedRows.isNotEmpty;
      _selectionAnchor = selecting ? result.anchor : null;
    });
    if (selecting && _wide) unawaited(_editSelection(replacingApproved: true));
  }

  /// One row uses its own editor; multiple rows use the bulk editor, just as
  /// Tasks opens its single editor for one selected task. Either edits the
  /// selected rows' current containers.
  Future<void> _editSelection({bool replacingApproved = false}) {
    final rows = [
      for (final row in _grouping.rows)
        if (selectedRows.contains(_rowKey(row))) row,
    ];
    if (rows.isEmpty) return Future.value();
    return rows.length == 1
        ? _edit(
            group: rows.single,
            rows: {_rowKey(rows.single)},
            detailsCommand: widget.onDetails,
            replacingApproved: replacingApproved,
          )
        : _edit(
            rows: {for (final row in rows) _rowKey(row)},
            replacingApproved: replacingApproved,
          );
  }

  Future<void> _selectMatching(Set<String> observed, Object? workspace) async {
    bool usable() =>
        mounted &&
        !widget.busy &&
        widget.workspaceIdentity == workspace &&
        !(widget.hasPendingSave?.call() ?? widget.savePending);
    if (!usable()) return;
    final replace = _wide && _editorBuilder != null && observed.isNotEmpty;
    if (replace) {
      if (!await (_canReplaceEditor?.call() ?? Future.value(false))) return;
    } else {
      if (!await requestCloseEditor()) return;
      await editorDone;
    }
    if (!usable()) return;
    final selected = observed.intersection(_grouping.visibleRows);
    if (selected.isEmpty) return;
    setState(() {
      selecting = true;
      _selectionAnchor = null;
      selectedRows
        ..clear()
        ..addAll(selected);
    });
    if (_wide) unawaited(_editSelection(replacingApproved: replace));
  }

  /// Keep Tasks' search-input behavior: resolve the draft, then clear selection.
  /// View recomputation still uses the shared visible-ID retention policy.
  Future<void> _changeSearch(String value) async {
    if (!await requestCloseEditor()) {
      if (!mounted) return;
      search.text = _lastSearchText;
      return;
    }
    await editorDone;
    if (!mounted) return;
    setState(() {
      _lastSearchText = value;
      _clearBulkSelection();
    });
  }

  Future<void> _clearSearch() async {
    if (!await requestCloseEditor()) return;
    await editorDone;
    if (!mounted) return;
    setState(() {
      search.clear();
      _lastSearchText = '';
      _clearBulkSelection();
    });
  }

  /// Clear Selection also closes a wide selection's bulk pane.
  Future<void> _clearSelection() async {
    if (_editorBuilder != null) {
      if (!await requestCloseEditor()) return;
      await editorDone;
      if (!mounted) return;
    }
    setState(_clearBulkSelection);
  }

  /// Up/Down move between rows; with Shift they extend the selection from
  /// its anchor, as on Tasks.
  Future<void> _focusRelative(FoodGroup group, int direction) async {
    final workspace = widget.workspaceIdentity;
    final rows = _grouping.rows;
    final index = rows.indexWhere((row) => _rowKey(row) == _rowKey(group));
    final next = index + direction;
    if (index < 0 || next < 0 || next >= rows.length) return;
    final target = rows[next];
    if (HardwareKeyboard.instance.isShiftPressed) {
      _selectionAnchor ??= _rowKey(group);
      await _select(target, SelectionGesture.range, workspace);
      if (!mounted) return;
    }
    final key = _rowKey(target);
    var node = _rowFocus[key];
    if (node?.context == null && _scroll.hasClients) {
      final box = _rowFocus[_rowKey(group)]?.context?.findRenderObject();
      final step = box is RenderBox && box.hasSize ? box.size.height : 72.0;
      await _scroll.animateTo(
        (_scroll.offset + direction * step).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      node = _rowFocus[key];
    }
    final context = node?.context;
    if (context != null && context.mounted) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 120),
        alignmentPolicy: direction > 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
    if (mounted) _rowFocus[key]?.requestFocus();
  }

  /// Lets open dialogs follow incoming Food changes.
  late final _stateChanges = ValueNotifier<FoodState>(widget.state);

  @override
  void didUpdateWidget(covariant FoodInventoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _stateChanges.value = widget.state;
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
  Future<bool> Function()? _canReplaceEditor;
  Widget Function(bool panel)? _editorBuilder;
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
    HardwareKeyboard.instance.addHandler(_escapeClearsSelection);
  }

  /// Escape clears a selection, as on Tasks, even when no row or input has
  /// focus. Focused inputs keep Escape for themselves first (for example to
  /// dismiss suggestions) and reach the page's DismissIntent action instead.
  bool _escapeClearsSelection(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        !selecting ||
        _textHasFocus ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    unawaited(_clearSelection());
    return true;
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
    HardwareKeyboard.instance.removeHandler(_escapeClearsSelection);
    _stateChanges.dispose();
    _expirationClock.removeListener(_expirationChanged);
    _expirationClock.dispose();
    search.dispose();
    _scroll.dispose();
    for (final node in _rowFocus.values) {
      node.dispose();
    }
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
    if (view == FoodView.runningLow && widget.state.runningLow.isEmpty) {
      view = FoodView.inventory;
    }
    final grouping = _grouping;
    final live = {for (final row in grouping.rows) _rowKey(row)};
    final stale = _rowFocus.keys.where((k) => !live.contains(k)).toList();
    if (stale.isNotEmpty) {
      final nodes = [for (final k in stale) _rowFocus.remove(k)!];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in nodes) {
          node.dispose();
        }
      });
    }
    final runningLow = view == FoodView.runningLow && !querying
        ? widget.state.runningLow
              .where(
                (product) =>
                    (brands.isEmpty || brands.contains(product.brand)) &&
                    (locations.isEmpty ||
                        widget.state.active.any(
                          (item) =>
                              item.product == product.id &&
                              locations.contains(item.details.location),
                        )),
              )
              .toList()
        : const <FoodProductSummary>[];
    final inboxGroups = grouping.inbox;
    final visibleIds = grouping.visibleIds;
    final selection = retainVisibleListSelection<String>(
      selected: selectedRows,
      selecting: selecting,
      anchor: _selectionAnchor,
      visibleRows: live,
      visibleIds: live,
      editorOpen: _editorBuilder != null,
    );
    selectedRows
      ..clear()
      ..addAll(selection.selected);
    final selectedCount = _rowContainers(selectedRows).length;
    selecting = selection.selecting;
    _selectionAnchor = selection.anchor;
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
            // Escape clears a selection (resolving its editor first), as on
            // Tasks; otherwise it dismisses an open editor.
            if (_editorBuilder != null || selecting)
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  unawaited(
                    selecting ? _clearSelection() : requestCloseEditor(),
                  );
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
                    _wide = constraints.maxWidth >= EditorSurface.breakpoint;
                    final panel = _wide;
                    // Narrow selection waits for Edit. Widening the same list
                    // reveals its editor automatically, as on Tasks.
                    if (_wide &&
                        selecting &&
                        selectedRows.isNotEmpty &&
                        _editorBuilder == null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted &&
                            _wide &&
                            selecting &&
                            selectedRows.isNotEmpty &&
                            _editorBuilder == null) {
                          unawaited(_editSelection());
                        }
                      });
                    }
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
                                  controller: _scroll,
                                  slivers: [
                                    SliverToBoxAdapter(
                                      child: Column(
                                        children: [
                                          TaskEntryArea(
                                            selecting: selecting,
                                            wideLayout: _wide,
                                            editorOpen: _editorBuilder != null,
                                            captureVisible: true,
                                            selectionCount: selectedCount,
                                            maximumSelectionCount:
                                                visibleIds.length,
                                            onClear: () =>
                                                unawaited(_clearSelection()),
                                            onEdit:
                                                widget.busy ||
                                                    pending ||
                                                    selectedRows.isEmpty
                                                ? null
                                                : _editSelection,
                                            capture: TextField(
                                              key: const ValueKey(
                                                'food-search',
                                              ),
                                              controller: search,
                                              onChanged: _changeSearch,
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
                                                        onPressed: _clearSearch,
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
                                    if (runningLow.isNotEmpty) ...[
                                      SliverPadding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: rowInset,
                                        ),
                                        sliver: SliverList.builder(
                                          itemCount: runningLow.length,
                                          itemBuilder: (_, index) => _lowRow(
                                            runningLow[index],
                                            pending,
                                          ),
                                        ),
                                      ),
                                    ],
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
                                    ],
                                    if ((inboxGroups.isNotEmpty ||
                                            runningLow.isNotEmpty) &&
                                        groups.isNotEmpty)
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
                                    if (groups.isEmpty &&
                                        runningLow.isEmpty &&
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
                                                    FoodView.runningLow =>
                                                      'No matching food',
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

  /// One product below its minimum: what it is, how many of how many, its
  /// store link and Add another.
  Widget _lowRow(FoodProductSummary product, bool pending) {
    final colors = Theme.of(context).colorScheme;
    final link = product.links.firstOrNull;
    final description = [
      product.name,
      product.brand,
      product.size,
    ].where((value) => value.isNotEmpty).join(' · ');
    return ListRowSurface(
      key: ValueKey('food-running-low:${product.id}'),
      interactive: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label:
                    '$description, ${product.onHand} of ${product.minimum} on hand',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          product.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${product.onHand} of ${product.minimum}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.error,
                              ),
                        ),
                      ],
                    ),
                    if (product.brand.isNotEmpty || product.size.isNotEmpty)
                      Text(
                        [
                          product.brand,
                          product.size,
                        ].where((v) => v.isNotEmpty).join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (link != null)
              IconButton(
                tooltip: 'Open store link for ${product.name}',
                onPressed: () => launchUrl(
                  Uri.parse(link),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
              ),
            IconButton(
              tooltip: 'Add another ${product.name}',
              onPressed: widget.busy || pending
                  ? null
                  : () => _edit(
                      template: product.description,
                      addCommand: widget.onAdd,
                    ),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterControl(bool compact) {
    final querying = search.text.trim().isNotEmpty;
    final active =
        !querying &&
        (view == FoodView.runningLow ||
            view == FoodView.deleted ||
            view == FoodView.retained ||
            brands.isNotEmpty ||
            locations.isNotEmpty);
    final label = switch (view) {
      FoodView.deleted => 'Deleted',
      FoodView.retained => 'Retained',
      FoodView.runningLow => 'Running low',
      _ => 'Stock',
    };
    final lowCount = widget.state.runningLow.length;
    final low = lowCount > 0;
    final lowProducts = '$lowCount ${lowCount == 1 ? "product" : "products"}';
    final lowLabel = '$lowProducts running low';
    final icon = low
        ? Badge(
            key: const ValueKey('food-low-warning'),
            backgroundColor: Theme.of(context).colorScheme.error,
            child: const Icon(Icons.filter_list),
          )
        : toolbarFilterIcon(active: active);
    return toolbarMenuAction<FoodView>(
      context: context,
      compact: compact,
      label: 'Filter',
      icon: icon,
      key: const ValueKey('food-filter'),
      tooltip: querying
          ? 'Filter food: all food; saved $label filters paused${low ? ' · $lowLabel' : ''}'
          : 'Filter food: $label${active ? ' · active filters' : ''}${low ? ' · $lowLabel' : ''}',
      enabled: !widget.busy,
      onSelected: (next) => setState(() {
        view = next;
      }),
      itemBuilder: (_) {
        final observed = Set.of(_grouping.visibleRows);
        final workspace = widget.workspaceIdentity;
        return [
          for (final mode in [
            FoodView.inventory,
            FoodView.retained,
            FoodView.deleted,
            if (low) FoodView.runningLow,
          ])
            PopupMenuItem(
              value: mode,
              child: Semantics(
                selected: mode == view,
                label: mode == FoodView.runningLow
                    ? 'Running low, $lowProducts'
                    : null,
                excludeSemantics: mode == FoodView.runningLow,
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
                        FoodView.runningLow => 'Running low · $lowCount',
                      }),
                    ),
                    // The closed filter button's warning dot, explained here.
                    if (mode == FoodView.runningLow) ...[
                      const SizedBox(width: 8),
                      Badge(
                        key: const ValueKey('food-low-menu-warning'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ],
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
            onTap: () => unawaited(_selectMatching(observed, workspace)),
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
    group.key,
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
      selecting && selectedRows.contains(_rowKey(group));

  bool _groupHighlighted(FoodGroup group) =>
      _groupSelected(group) ||
      (_editingGroup != null && _rowKey(_editingGroup!) == _rowKey(group));

  List<PopupMenuEntry<String>> _groupMenuItems(FoodGroup group) => [
    if (widget
            .state
            .products[group.containers.first.product]
            ?.links
            .isNotEmpty ??
        false)
      const PopupMenuItem<String>(
        value: 'open-store-link',
        child: Text('Open store link'),
      ),
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
    // Moving all of them is an ordinary Location edit, so Move some needs
    // at least two containers.
    if (!group.containers.first.deleted && group.containers.length > 1)
      PopupMenuItem<String>(
        enabled: !(widget.hasPendingSave?.call() ?? widget.savePending),
        value: 'move-some',
        child: const Text('Move some…'),
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
    final key = _rowKey(group);
    final identity = _groupMenuIdentity(group);
    final countLabel =
        '${group.containers.length} ${group.containers.length == 1 ? 'container' : 'containers'}';
    final metadata = [
      if (details.brand.isNotEmpty) details.brand,
      if (details.size.isNotEmpty) details.size,
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
      if (action == 'open-store-link') {
        final link = widget
            .state
            .products[group.containers.first.product]
            ?.links
            .firstOrNull;
        if (link != null) {
          unawaited(
            launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
          );
        }
      }
      if (action == 'select') select(SelectionGesture.longPress);
      if (action == 'move-some' &&
          !(widget.hasPendingSave?.call() ?? widget.savePending)) {
        unawaited(_moveSome(group));
      }
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
        color: _groupHighlighted(group)
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
          // its buttons keep their own Space activation.
          onKeyEvent: (node, event) {
            if (FocusManager.instance.primaryFocus?.parent == node &&
                event is! KeyUpEvent &&
                (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                    event.logicalKey == LogicalKeyboardKey.arrowDown)) {
              unawaited(
                _focusRelative(
                  group,
                  event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1,
                ),
              );
              return KeyEventResult.handled;
            }
            if (event.logicalKey != LogicalKeyboardKey.space ||
                event is KeyUpEvent ||
                FocusManager.instance.primaryFocus?.parent != node) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent && editable) {
              select(SelectionGesture.toggle);
            }
            return KeyEventResult.handled;
          },
          child: InkWell(
            focusNode: _rowFocus.putIfAbsent(
              key,
              () => FocusNode(debugLabel: 'Food row ${details.name}'),
            ),
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
                  Expanded(
                    child: Semantics(
                      button: true,
                      enabled: editable,
                      label: [
                        selecting ? 'Select' : 'Edit',
                        details.name,
                        countLabel,
                        details.expiry ?? 'Needs expiration',
                        if (details.location.isNotEmpty) details.location,
                        if (details.retention.isNotEmpty) details.retention,
                        ...metadata,
                      ].join(', '),
                      selected: _groupHighlighted(group),
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
                                details.location,
                                details.retention,
                              ].where((value) => value.isNotEmpty)) ...[
                                const Text('·'),
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

  /// Move some… gives some of a row's containers a new Location, so they form
  /// their own row. It is one Location edit: one command and one Undo action.
  /// Moving every container is allowed too; it equals editing the row.
  Future<void> _moveSome(FoodGroup group) async {
    final workspace = widget.workspaceIdentity;
    final key = _rowKey(group);
    final details = group.details;
    List<FoodContainer> current() => widget.state.rows[key] ?? const [];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _MoveSomeDialog(
        details: details,
        changes: _stateChanges,
        available: () => current().length,
        locations: () => widget.state.locations,
        move: (count, location) async {
          final pending = widget.hasPendingSave?.call() ?? widget.savePending;
          if (!mounted || workspace != widget.workspaceIdentity || pending) {
            throw FormatException(
              pending
                  ? 'Finish the pending save first.'
                  : 'The food workspace changed. Close and try again.',
            );
          }
          // The row's containers at Move time, not when the dialog opened.
          await widget.onDetails(
            current().take(count).toList(),
            FoodDetails(
              name: details.name,
              brand: details.brand,
              expiry: details.expiry,
              estimated: details.estimated,
              retention: details.retention,
              location: location,
              size: details.size,
            ),
            const ['location'],
            const FoodProductChange(),
          );
        },
      ),
    );
  }

  Future<void> _edit({
    FoodGroup? group,
    bool replacingApproved = false,
    FoodDetails? template,
    Set<String>? rows,
    FutureOr<void> Function(FoodDetails, int)? addCommand,
    FutureOr<void> Function(
      List<FoodContainer>,
      FoodDetails,
      List<String>,
      FoodProductChange,
    )?
    detailsCommand,
  }) async {
    if (group != null &&
        _editingGroup != null &&
        _rowKey(group) == _rowKey(_editingGroup!) &&
        !selecting) {
      return;
    }
    final request = ++_editorRequest;
    final workspace = widget.workspaceIdentity;
    final add = addCommand ?? widget.onAdd;
    final changeDetails = detailsCommand ?? widget.onDetails;
    // Selected rows resolve to their current containers on every build, so
    // the editor's count and targets follow arrivals and departures. A row
    // whose containers all left keeps its last membership for display, and
    // Save refuses it. Plain-click editing keeps its observed containers.
    final rowKeys = rows == null ? null : List<String>.unmodifiable(rows);
    final bulk = rowKeys != null && group == null;
    var lastGroup = group;
    var lastTargets = bulk
        ? List<FoodContainer>.unmodifiable(_rowContainers(rowKeys))
        : null;
    FoodGroup? currentGroup() {
      if (group == null || rowKeys == null) return group;
      final members = widget.state.rows[_rowKey(group)];
      if (members != null && members.isNotEmpty) {
        lastGroup = FoodGroup(members, productKey: group.productKey);
      }
      return lastGroup;
    }

    List<FoodContainer>? currentTargets() {
      if (!bulk) return null;
      final members = _rowContainers(rowKeys);
      if (members.isNotEmpty) lastTargets = List.unmodifiable(members);
      return lastTargets;
    }

    // Every row with containers is still shown: a newly hidden row is
    // refused rather than silently dropped from the edit.
    bool rowsShown() =>
        rowKeys == null ||
        (_rowContainers(rowKeys).isNotEmpty &&
            rowKeys.every(
              (key) =>
                  (widget.state.rows[key]?.isEmpty ?? true) ||
                  _grouping.visibleRows.contains(key),
            ));
    if (_editorDone != null && !replacingApproved) {
      if (!await (_canReplaceEditor?.call() ?? Future.value(false))) return;
    }
    if (!mounted ||
        request != _editorRequest ||
        workspace != widget.workspaceIdentity ||
        (widget.hasPendingSave?.call() ?? widget.savePending) ||
        (group != null && !_canUseGroupMenu(group, workspace)) ||
        (bulk && (lastTargets!.isEmpty || !rowsShown()))) {
      return;
    }
    final removeCommand = widget.onRemove,
        restoreCommand = widget.onRestore,
        restoreBatchCommand = widget.onRestoreBatch;
    final key = GlobalKey<FoodEditorState>();
    final done = _editorDone = Completer<void>();
    final previousFocus = FocusManager.instance.primaryFocus;
    (FoodDetails, int)? accepted;
    _canReplaceEditor = () async =>
        await key.currentState?.requestClose(close: false) ?? false;
    _editorCloseBusy = () => key.currentState?.closeBusy ?? true;
    _requestEditorClose = () async =>
        await key.currentState?.requestClose() ?? false;
    _editingGroup = group;
    setState(
      () => _editorBuilder = (panel) => FoodEditor(
        key: key,
        panel: panel,
        group: currentGroup(),
        template: template,
        targets: currentTargets(),
        state: widget.state,
        onAdd: add,
        onDetails: changeDetails,
        pending: () => widget.hasPendingSave?.call() ?? widget.savePending,
        isOriginCurrent: () =>
            mounted &&
            workspace == widget.workspaceIdentity &&
            (group == null ||
                (widget.hasPendingSave?.call() ?? widget.savePending) ||
                (rowKeys != null
                    ? rowsShown()
                    : group.containers.every(
                        (e) => widget.state.containers.any(
                          (item) =>
                              item.id == e.id &&
                              item.deleted == e.deleted &&
                              item.deletions.length == e.deletions.length &&
                              item.deletions.containsAll(e.deletions),
                        ),
                      ))),
        areTargetsVisible: () => !bulk || rowsShown(),
        onBulkApplied: () {
          if (mounted) setState(_clearBulkSelection);
        },
        onRemoveTargets: !bulk
            ? null
            : (items) => removeCommand(items.map((e) => e.id).toList()),
        onRestoreTargets: !bulk
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
            _clearBulkSelection();
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
    // Completion follows actual input disposal, including whole-page disposal.
    await done.future;
    // A replaced editor only releases its own inputs. It must not clear the
    // replacement's close guard or restore focus over the new editor.
    if (!identical(_editorDone, done)) return;
    if (identical(_editorDone, done)) {
      _editingGroup = null;
      _canReplaceEditor = null;
      _requestEditorClose = null;
      _editorCloseBusy = null;
      _editorDone = null;
    }
    if (!mounted) return;
    if (accepted != null && !bulk && group == null) {
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

/// How many containers of one row move, and where to; errors sit beside the
/// fields once Move reveals them.
class _MoveSomeDialog extends StatefulWidget {
  const _MoveSomeDialog({
    required this.details,
    required this.changes,
    required this.available,
    required this.locations,
    required this.move,
  });
  final FoodDetails details;
  final Listenable changes;
  final int Function() available;
  final List<String> Function() locations;
  final Future<void> Function(int count, String location) move;

  @override
  State<_MoveSomeDialog> createState() => _MoveSomeDialogState();
}

class _MoveSomeDialogState extends State<_MoveSomeDialog> {
  final amount = TextEditingController(text: '1')
    ..selection = const TextSelection(baseOffset: 0, extentOffset: 1);
  final location = TextEditingController();
  String? amountError, locationError, failure;
  var revealed = false, saving = false;

  @override
  void initState() {
    super.initState();
    widget.changes.addListener(_changed);
  }

  @override
  void dispose() {
    widget.changes.removeListener(_changed);
    amount.dispose();
    location.dispose();
    super.dispose();
  }

  // Food changes arrive while the page rebuilds; follow them after the frame.
  void _changed() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    setState(() {
      if (revealed) _validate();
    });
  });

  /// The count to move, or null with field errors set.
  int? _validate() {
    final available = widget.available();
    final count = int.tryParse(amount.text.trim());
    amountError = available == 0
        ? 'These containers changed. Close and choose the row again.'
        : count == null || count < 1 || count > available
        ? 'Enter 1 to $available.'
        : null;
    final value = location.text.trim();
    locationError = value == widget.details.location
        ? 'Choose a different location.'
        : value.length > 200 || value.contains('\u0000')
        ? 'Use 200 characters or fewer.'
        : null;
    return amountError == null && locationError == null ? count : null;
  }

  Future<void> _move() async {
    if (saving) return;
    final count = _validate();
    setState(() {
      revealed = true;
      failure = null;
    });
    if (count == null) return;
    setState(() => saving = true);
    try {
      await widget.move(count, location.text.trim());
      if (mounted) _answerOnce<void>(context)(null);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          failure = e is FormatException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.available(), details = widget.details;
    void edited(String _) {
      if (revealed) setState(_validate);
    }

    return AlertDialog(
      key: const ValueKey('food-move-some'),
      title: Text('Move some ${details.name}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$available ${available == 1 ? 'container is' : 'containers are'} '
                'in ${details.location.isEmpty ? 'no location' : details.location}. '
                'The ones you move get their own row.',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('food-move-count'),
                controller: amount,
                autofocus: true,
                enabled: !saving,
                keyboardType: TextInputType.number,
                onChanged: edited,
                onSubmitted: (_) => unawaited(_move()),
                decoration: InputDecoration(
                  labelText: 'How many',
                  errorText: revealed ? amountError : null,
                  errorMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
              FreeTextAutocomplete(
                key: const ValueKey('food-move-location'),
                controller: location,
                enabled: !saving,
                label: 'New location',
                values: widget.locations(),
                errorText: revealed ? locationError : null,
                onChanged: edited,
                onSelected: edited,
              ),
              if (failure != null) ...[
                const SizedBox(height: 12),
                Text(
                  failure!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => _answerOnce<void>(context)(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : () => unawaited(_move()),
          child: const Text('Move'),
        ),
      ],
    );
  }
}
