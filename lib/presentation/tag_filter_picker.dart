import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Inline exact-tag selection with suggestions outside the dialog's layout.
class TagFilterPicker extends StatefulWidget {
  const TagFilterPicker({
    super.key,
    required this.tags,
    required this.selected,
    required this.onChanged,
    required this.onQueryChanged,
    required this.onDropdownChanged,
  });
  final List<String> tags;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final VoidCallback onQueryChanged;
  final ValueChanged<bool> onDropdownChanged;

  @override
  State<TagFilterPicker> createState() => TagFilterPickerState();
}

class TagFilterPickerState extends State<TagFilterPicker>
    with WidgetsBindingObserver {
  final _query = TextEditingController();
  final _focus = FocusNode();
  OverlayEntry? _overlayEntry;
  final _link = LayerLink();
  final _anchor = GlobalKey();
  final _tapGroup = Object();
  ScrollPosition? _scroll;
  bool _open = false;
  bool _positionPending = false;
  bool _revealAfterMetrics = false;
  Size? _viewportSize;
  bool _ignoreNextFocus = false;

  bool get dropdownOpen => _open;
  bool get hasQuery => _query.text.isNotEmpty;
  List<String> get _matches => widget.tags
      .where((tag) => tag.toLowerCase().contains(_query.text.toLowerCase()))
      .toList();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    // The old anchor may be clipped for one layout frame before the focused
    // editor reveals its caret. Keep an intentional open popup through that
    // transition; ordinary user scrolling away still dismisses it.
    if (_open && _focus.hasFocus) _revealAfterMetrics = true;
    _reposition();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (_scroll != scroll) {
      _scroll?.removeListener(_reposition);
      _scroll = scroll;
      _scroll?.addListener(_reposition);
    }
    _reposition();
  }

  @override
  void didUpdateWidget(TagFilterPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reposition();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) {
      dismissDropdown();
    } else if (_ignoreNextFocus) {
      _ignoreNextFocus = false;
    } else {
      _show();
    }
  }

  void _reposition() {
    if (!_open || _positionPending) return;
    _positionPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionPending = false;
      if (!mounted || !_open) return;
      final anchor = _anchor.currentContext;
      final box = anchor?.findRenderObject();
      final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          viewport is RenderBox &&
          viewport.hasSize) {
        // Dialog padding can finish shrinking the scroll viewport after the
        // first keyboard metrics frame. Reveal against each changed extent,
        // then check geometry after layout; do not close on that stale frame.
        final resized = _revealAfterMetrics || _viewportSize != viewport.size;
        _revealAfterMetrics = false;
        _viewportSize = viewport.size;
        if (resized && _focus.hasFocus) {
          Scrollable.ensureVisible(anchor!);
          _overlayEntry?.markNeedsBuild();
          _reposition();
          return;
        }
        final field = box.localToGlobal(Offset.zero) & box.size;
        final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
        if (!field.overlaps(visible)) {
          dismissDropdown();
          return;
        }
      }
      _overlayEntry?.markNeedsBuild();
    });
  }

  void _show() {
    if (_open) return;
    setState(() => _open = true);
    // Keep painted results outside the query's clipped semantic scroll viewport.
    // The portal painted visible Android labels that were missing from its
    // accessibility hierarchy; the entry gives them their actual overlay bounds.
    _overlayEntry = OverlayEntry(
      builder: (_) => MediaQuery(
        data: MediaQuery.of(context),
        child: InheritedTheme.captureAll(context, _suggestions(context)),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    widget.onDropdownChanged(true);
  }

  bool dismissDropdown() {
    if (!_open) return false;
    _revealAfterMetrics = false;
    _removeOverlay();
    setState(() => _open = false);
    widget.onDropdownChanged(false);
    return true;
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  void clearQuery() {
    _query.clear();
    _overlayEntry?.markNeedsBuild();
    widget.onQueryChanged();
    if (mounted) setState(() {});
  }

  void _toggle(String tag) {
    final next = Set<String>.of(widget.selected);
    if (!next.add(tag)) next.remove(tag);
    widget.onChanged(next);
    dismissDropdown();
    if (!_focus.hasFocus) {
      _ignoreNextFocus = true;
      _focus.requestFocus();
    }
    _reposition();
  }

  Widget _suggestions(BuildContext context) {
    final box = _anchor.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return const SizedBox.shrink();
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final media = MediaQuery.of(context);
    final view = View.of(context);
    final top = view.padding.top / view.devicePixelRatio + 8;
    final bottom =
        media.size.height -
        math.max(
          view.viewInsets.bottom / view.devicePixelRatio,
          view.padding.bottom / view.devicePixelRatio,
        ) -
        8;
    final below = math.max(0.0, bottom - rect.bottom - 4);
    final above = math.max(0.0, rect.top - top - 4);
    final width = math.min(rect.width, media.size.width - 16);
    final matches = _matches;
    double rowHeight(String text) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        textDirection: Directionality.of(context),
        textScaler: media.textScaler,
        maxLines: 2,
      )..layout(maxWidth: math.max(1, width - 72));
      final height = math.max(56.0, painter.height + 16);
      painter.dispose();
      return height;
    }

    final resultHeights = matches.isEmpty
        ? [rowHeight(widget.tags.isEmpty ? 'No tags yet' : 'No matching tags')]
        : matches.take(4).map((tag) => rowHeight('#$tag')).toList();
    final desired = math.min(200.0, resultHeights.reduce((a, b) => a + b));
    // Prefer below even when above has more space. One result needs one row;
    // longer lists need two usable rows and scroll within the remaining space.
    // The overlay may extend past the dialog footer, which is not a viewport.
    final usable = math.min(
      desired,
      resultHeights.take(2).reduce((a, b) => a + b),
    );
    final upward = below < usable && above > below;
    final height = math.min(
      math.min(desired, math.max(0.0, bottom - top)),
      upward ? above : below,
    );
    final y = (upward ? rect.top - height - 4 : rect.bottom + 4).clamp(
      top,
      math.max(top, bottom - height),
    );
    final x = rect.left.clamp(8.0, math.max(8.0, media.size.width - width - 8));
    return SizedBox.expand(
      child: Stack(
        children: [
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: Offset(x - rect.left, y - rect.top),
            child: TextFieldTapRegion(
              child: TapRegion(
                groupId: _tapGroup,
                child: Material(
                  elevation: 8,
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    key: const ValueKey('tag-results'),
                    width: width,
                    height: height,
                    child: matches.isEmpty
                        ? Center(
                            child: Text(
                              widget.tags.isEmpty
                                  ? 'No tags yet'
                                  : 'No matching tags',
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final tag = matches[index];
                              final selected = widget.selected.contains(tag);
                              return Semantics(
                                selected: selected,
                                child: ListTile(
                                  key: ValueKey('tag-option-$tag'),
                                  selected: selected,
                                  leading: selected
                                      ? const Icon(Icons.check, size: 20)
                                      : const SizedBox(width: 20),
                                  title: Tooltip(
                                    message: '#$tag',
                                    child: Text(
                                      '#$tag',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  onTap: () => _toggle(tag),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    // Picker controls belong to the query field. Otherwise a control tap can
    // unfocus/dismiss the field before the same tap processes its toggle.
    child: CompositedTransformTarget(
      link: _link,
      child: TapRegion(
        groupId: _tapGroup,
        onTapOutside: (_) => dismissDropdown(),
        child: Container(
          key: _anchor,
          child: Container(
            key: const ValueKey('tag-autocomplete'),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final tag in widget.selected.toList()..sort())
                          Tooltip(
                            message: '#$tag',
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth,
                              ),
                              child: InputChip(
                                key: ValueKey('selected-tag-$tag'),
                                label: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: math.max(
                                      0,
                                      constraints.maxWidth - 64,
                                    ),
                                  ),
                                  child: Text(
                                    '#$tag',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                onDeleted: () => _toggle(tag),
                              ),
                            ),
                          ),
                        SizedBox(
                          key: const ValueKey('tag-query-slot'),
                          width: math.min(160, constraints.maxWidth),
                          child: Focus(
                            onKeyEvent: (_, event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.escape &&
                                  dismissDropdown()) {
                                return KeyEventResult.handled;
                              }
                              if (event is KeyDownEvent &&
                                  event.logicalKey == LogicalKeyboardKey.tab) {
                                dismissDropdown();
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              key: const ValueKey('tag-search'),
                              controller: _query,
                              focusNode: _focus,
                              decoration: const InputDecoration(
                                hintText: 'Find tags',
                                filled: false,
                                isDense: true,
                                border: InputBorder.none,
                              ),
                              onTap: _show,
                              onChanged: (_) {
                                _show();
                                _overlayEntry?.markNeedsBuild();
                                setState(() {});
                                widget.onQueryChanged();
                              },
                              onSubmitted: (_) {
                                final tag = _matches.firstOrNull;
                                if (tag != null &&
                                    !widget.selected.contains(tag)) {
                                  _toggle(tag);
                                }
                                dismissDropdown();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Clear tag filters',
                  onPressed: widget.selected.isEmpty && !hasQuery
                      ? null
                      : () {
                          dismissDropdown();
                          widget.onChanged({});
                          clearQuery();
                        },
                  icon: const Icon(Icons.close),
                ),
                IconButton(
                  tooltip: _open
                      ? 'Collapse tag options'
                      : 'Expand tag options',
                  onPressed: () {
                    if (!dismissDropdown()) _show();
                    if (!_focus.hasFocus) {
                      // Keep typing/the IME available without reopening a
                      // dropdown the user just deliberately collapsed.
                      _ignoreNextFocus = true;
                      _focus.requestFocus();
                    }
                  },
                  icon: Icon(
                    _open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _removeOverlay();
    WidgetsBinding.instance.removeObserver(this);
    _scroll?.removeListener(_reposition);
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _query.dispose();
    super.dispose();
  }
}
