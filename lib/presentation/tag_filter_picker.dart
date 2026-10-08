import 'package:flutter/material.dart';
import 'tag_input.dart';

/// Filter policy adapter around the shared tag input; search never creates tags.
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

class TagFilterPickerState extends State<TagFilterPicker> {
  final _query = TextEditingController();
  final _input = GlobalKey<TagInputState>();
  bool get dropdownOpen => _input.currentState?.dropdownOpen ?? false;
  bool get hasQuery => _query.text.isNotEmpty;
  bool dismissDropdown() => _input.currentState?.dismissDropdown() ?? false;
  void clearQuery() => _query.clear();
  @override
  Widget build(BuildContext context) => TagInput(
    key: _input,
    tags: widget.tags,
    selected: widget.selected,
    queryController: _query,
    queryLabel: 'Find tags',
    onChanged: widget.onChanged,
    onQueryChanged: widget.onQueryChanged,
    onDropdownChanged: widget.onDropdownChanged,
  );
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }
}
