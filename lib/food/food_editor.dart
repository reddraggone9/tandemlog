import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../presentation/civil_date_input.dart';
import '../presentation/free_text_autocomplete.dart';
import '../presentation/tag_input.dart';
import 'inventory.dart';

/// One Food draft owns its inputs and captured commands across layout changes.
class FoodEditor extends StatefulWidget {
  const FoodEditor({
    super.key,
    required this.panel,
    this.group,
    this.template,
    this.targets,
    required this.state,
    required this.onAdd,
    required this.onDetails,
    required this.pending,
    required this.isOriginCurrent,
    required this.areTargetsVisible,
    required this.onBulkApplied,
    required this.onClosed,
    required this.onDisposed,
    this.onReadinessChanged,
  });
  final bool panel;
  final FoodGroup? group;
  final FoodDetails? template;
  final List<FoodContainer>? targets;
  final FoodState state;
  final FutureOr<void> Function(FoodDetails, int) onAdd;
  final FutureOr<void> Function(List<FoodContainer>, FoodDetails, List<String>)
  onDetails;
  final bool Function() pending, isOriginCurrent, areTargetsVisible;
  final VoidCallback onBulkApplied, onDisposed;
  final ValueChanged<(FoodDetails, int)?> onClosed;
  final VoidCallback? onReadinessChanged;
  @override
  State<FoodEditor> createState() => FoodEditorState();
}

