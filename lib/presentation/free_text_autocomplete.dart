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
  });
  final TextEditingController controller;
  final String label;
  final List<String> values;
  final bool enabled;
  final String? hint, errorText;
  final ValueChanged<String>? onChanged;
  @override
  State<FreeTextAutocomplete> createState() => _FreeTextAutocompleteState();
}

class _FreeTextAutocompleteState extends State<FreeTextAutocomplete> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Autocomplete<String>(
    textEditingController: widget.controller,
    focusNode: _focus,
    optionsBuilder: (value) =>
        !widget.enabled ||
            (value.composing.isValid && !value.composing.isCollapsed)
        ? const Iterable<String>.empty()
        : widget.values.where(
            (option) =>
                option.toLowerCase().contains(value.text.trim().toLowerCase()),
          ),
    fieldViewBuilder: (context, controller, focusNode, submit) => TextField(
      enabled: widget.enabled,
      controller: controller,
      focusNode: focusNode,
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
      onSubmitted: (_) => submit(),
    ),
  );
}
