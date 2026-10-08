import 'package:flutter/material.dart';

/// Reversible UI experiment. No domain or file access; the host editor keeps
/// its existing space-separated controller and validation/save behavior.
class TagEntryTrial extends StatefulWidget {
  const TagEntryTrial({
    super.key,
    required this.controller,
    required this.field,
    required this.label,
    required this.inventory,
    required this.chips,
    required this.enabled,
  });
  final TextEditingController controller;
  final String field, label;
  final List<String> inventory;
  final bool chips, enabled;
  @override
  State<TagEntryTrial> createState() => _TagEntryTrialState();
}

class _TagOption {
  const _TagOption(this.tag, this.source);
  final String tag;
  final TextEditingValue source;
}

class _TagEntryTrialState extends State<TagEntryTrial> {
  final query = TextEditingController();
  final focus = FocusNode();
  List<String> get selected => widget.controller.text
      .trim()
      .split(RegExp(r'\s+'))
      .where((tag) => tag.isNotEmpty)
      .map((tag) => tag.startsWith('#') ? tag.substring(1) : tag)
      .toSet()
      .toList();
  TextEditingController get entry => widget.chips ? query : widget.controller;
  @override
  void initState() {
    super.initState();
    if (const bool.fromEnvironment('TAG_TRIAL_DEMO') &&
        const {'tags', 'addTags'}.contains(widget.field)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await Scrollable.ensureVisible(context, alignment: .85);
        if (!mounted) return;
        focus.requestFocus();
        entry.value = TextEditingValue(
          text: widget.chips || selected.isEmpty
              ? 'ba'
              : '${selected.join(' ')} ba',
          selection: TextSelection.collapsed(
            offset: widget.chips || selected.isEmpty
                ? 2
                : '${selected.join(' ')} ba'.length,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    query.dispose();
    focus.dispose();
    super.dispose();
  }

  (int, int, String) token(TextEditingValue value) {
    final caret = value.selection.isValid
        ? value.selection.baseOffset
        : value.text.length;
    var start = caret, end = caret;
    while (start > 0 && !RegExp(r'\s').hasMatch(value.text[start - 1])) {
      start--;
    }
    while (end < value.text.length &&
        !RegExp(r'\s').hasMatch(value.text[end])) {
      end++;
    }
    return (start, end, value.text.substring(start, caret));
  }

  void choose(String tag, {TextEditingValue? source}) {
    tag = tag.startsWith('#') ? tag.substring(1) : tag;
    if (widget.chips) {
      final tags = [...selected];
      if (!tags.contains(tag)) tags.add(tag);
      widget.controller.text = tags.join(' ');
      query.clear();
    } else {
      final before = source ?? widget.controller.value;
      final (start, end, _) = token(before);
      final text = before.text.replaceRange(start, end, tag);
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: start + tag.length),
      );
    }
    setState(() {});
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      return RawAutocomplete<_TagOption>(
        textEditingController: entry,
        focusNode: focus,
        optionsViewOpenDirection: OptionsViewOpenDirection.up,
        optionsBuilder: (value) {
          final raw = widget.chips ? value.text.trim() : token(value).$3;
          final part = raw.startsWith('#') ? raw.substring(1) : raw;
          if (part.isEmpty) return const <_TagOption>[];
          return widget.inventory
              .where(
                (tag) =>
                    tag.toLowerCase().contains(part.toLowerCase()) &&
                    !selected.contains(tag),
              )
              .take(6)
              .map((tag) => _TagOption(tag, value));
        },
        displayStringForOption: (option) => option.tag,
        onSelected: (option) => choose(option.tag, source: option.source),
        fieldViewBuilder: (context, controller, focus, submit) {
          final input = TextField(
            key: ValueKey('query-${widget.field}'),
            controller: controller,
            focusNode: focus,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: widget.chips ? null : widget.label,
              hintText: widget.chips
                  ? 'Find or add a tag'
                  : 'Separate tags with spaces',
              helperText: widget.chips
                  ? null
                  : 'Up/Down suggestions; Enter selects',
              border: widget.chips ? InputBorder.none : null,
              enabledBorder: widget.chips ? InputBorder.none : null,
              focusedBorder: widget.chips ? InputBorder.none : null,
              filled: !widget.chips,
              contentPadding: widget.chips ? const EdgeInsets.all(0) : null,
            ),
            onSubmitted: (_) {
              submit();
              if (widget.chips && query.text.trim().isNotEmpty) {
                for (final tag in query.text.trim().split(RegExp(r'\s+'))) {
                  choose(tag);
                }
              }
            },
          );
          if (!widget.chips) return input;
          return InputDecorator(
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: 'Enter adds; Up/Down suggestions',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final tag in selected)
                          InputChip(
                            label: Text('#$tag'),
                            onDeleted: widget.enabled
                                ? () => setState(() {
                                    widget.controller.text =
                                        (selected..remove(tag)).join(' ');
                                  })
                                : null,
                          ),
                      ],
                    ),
                  ),
                input,
              ],
            ),
          );
        },
        optionsViewBuilder: (context, choose, options) => Align(
          alignment: Alignment.bottomLeft,
          child: Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: bounds.maxWidth,
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  final tag = option.tag;
                  return ListTile(
                    dense: true,
                    title: Text('#$tag'),
                    selected:
                        AutocompleteHighlightedOption.of(context) == index,
                    onTap: () => choose(option),
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}