class FoodEditorState extends State<FoodEditor> {
  final expiryFocus = FocusNode();
  final _focusScope = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  final _formKey = GlobalKey();
  final _scroll = ScrollController();
  late final TextEditingController name,
      brand,
      expiry,
      size,
      location,
      count,
      retentionQuery;
  late final FoodDetails? original;
  late final bool? estimated;
  late String retention;
  late final String initial;
  var applyBrand = false,
      applyLocation = false,
      clearBrand = false,
      clearLocation = false;
  var answered = false, saving = false, deciding = false, auxiliaryOpen = false;
  Future<bool>? closeRequest;
  (FoodDetails, int)? _completedSave;
  String? error;
  double? editorViewportHeight;
  bool _routeCurrent = true;
  bool get bulk => widget.targets != null;
  bool pending() => widget.pending();
  bool get closeBusy =>
      saving ||
      answered ||
      auxiliaryOpen ||
      (!deciding && !(ModalRoute.of(context)?.isCurrent ?? true));
  String common(String Function(FoodDetails) field) =>
      widget.targets!.map((e) => field(e.details)).toSet().length == 1
      ? field(widget.targets!.first.details)
      : '';
  List<TextEditingController> get _controllers => [
    name,
    brand,
    expiry,
    size,
    location,
    count,
    retentionQuery,
  ];
  String snapshot() => jsonEncode([
    for (final controller in _controllers) controller.text,
    retention,
    estimated,
    applyBrand,
    applyLocation,
    clearBrand,
    clearLocation,
  ]);
  @override
  void initState() {
    super.initState();
    original = bulk
        ? widget.targets!.first.details
        : widget.group?.details ?? widget.template;
    name = TextEditingController(text: original?.name ?? '');
    brand = TextEditingController(
      text: bulk ? common((e) => e.brand) : original?.brand ?? '',
    );
    expiry = TextEditingController(
      text: widget.template == null ? original?.expiry ?? '' : '',
    );
    size = TextEditingController(text: original?.size ?? '');
    location = TextEditingController(
      text: bulk ? common((e) => e.location) : original?.location ?? '',
    );
    count = TextEditingController(text: '1');
    retentionQuery = TextEditingController();
    retention = widget.template == null ? original?.retention ?? '' : '';
    estimated = widget.template == null ? original?.estimated : null;
    initial = snapshot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (!_routeCurrent && current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _finishAcceptedSave();
          widget.onReadinessChanged?.call();
        }
      });
    }
    _routeCurrent = current;
  }

  void answer(BuildContext owner, (FoodDetails, int)? result) {
    if (answered || !mounted || !(ModalRoute.of(owner)?.isCurrent ?? true)) {
      return;
    }
    answered = true;
    widget.onClosed(result);
  }

  void _finishAcceptedSave() {
    final result = _completedSave;
    if (result != null && mounted && !auxiliaryOpen) answer(context, result);
  }

  Future<bool> requestClose() =>
      closeRequest ??= _decideClose().whenComplete(() {
        closeRequest = null;
        widget.onReadinessChanged?.call();
      });

  Future<bool> _decideClose() async {
    if (closeBusy || deciding) return false;
    if (snapshot() != initial) {
      deciding = true;
      bool? discard;
      final values = {
        for (final controller in _controllers) controller: controller.value,
      };
      try {
        final route = DialogRoute<bool>(
          context: context,
          builder: (ctx) {
            final decide = _answerOnce<bool>(ctx);
            return AlertDialog(
              scrollable: true,
              title: Text(
                pending() ? 'Close food editor?' : 'Discard food changes?',
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
        unawaited(
          Navigator.of(context).push(route).then((value) => discard = value),
        );
        await route.completed;
      } finally {
        deciding = false;
      }
      if (!mounted || answered) return false;
      if (discard != true) {
        for (final entry in values.entries) {
          entry.key.value = entry.value;
        }
        return false;
      }
    }
    answer(context, null);
    return answered;
  }

  @override
  void dispose() {
    expiryFocus.dispose();
    _focusScope.dispose();
    _scroll.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _focusScope.traversalEdgeBehavior = widget.panel
        ? TraversalEdgeBehavior.parentScope
        : TraversalEdgeBehavior.closedLoop;
    final group = widget.group,
        template = widget.template,
        targets = widget.targets;
    final add = widget.onAdd, changeDetails = widget.onDetails;
    final dialogContext = context;
    final setDialog = setState;
    final cancel = requestClose;
    final title = Text(
      bulk
          ? 'Edit ${targets!.length} containers'
          : group == null
          ? 'Add food'
          : 'Edit ${group.containers.length} ${group.containers.length == 1 ? 'container' : 'containers'}',
    );
    final content = SizedBox(
      key: _formKey,
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bulk) ...[
            for (final field in ['Brand', 'Location']) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Apply $field'),
                controlAffinity: ListTileControlAffinity.leading,
                value: field == 'Brand' ? applyBrand : applyLocation,
                onChanged: saving || pending()
                    ? null
                    : (value) => setDialog(() {
                        if (field == 'Brand') {
                          applyBrand = value ?? false;
                        } else {
                          applyLocation = value ?? false;
                        }
                      }),
              ),
              Row(
                children: [
                  Expanded(
                    child: FreeTextAutocomplete(
                      enabled:
                          !saving &&
                          !pending() &&
                          (field == 'Brand' ? applyBrand : applyLocation),
                      controller: field == 'Brand' ? brand : location,
                      label: field,
                      hint:
                          common(
                            (e) => field == 'Brand' ? e.brand : e.location,
                          ).isEmpty
                          ? 'Mixed or empty — unchanged unless applied'
                          : null,
                      values: field == 'Brand'
                          ? widget.state.brands
                          : widget.state.locations,
                      onChanged: (_) => setDialog(() {
                        if (field == 'Brand') {
                          clearBrand = false;
                        } else {
                          clearLocation = false;
                        }
                      }),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear $field',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: saving || pending()
                        ? null
                        : () => setDialog(() {
                            if (field == 'Brand') {
                              applyBrand = true;
                              clearBrand = true;
                              brand.clear();
                            } else {
                              applyLocation = true;
                              clearLocation = true;
                              location.clear();
                            }
                          }),
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ] else ...[
            TextField(
              enabled: !saving && !pending(),
              controller: name,
              autofocus: template == null,
              decoration: const InputDecoration(labelText: 'Food name'),
            ),
            const SizedBox(height: 12),
            FreeTextAutocomplete(
              enabled: !saving && !pending(),
              controller: brand,
              label: 'Brand',
              values: widget.state.brands,
            ),
            const SizedBox(height: 12),
            CivilDateInput(
              enabled: !saving && !pending(),
              controller: expiry,
              isOwnerMounted: () => mounted && !answered,
              onPickerChanged: (open) {
                auxiliaryOpen = open;
                if (!open) _finishAcceptedSave();
                widget.onReadinessChanged?.call();
              },
              fieldKey: const ValueKey('food-expiration'),
              focusNode: expiryFocus,
              autofocus: template != null,
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
            FreeTextAutocomplete(
              enabled: !saving && !pending(),
              controller: location,
              label: 'Location',
              values: widget.state.locations,
            ),
            if (group == null) ...[
              const SizedBox(height: 12),
              TextField(
                enabled: !saving && !pending(),
                controller: count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Containers to add',
                  helperText: 'Creates a separate container for each one',
                  helperMaxLines: 2,
                ),
              ),
            ],
            if (group != null) ...[
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
            ],
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
    final actions = [
      TextButton(
        onPressed: saving ? null : cancel,
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                if (!mounted || closeBusy || deciding) {
                  return;
                }
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
                  if (!bulk && expiry.text.trim().isEmpty) {
                    throw const FormatException('Expiration is required.');
                  }
                  if (bulk &&
                      ((applyBrand &&
                              brand.text.trim().isEmpty &&
                              !clearBrand) ||
                          (applyLocation &&
                              location.text.trim().isEmpty &&
                              !clearLocation))) {
                    throw const FormatException(
                      'Use Clear Brand or Clear Location to remove a value.',
                    );
                  }
                  final details = FoodDetails(
                    name: name.text.trim(),
                    brand: brand.text.trim(),
                    expiry: bulk ? original!.expiry : expiry.text.trim(),
                    estimated: estimated,
                    retention: group == null && !bulk
                        ? ''
                        : retentionQuery.text.trim().isEmpty
                        ? retention
                        : retentionQuery.text.trim(),
                    size: size.text.trim(),
                    location: location.text.trim(),
                  );
                  details.validate();
                  if (!widget.isOriginCurrent()) {
                    throw FormatException(
                      bulk
                          ? 'The selected containers changed. Close this editor and select again.'
                          : 'The food workspace or containers changed. Close this editor and select again.',
                    );
                  }
                  setDialog(() => saving = true);
                  if (bulk) {
                    if (!pending() && !widget.areTargetsVisible()) {
                      throw const FormatException(
                        'The selected containers changed. Close this editor and select again.',
                      );
                    }
                    final fields = [
                      if (applyBrand &&
                          targets!.any((e) => e.details.brand != details.brand))
                        'brand',
                      if (applyLocation &&
                          targets!.any(
                            (e) => e.details.location != details.location,
                          ))
                        'location',
                    ];
                    if (fields.isNotEmpty) {
                      await changeDetails(targets!, details, fields);
                    }
                    if (mounted) widget.onBulkApplied();
                  } else if (group == null) {
                    await add(details, amount);
                  } else {
                    final before = original!.toJson(), after = details.toJson();
                    final fields = after.keys
                        .where(
                          (key) =>
                              key != 'estimated' && before[key] != after[key],
                        )
                        .toList();
                    if (fields.isNotEmpty) {
                      await changeDetails(group.containers, details, fields);
                    }
                  }
                  if (dialogContext.mounted) {
                    _completedSave = (details, amount);
                    _finishAcceptedSave();
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    setDialog(() {
                      saving = false;
                      error = e is FormatException ? e.message : e.toString();
                    });
                  }
                } finally {
                  if (mounted) {
                    widget.onReadinessChanged?.call();
                  }
                }
              },
        child: Text(
          pending()
              ? 'Retry save'
              : !bulk && group == null
              ? 'Add'
              : 'Save',
        ),
      ),
    ];
    final presentation = widget.panel
        ? Material(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DefaultTextStyle(
                            style: Theme.of(context).textTheme.headlineSmall!,
                            child: title,
                          ),
                          const SizedBox(height: 12),
                          content,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: actions,
                  ),
                ],
              ),
            ),
          )
        : AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.all(16),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: title,
            content: content,
            actions: actions,
          );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(requestClose());
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              // Autocomplete delegates Escape here when there are no suggestions.
              // It still belongs to that field, as it did in the modal editor.
              final focused = FocusManager.instance.primaryFocus?.context;
              if (focused
                          ?.findAncestorWidgetOfExactType<
                            FreeTextAutocomplete
                          >() !=
                      null ||
                  focused?.findAncestorWidgetOfExactType<TagInput>() != null) {
                return null;
              }
              unawaited(requestClose());
              return null;
            },
          ),
        },
        child: FocusScope(
          node: _focusScope,
          autofocus: true,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              if (notification.depth == 0 &&
                  notification.metrics.axis == Axis.vertical &&
                  editorViewportHeight !=
                      notification.metrics.viewportDimension) {
                editorViewportHeight = notification.metrics.viewportDimension;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final focused = _focusScope.focusedChild?.context;
                  if (mounted &&
                      !answered &&
                      !closeBusy &&
                      focused != null &&
                      focused.mounted) {
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
            child: presentation,
          ),
        ),
      ),
    );
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
