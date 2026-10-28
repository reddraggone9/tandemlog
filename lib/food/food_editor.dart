import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../presentation/civil_date_input.dart';
import '../presentation/free_text_autocomplete.dart';
import '../presentation/form_validation.dart';
import '../presentation/settled_center_alignment.dart';
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
    this.onRemoveTargets,
    this.onRestoreTargets,
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

  /// Bulk Remove/Restore of the captured targets; each is one Undo action.
  final FutureOr<void> Function(List<FoodContainer>)? onRemoveTargets,
      onRestoreTargets;
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
  late final FormValidation _validation;
  FoodDetails? _attemptDetails;
  int? _attemptAmount;
  List<String>? _attemptFields;
  double? editorViewportHeight;
  // Centered on open; actions stay put while validation text changes.
  final _placement = SettledDialogPlacement();
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
    _validation = FormValidation(
      validate: _issues,
      isComposing: (field) => _composing(_fields[field]!),
    )..addListener(_validationChanged);
    for (final entry in _fields.entries) {
      entry.value.addListener(() => _validation.changed(entry.key));
    }
  }

  Map<String, TextEditingController> get _fields => {
    'name': name,
    'brand': brand,
    'expiry': expiry,
    'size': size,
    'location': location,
    'count': count,
    'retention': retentionQuery,
  };

  void _validationChanged() {
    if (mounted) setState(() {});
  }

  List<FieldIssue> _issues() {
    final issues = <FieldIssue>[];
    final active = bulk
        ? [if (applyBrand) 'brand', if (applyLocation) 'location']
        : [
            'name',
            'brand',
            'expiry',
            'size',
            'location',
            if (widget.group == null) 'count',
            if (widget.group != null) 'retention',
          ];
    for (final field in active) {
      final controller = _fields[field]!;
      if (_composing(controller)) {
        issues.add(FieldIssue(field, 'Finish composing text before saving.'));
        continue;
      }
      final value = controller.text.trim();
      if (field == 'count') {
        final amount = int.tryParse(controller.text);
        if (amount == null || amount < 1 || amount > 100) {
          issues.add(
            const FieldIssue('count', 'Add 1 to 100 containers at a time.'),
          );
        }
        continue;
      }
      if (field == 'expiry' && value.isEmpty) {
        issues.add(const FieldIssue('expiry', 'Expiration is required.'));
        continue;
      }
      if (bulk &&
          value.isEmpty &&
          !(field == 'brand' ? clearBrand : clearLocation)) {
        issues.add(
          FieldIssue(
            field,
            field == 'brand'
                ? 'Use Clear Brand to remove a value.'
                : 'Use Clear Location to remove a value.',
          ),
        );
        continue;
      }
      final text = field == 'retention' && value.isEmpty ? retention : value;
      try {
        FoodDetails(
          name: field == 'name' ? text : 'Validation',
          brand: field == 'brand' ? text : '',
          expiry: field == 'expiry' ? text : null,
          size: field == 'size' ? text : '',
          location: field == 'location' ? text : '',
          retention: field == 'retention' ? text : '',
        ).validate();
      } on FormatException catch (failure) {
        const labels = {
          'name': 'Food name',
          'brand': 'Brand',
          'location': 'Location',
          'size': 'Container size',
          'retention': 'Retention reason',
        };
        final limit = field == 'name' ? 500 : 200;
        final message = field == 'name' && value.isEmpty
            ? 'Enter a food name.'
            : field != 'expiry' && text.length > limit
            ? '${labels[field]} must be $limit characters or fewer.'
            : failure.message.toString();
        issues.add(FieldIssue(field, message));
      }
    }
    return issues;
  }

  FoodDetails _details() => FoodDetails(
    name: name.text.trim(),
    brand: bulk && !applyBrand ? original!.brand : brand.text.trim(),
    expiry: bulk ? original!.expiry : expiry.text.trim(),
    estimated: estimated,
    retention: widget.group == null && !bulk
        ? ''
        : retentionQuery.text.trim().isEmpty
        ? retention
        : retentionQuery.text.trim(),
    size: size.text.trim(),
    location: bulk && !applyLocation
        ? original!.location
        : location.text.trim(),
  );

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
    _validation.dispose();
    expiryFocus.dispose();
    _focusScope.dispose();
    _scroll.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    widget.onDisposed();
    super.dispose();
  }

  Future<void> _save() async {
    if (!mounted) return;
    final group = widget.group, targets = widget.targets;
    final add = widget.onAdd, changeDetails = widget.onDetails;
    final dialogContext = context;
    final setDialog = setState;

    if (!mounted || closeBusy || deciding) {
      return;
    }
    try {
      final retry = pending();
      if (!retry && !await _validation.reviewAndReveal()) return;
      if (!mounted || closeBusy || deciding) return;
      if (retry && (_attemptDetails == null || _attemptAmount == null)) {
        throw const FormatException(
          'The earlier save must be retried from Food.',
        );
      }
      final details = retry ? _attemptDetails! : _details();
      final amount = retry ? _attemptAmount! : int.parse(count.text);
      if (!retry) details.validate();
      if (!widget.isOriginCurrent()) {
        throw FormatException(
          bulk
              ? 'The selected containers changed. Close this editor and select again.'
              : 'The food workspace or containers changed. Close this editor and select again.',
        );
      }
      if (!retry) {
        _attemptDetails = details;
        _attemptAmount = amount;
      }
      setDialog(() {
        saving = true;
        error = null;
      });
      if (bulk) {
        if (!pending() && !widget.areTargetsVisible()) {
          throw const FormatException(
            'The selected containers changed. Close this editor and select again.',
          );
        }
        final fields = retry
            ? _attemptFields!
            : [
                if (applyBrand &&
                    targets!.any((e) => e.details.brand != details.brand))
                  'brand',
                if (applyLocation &&
                    targets!.any((e) => e.details.location != details.location))
                  'location',
              ];
        if (!retry) _attemptFields = List.unmodifiable(fields);
        if (fields.isNotEmpty) {
          await changeDetails(targets!, details, fields);
        }
        if (mounted) widget.onBulkApplied();
      } else if (group == null) {
        await add(details, amount);
      } else {
        final before = original!.toJson(), after = details.toJson();
        final fields = retry
            ? _attemptFields!
            : after.keys
                  .where(
                    (key) => key != 'estimated' && before[key] != after[key],
                  )
                  .toList();
        if (!retry) _attemptFields = List.unmodifiable(fields);
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
  }

  /// Removes the selected active containers, or restores the selected
  /// deleted ones, as one host command and therefore one Undo action.
  Future<void> _bulkCommand(bool remove) async {
    final command = remove ? widget.onRemoveTargets : widget.onRestoreTargets;
    final items = widget.targets!.where((e) => e.deleted != remove).toList();
    if (command == null ||
        items.isEmpty ||
        closeBusy ||
        deciding ||
        pending()) {
      return;
    }
    if (remove) {
      bool? confirmed;
      deciding = true;
      try {
        final noun = items.length == 1 ? 'container' : 'containers';
        confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final decide = _answerOnce<bool>(ctx);
            return AlertDialog(
              title: Text('Remove ${items.length} $noun?'),
              content: const Text(
                'You can restore these containers from Deleted.',
              ),
              actions: [
                TextButton(
                  onPressed: () => decide(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => decide(true),
                  child: const Text('Remove'),
                ),
              ],
            );
          },
        );
      } finally {
        deciding = false;
      }
      if (confirmed != true || !mounted || answered) return;
    }
    try {
      if (!widget.isOriginCurrent() || !widget.areTargetsVisible()) {
        throw const FormatException(
          'The selected containers changed. Close this editor and select again.',
        );
      }
      setState(() {
        saving = true;
        error = null;
      });
      await command(items);
      if (!mounted) return;
      widget.onBulkApplied();
      saving = false;
      answer(context, null);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is FormatException ? e.message : e.toString();
        });
      }
    } finally {
      if (mounted) widget.onReadinessChanged?.call();
    }
  }

  Widget _failureNotice() => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight:
          ((MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom) *
                  .2)
              .clamp(40.0, 120.0),
    ),
    child: SingleChildScrollView(
      child: Semantics(
        liveRegion: true,
        child: Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    _focusScope.traversalEdgeBehavior = widget.panel
        ? TraversalEdgeBehavior.parentScope
        : TraversalEdgeBehavior.closedLoop;
    final group = widget.group,
        template = widget.template,
        targets = widget.targets;
    final setDialog = setState;
    final cancel = requestClose;
    final title = Text(
      bulk
          ? 'Edit ${targets!.length} ${targets.length == 1 ? 'container' : 'containers'}'
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
                        _validation.changed(field.toLowerCase());
                      }),
              ),
              Row(
                children: [
                  Expanded(
                    child: _validation.field(
                      field.toLowerCase(),
                      FreeTextAutocomplete(
                        errorText: _validation.errorFor(field.toLowerCase()),
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
                          _validation.changed(field.toLowerCase());
                        }),
                      ),
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
                            _validation.changed(field.toLowerCase());
                          }),
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ] else ...[
            _validation.field(
              'name',
              TextField(
                enabled: !saving && !pending(),
                controller: name,
                autofocus: template == null,
                decoration: InputDecoration(
                  labelText: 'Food name',
                  errorText: _validation.errorFor('name'),
                  errorMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _validation.field(
              'brand',
              FreeTextAutocomplete(
                errorText: _validation.errorFor('brand'),
                enabled: !saving && !pending(),
                controller: brand,
                label: 'Brand',
                values: widget.state.brands,
              ),
            ),
            const SizedBox(height: 12),
            _validation.field(
              'expiry',
              CivilDateInput(
                errorText: _validation.errorFor('expiry'),
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
            ),
            const SizedBox(height: 12),
            _validation.field(
              'size',
              TextField(
                enabled: !saving && !pending(),
                controller: size,
                decoration: InputDecoration(
                  errorText: _validation.errorFor('size'),
                  errorMaxLines: 3,
                  labelText: 'Container size',
                  hintText: 'e.g. 1 lb',
                ),
              ),
            ),
            const SizedBox(height: 12),
            _validation.field(
              'location',
              FreeTextAutocomplete(
                errorText: _validation.errorFor('location'),
                enabled: !saving && !pending(),
                controller: location,
                label: 'Location',
                values: widget.state.locations,
              ),
            ),
            if (group == null) ...[
              const SizedBox(height: 12),
              _validation.field(
                'count',
                TextField(
                  enabled: !saving && !pending(),
                  controller: count,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    errorText: _validation.errorFor('count'),
                    errorMaxLines: 3,
                    labelText: 'Containers to add',
                    helperText: 'Creates a separate container for each one',
                    helperMaxLines: 2,
                  ),
                ),
              ),
            ],
            if (group != null) ...[
              const SizedBox(height: 12),
              _validation.field(
                'retention',
                TagInput(
                  queryErrorText: _validation.errorFor('retention'),
                  enabled: !saving && !pending(),
                  tags: widget.state.reasons,
                  selected: retention.isEmpty ? {} : {retention},
                  queryController: retentionQuery,
                  onDropdownChanged: (_) {},
                  allowCreate: true,
                  canSubmitQuery: () =>
                      retentionQuery.text.trim().length <= 200,
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
                      _validation.blur('retention');
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
              ),
            ],
          ],
        ],
      ),
    );
    final cancelAction = TextButton(
      onPressed: saving ? null : cancel,
      child: const Text('Cancel'),
    );
    final saveAction = ValidationActionButton(
      buttonKey: const ValueKey('food-save-action'),
      validation: _validation,
      label: !bulk && group == null ? 'Add' : 'Save',
      busy: saving,
      enabled: !closeBusy && !deciding,
      retry: pending(),
      retryLabel: 'Retry save',
      onSubmit: _save,
    );
    // Like Tasks' bulk Delete, whole-selection commands sit opposite Save.
    final bulkActions = [
      if (bulk &&
          widget.onRestoreTargets != null &&
          targets!.any((e) => e.deleted))
        TextButton(
          key: const ValueKey('food-bulk-restore'),
          onPressed: saving || pending() ? null : () => _bulkCommand(false),
          child: const Text('Restore'),
        ),
      if (bulk &&
          widget.onRemoveTargets != null &&
          targets!.any((e) => !e.deleted))
        TextButton(
          key: const ValueKey('food-bulk-remove'),
          onPressed: saving || pending() ? null : () => _bulkCommand(true),
          child: const Text('Remove'),
        ),
    ];
    final actions = bulkActions.isEmpty
        ? [cancelAction, saveAction]
        : [
            // Narrow, enlarged-text dialogs wrap Cancel/Save onto a second row
            // rather than squeezing them.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 4,
              children: [
                Wrap(spacing: 8, children: bulkActions),
                Wrap(spacing: 8, children: [cancelAction, saveAction]),
              ],
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
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _failureNotice(),
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
            alignment: _placement.alignmentFor(context),
            scrollable: true,
            insetPadding: const EdgeInsets.all(16),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: title,
            content: content,
            actions: [if (error != null) _failureNotice(), ...actions],
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
