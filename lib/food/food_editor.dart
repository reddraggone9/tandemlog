import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../presentation/bulk_apply.dart';
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

  /// Container fields plus product changes of one Save (one Undo action).
  final FutureOr<void> Function(
    List<FoodContainer>,
    FoodDetails,
    List<String>,
    FoodProductChange,
  )
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
      retentionQuery,
      link,
      minimum;
  late final FoodDetails? original;

  /// The edited row's product (single-row Edit only).
  late final FoodProductSummary? product;
  late final bool? estimated;
  late String retention;
  late final String initial;

  /// Bulk editing writes only applied fields; mixed fields start blank.
  static const bulkFields = ['name', 'brand', 'size', 'location', 'retention'];

  /// Name, Brand and Container size describe the product (decision 2).
  static const productFields = {'name', 'brand', 'size'};
  final applied = <String>{}, mixed = <String>{};
  var answered = false, saving = false, deciding = false, auxiliaryOpen = false;
  Future<bool>? closeRequest;
  (FoodDetails, int)? _completedSave;
  String? error;
  late final FormValidation _validation;
  FoodDetails? _attemptDetails;
  int? _attemptAmount;
  List<String>? _attemptFields;
  FoodProductChange? _attemptProducts;
  // Selected rows follow their current containers until Save; a retry of a
  // pending save keeps the containers the first attempt sent.
  List<FoodContainer>? _attemptTargets;
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

  /// The targets' shared value, or blank and mixed when they disagree.
  String _common(String field) {
    final values = widget.targets!
        .map((e) => e.details.toJson()[field] as String)
        .toSet();
    if (values.length == 1) return values.single;
    mixed.add(field);
    return '';
  }

  List<TextEditingController> get _controllers => [
    name,
    brand,
    expiry,
    size,
    location,
    count,
    retentionQuery,
    link,
    minimum,
  ];
  String snapshot() => jsonEncode([
    for (final controller in _controllers) controller.text,
    retention,
    estimated,
    [...applied]..sort(),
  ]);
  @override
  void initState() {
    super.initState();
    original = bulk
        ? widget.targets!.first.details
        : widget.group?.details ?? widget.template;
    String start(String field, String single) => bulk ? _common(field) : single;
    name = TextEditingController(text: start('name', original?.name ?? ''));
    brand = TextEditingController(text: start('brand', original?.brand ?? ''));
    expiry = TextEditingController(
      text: widget.template == null ? original?.expiry ?? '' : '',
    );
    size = TextEditingController(text: start('size', original?.size ?? ''));
    location = TextEditingController(
      text: start('location', original?.location ?? ''),
    );
    count = TextEditingController(text: '1');
    retentionQuery = TextEditingController();
    product = !bulk && widget.group != null
        ? widget.state.products[widget.group!.product]
        : null;
    link = TextEditingController(text: product?.links.firstOrNull ?? '');
    minimum = TextEditingController(text: product?.minimum?.toString() ?? '');
    retention = start(
      'retention',
      widget.template == null ? original?.retention ?? '' : '',
    );
    estimated = widget.template == null ? original?.estimated : null;
    initial = snapshot();
    _validation = FormValidation(
      validate: _issues,
      isComposing: (field) => _composing(_fields[field]!),
    )..addListener(_validationChanged);
    for (final entry in _fields.entries) {
      entry.value.addListener(() => _validation.changed(entry.key));
    }
    if (bulk) {
      // As in the Tasks bulk editor, editing a field applies it. Focus and
      // caret notifications leave the text unchanged and apply nothing.
      for (final field in bulkFields) {
        final controller = _fields[field]!;
        var previous = controller.text;
        controller.addListener(() {
          if (controller.text == previous) return;
          previous = controller.text;
          _apply(field);
        });
      }
    }
  }

  void _apply(String field) {
    if (bulk && mounted && applied.add(field)) setState(() {});
  }

  Map<String, TextEditingController> get _fields => {
    'name': name,
    'brand': brand,
    'expiry': expiry,
    'size': size,
    'location': location,
    'count': count,
    'retention': retentionQuery,
    'link': link,
    'minimum': minimum,
  };

  void _validationChanged() {
    if (mounted) setState(() {});
  }

  List<FieldIssue> _issues() {
    final issues = <FieldIssue>[];
    final active = bulk
        ? bulkFields.where(applied.contains).toList()
        : [
            'name',
            'brand',
            'expiry',
            'size',
            'location',
            if (widget.group == null) 'count',
            if (widget.group != null) 'retention',
            if (product != null) ...['link', 'minimum'],
          ];
    for (final field in active) {
      final controller = _fields[field]!;
      if (_composing(controller)) {
        issues.add(FieldIssue(field, 'Finish composing text before saving.'));
        continue;
      }
      final value = controller.text.trim();
      if (field == 'link') {
        if (value.isNotEmpty && !isFoodStoreLink(value)) {
          issues.add(
            const FieldIssue('link', 'Enter a web address starting https://'),
          );
        }
        continue;
      }
      if (field == 'minimum') {
        final amount = int.tryParse(value);
        if (value.isNotEmpty &&
            (amount == null || amount < 0 || amount > maximumProductMinimum)) {
          issues.add(
            const FieldIssue('minimum', 'Enter 0 to 999, or leave blank.'),
          );
        }
        continue;
      }
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

  // In bulk edits, unapplied fields carry the first target's value; Save
  // names only applied fields, so other targets keep their own values.
  FoodDetails _details() {
    String value(String field, String draft) => bulk && !applied.contains(field)
        ? original!.toJson()[field] as String
        : draft;
    return FoodDetails(
      name: value('name', name.text.trim()),
      brand: value('brand', brand.text.trim()),
      expiry: bulk ? original!.expiry : expiry.text.trim(),
      estimated: estimated,
      retention: widget.group == null && !bulk
          ? ''
          : value(
              'retention',
              retentionQuery.text.trim().isEmpty
                  ? retention
                  : retentionQuery.text.trim(),
            ),
      size: value('size', size.text.trim()),
      location: value('location', location.text.trim()),
    );
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

  bool _replacementDecision = false;

  Future<bool> requestClose({bool close = true}) {
    // A discard decision for replacement is not a close acknowledgement.
    // Section/exit requests must retry after readiness rather than wait for an
    // editor that deliberately remains mounted through this decision.
    if (_replacementDecision || (!close && closeRequest != null)) {
      return Future.value(false);
    }
    _replacementDecision = !close;
    return closeRequest ??= _decideClose(close: close).whenComplete(() {
      closeRequest = null;
      _replacementDecision = false;
      widget.onReadinessChanged?.call();
    });
  }

  Future<bool> _decideClose({required bool close}) async {
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
    if (!close) return true;
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
        final items = retry ? _attemptTargets! : targets!;
        final after = details.toJson();
        final changed = [
          for (final field in bulkFields)
            if (applied.contains(field) &&
                items.any((e) => e.details.toJson()[field] != after[field]))
              field,
        ];
        final fields = retry
            ? _attemptFields!
            : changed.where((f) => !productFields.contains(f)).toList();
        final products = retry
            ? _attemptProducts!
            : _bulkProductChange(details);
        if (!retry) {
          _attemptFields = List.unmodifiable(fields);
          _attemptProducts = products;
          _attemptTargets = items;
        }
        if (fields.isNotEmpty || !products.isEmpty) {
          await changeDetails(items, details, fields, products);
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
                    (key) =>
                        key != 'estimated' &&
                        !productFields.contains(key) &&
                        before[key] != after[key],
                  )
                  .toList();
        final products = retry ? _attemptProducts! : _productChange(details);
        final items = retry ? _attemptTargets! : group.containers;
        if (!retry) {
          _attemptFields = List.unmodifiable(fields);
          _attemptProducts = products;
          _attemptTargets = items;
        }
        if (fields.isNotEmpty || !products.isEmpty) {
          await changeDetails(items, details, fields, products);
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

  /// Existing products as "Name · Brand · Size" suggestions for Add.
  late final Map<String, FoodProductSummary> _productOptions = {
    for (final p
        in widget.state.products.values.toList()
          ..sort((a, b) => b.containers.compareTo(a.containers)))
      [p.name, p.brand, p.size].where((v) => v.isNotEmpty).join(' · '): p,
  };

  /// Changed product fields of the single-row editor.
  FoodProductChange _productChange(FoodDetails details) {
    final current = product;
    if (current == null) return const FoodProductChange();
    final before = original!.toJson(), after = details.toJson();
    final changes = <String, Object?>{
      for (final field in productFields)
        if (before[field] != after[field]) field: after[field],
    };
    final typed = link.text.trim();
    final links = [
      if (typed.isNotEmpty) typed,
      ...current.links.skip(1).where((l) => l != typed),
    ];
    if (jsonEncode(links) != jsonEncode(current.links)) {
      changes['links'] = links;
    }
    final keep = int.tryParse(minimum.text.trim());
    if (keep != current.minimum) changes['minimum'] = keep;
    return FoodProductChange(roots: [current.id], changes: changes);
  }

  /// Applied Name/Brand/Container size change the selected products.
  FoodProductChange _bulkProductChange(FoodDetails details) {
    final after = details.toJson();
    final changes = <String, Object?>{
      for (final field in productFields)
        if (applied.contains(field) &&
            widget.targets!.any(
              (e) => e.details.toJson()[field] != after[field],
            ))
          field: after[field],
    };
    return FoodProductChange(
      roots: {for (final e in widget.targets!) e.product}.toList(),
      changes: changes,
    );
  }

  /// "Also changes N other containers" or the merge this Save makes.
  String? _scope() {
    final state = widget.state;
    if (bulk) {
      final change = _bulkProductChange(_details());
      if (change.isEmpty) return null;
      final steps = planFoodProductChanges(state, change.roots, change.changes);
      final merged = <String>{
        for (final step in steps)
          if (step is FoodProductMerge) ...[step.source, step.into],
      };
      final selected = widget.targets!.map((e) => e.id).toSet();
      final affected = {...change.roots, ...merged};
      final containers = [
        for (final c in state.containers)
          if (affected.contains(c.product)) c,
      ];
      if (merged.isNotEmpty) {
        return 'Merges ${merged.length} products, ${containers.length} '
            '${containers.length == 1 ? 'container' : 'containers'}';
      }
      final others = containers.where((c) => !selected.contains(c.id)).length;
      return others == 0
          ? null
          : 'Also changes $others other ${others == 1 ? 'container' : 'containers'}';
    }
    final current = product;
    if (current == null) return null;
    final key = foodDescriptionKey(name.text, brand.text, size.text);
    final into = state.productsByDescription[key]
        ?.where((p) => p.id != current.id)
        .firstOrNull;
    if (into != null) {
      return 'Merges with ${into.containers} '
          '${into.containers == 1 ? 'container' : 'containers'} of ${into.name}';
    }
    final mine = widget.group!.containers.map((e) => e.id).toSet();
    final others = state.containers
        .where((c) => c.product == current.id && !mine.contains(c.id))
        .length;
    return others == 0
        ? null
        : 'Also changes $others other ${others == 1 ? 'container' : 'containers'}';
  }

  /// "Last \$3.48 · Walmart · Oct 20 · typical \$3.30" (decision 10).
  String? _priceLine() {
    final last = product?.last;
    if (last == null) return null;
    final typical = product!.typicalUnitCost(DateTime.now());
    final date = DateTime.parse(last.date);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return [
      'Last ${foodMoney(last.unitCost, last.currency)}',
      if (last.store.isNotEmpty) last.store,
      '${months[date.month - 1]} ${date.day}',
      if (typical != null) 'typical ${foodMoney(typical, last.currency)}',
    ].join(' · ');
  }

  Widget _secondary(String text, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

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

  static const _labels = {
    'name': 'Food name',
    'brand': 'Brand',
    'size': 'Container size',
    'location': 'Location',
    'retention': 'Retention reason',
  };

  /// Bulk fields get the shared Apply control beside their input.
  Widget _bulkApply(String field, Widget input) => !bulk
      ? input
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BulkApplyCheckbox(
              checkboxKey: ValueKey('${field}Apply'),
              label: _labels[field]!,
              value: applied.contains(field),
              onChanged: saving || pending()
                  ? null
                  : (value) => setState(() {
                      if (value) {
                        applied.add(field);
                      } else {
                        applied.remove(field);
                      }
                      _validation.blur(field);
                    }),
            ),
            Expanded(child: input),
          ],
        );

  String? _hint(String field, [String? hint]) =>
      mixed.contains(field) ? bulkMixedHint : hint;

  // Mixed is state, not a placeholder: keep it visible without focus.
  FloatingLabelBehavior? _floatMixed(String field) =>
      mixed.contains(field) ? FloatingLabelBehavior.always : null;

  Widget _input(String field) {
    final enabled = !saving && !pending();
    return switch (field) {
      // Add suggests existing products; picking one fills Brand and size.
      'name' when !bulk && widget.group == null => FreeTextAutocomplete(
        errorText: _validation.errorFor('name'),
        enabled: enabled,
        controller: name,
        autofocus: widget.template == null,
        label: 'Food name',
        values: _productOptions.keys.toList(),
        // Once the typed name is a product's exact name there is nothing
        // left to suggest; the overlay would only cover the next fields.
        matches: (option, text) {
          final typed = text.trim().toLowerCase();
          return typed.isNotEmpty &&
              option.toLowerCase().contains(typed) &&
              _productOptions[option]!.name.toLowerCase() != typed;
        },
        onSelected: (option) {
          final picked = _productOptions[option];
          if (picked == null) return;
          name.text = picked.name;
          brand.text = picked.brand;
          size.text = picked.size;
        },
      ),
      'name' => TextField(
        enabled: enabled,
        controller: name,
        autofocus: widget.template == null && !bulk,
        decoration: InputDecoration(
          labelText: 'Food name',
          hintText: _hint('name'),
          floatingLabelBehavior: _floatMixed('name'),
          errorText: _validation.errorFor('name'),
          errorMaxLines: 3,
        ),
      ),
      'link' => TextField(
        key: const ValueKey('food-store-link'),
        enabled: enabled,
        controller: link,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: 'Store link',
          errorText: _validation.errorFor('link'),
          errorMaxLines: 3,
          suffixIcon: ListenableBuilder(
            listenable: link,
            builder: (context, _) => IconButton(
              tooltip: 'Open store link',
              onPressed: isFoodStoreLink(link.text.trim())
                  ? () => launchUrl(
                      Uri.parse(link.text.trim()),
                      mode: LaunchMode.externalApplication,
                    )
                  : null,
              icon: const Icon(Icons.open_in_new),
            ),
          ),
        ),
      ),
      'minimum' => TextField(
        key: const ValueKey('food-keep-at-least'),
        enabled: enabled,
        controller: minimum,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Keep at least',
          errorText: _validation.errorFor('minimum'),
          errorMaxLines: 3,
        ),
      ),
      'brand' => FreeTextAutocomplete(
        errorText: _validation.errorFor('brand'),
        enabled: enabled,
        controller: brand,
        label: 'Brand',
        hint: _hint('brand'),
        values: widget.state.brands,
      ),
      'expiry' => CivilDateInput(
        errorText: _validation.errorFor('expiry'),
        enabled: enabled,
        controller: expiry,
        isOwnerMounted: () => mounted && !answered,
        onPickerChanged: (open) {
          auxiliaryOpen = open;
          if (!open) _finishAcceptedSave();
          widget.onReadinessChanged?.call();
        },
        fieldKey: const ValueKey('food-expiration'),
        focusNode: expiryFocus,
        autofocus: widget.template != null,
        label: 'Expiration',
      ),
      'size' => TextField(
        enabled: enabled,
        controller: size,
        decoration: InputDecoration(
          errorText: _validation.errorFor('size'),
          errorMaxLines: 3,
          labelText: 'Container size',
          hintText: _hint('size', 'e.g. 1 lb'),
          floatingLabelBehavior: _floatMixed('size'),
        ),
      ),
      'location' => FreeTextAutocomplete(
        errorText: _validation.errorFor('location'),
        enabled: enabled,
        controller: location,
        label: 'Location',
        hint: _hint('location'),
        values: widget.state.locations,
      ),
      'count' => TextField(
        enabled: enabled,
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
      _ => TagInput(
        queryErrorText: _validation.errorFor('retention'),
        enabled: enabled,
        tags: widget.state.reasons,
        selected: retention.isEmpty ? {} : {retention},
        queryController: retentionQuery,
        onDropdownChanged: (_) {},
        allowCreate: true,
        canSubmitQuery: () => retentionQuery.text.trim().length <= 200,
        clearQueryOnSelection: true,
        queryLabel: 'Retention reason',
        // The hint is this field's only visible label, so keep its name.
        hint: mixed.contains('retention')
            ? 'Retention reason — Mixed'
            : 'Retention reason',
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
          setState(() => retention = text);
          _apply('retention');
          retentionQuery.clear();
          return true;
        },
        onChanged: (next) {
          setState(
            () => retention = next.difference({retention}).firstOrNull ?? '',
          );
          _apply('retention');
        },
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    _focusScope.traversalEdgeBehavior = widget.panel
        ? TraversalEdgeBehavior.parentScope
        : TraversalEdgeBehavior.closedLoop;
    final group = widget.group, targets = widget.targets;
    final cancel = requestClose;
    final prices = _priceLine();
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
          for (final (index, field) in [
            'name',
            'brand',
            if (!bulk) 'expiry',
            'size',
            if (product != null) ...['link', 'minimum'],
            'location',
            if (!bulk && group == null) 'count',
            if (bulk || group != null) 'retention',
          ].indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            _validation.field(field, _bulkApply(field, _input(field))),
            if (field == 'size' && (bulk || product != null))
              // Follows the draft: typing another product's name says merge.
              ListenableBuilder(
                listenable: Listenable.merge([name, brand, size]),
                builder: (context, _) {
                  final scope = _scope();
                  return scope == null
                      ? const SizedBox.shrink()
                      : _secondary(
                          scope,
                          key: const ValueKey('food-product-scope'),
                        );
                },
              ),
            if (field == 'minimum' && prices != null)
              _secondary(prices, key: const ValueKey('food-product-prices')),
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
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 4,
                children: [
                  Wrap(spacing: 8, children: bulkActions),
                  Wrap(spacing: 8, children: [cancelAction, saveAction]),
                ],
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
              // Food name keeps closing the editor as before it suggested
              // products; open suggestions consume Escape themselves.
              final focused = FocusManager.instance.primaryFocus?.context;
              final autocomplete = focused
                  ?.findAncestorWidgetOfExactType<FreeTextAutocomplete>();
              if ((autocomplete != null &&
                      !identical(autocomplete.controller, name)) ||
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
