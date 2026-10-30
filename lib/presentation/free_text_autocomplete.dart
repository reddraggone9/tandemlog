import 'package:flutter/material.dart';

/// Suggestions never constrain or commit the caller-owned free-text draft.
class FreeTextAutocomplete extends StatefulWidget {
  const FreeTextAutocomplete({
    super.key,
    required this.controller,
    required this.label,
    required this.values,
    this.enabled = true,
    this.hint,
    this.errorText,
    this.onChanged,
    this.onSelected,
    this.onSubmitted,
    this.autofocus = false,
    this.matches,
  });
  final TextEditingController controller;
  final String label;
  final List<String> values;
  final bool enabled;
  final String? hint, errorText;
  final ValueChanged<String>? onChanged;

  /// Called after a suggestion replaces the field text.
  final ValueChanged<String>? onSelected;
  final bool autofocus;

  /// Called on Enter only when no suggestion is being accepted.
  final ValueChanged<String>? onSubmitted;

  /// Replaces the default case-insensitive containment match.
  final bool Function(String option, String text)? matches;
  @override
  State<FreeTextAutocomplete> createState() => _FreeTextAutocompleteState();
}

class _FreeTextAutocompleteState extends State<FreeTextAutocomplete> {
  final _focus = FocusNode();
  bool _selectedOnSubmit = false;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Autocomplete<String>(
    textEditingController: widget.controller,
    focusNode: _focus,
    onSelected: (value) {
      _selectedOnSubmit = true;
      widget.onSelected?.call(value);
    },
    optionsBuilder: (value) =>
        !widget.enabled ||
            (value.composing.isValid && !value.composing.isCollapsed)
        ? const Iterable<String>.empty()
        : widget.values.where(
            (option) =>
                widget.matches?.call(option, value.text) ??
                option.toLowerCase().contains(value.text.trim().toLowerCase()),
          ),
    fieldViewBuilder: (context, controller, focusNode, submit) => TextField(
      enabled: widget.enabled,
      controller: controller,
      focusNode: focusNode,
      autofocus: widget.autofocus,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        // A hint is a caller's state message (such as Mixed), not a
        // placeholder, so it stays visible without focus.
        floatingLabelBehavior: widget.hint == null
            ? null
            : FloatingLabelBehavior.always,
        errorText: widget.errorText,
        errorMaxLines: 3,
      ),
      onChanged: widget.onChanged,
      // A suggestion consumes Enter without completing the surrounding form.
      // Keep keyboard/focus for its next Enter; successful form submission
      // closes the dialog. Other autocomplete consumers retain default behavior.
      onEditingComplete: widget.onSubmitted == null ? null : () {},
      onSubmitted: (value) {
        // RawAutocomplete owns Enter while an option is highlighted. Its
        // onSelected callback must not also commit the surrounding dialog.
        _selectedOnSubmit = false;
        submit();
        if (!_selectedOnSubmit) widget.onSubmitted?.call(value);
      },
    ),
  );
}
