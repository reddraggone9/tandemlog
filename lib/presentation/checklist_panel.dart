import 'package:flutter/material.dart';

class ChecklistPanel extends StatelessWidget {
  const ChecklistPanel({super.key, required this.items, required this.onAdd, required this.onEdit, required this.onToggle, required this.onMove, required this.onDelete, this.enabled = true});
  final List<Map<String, dynamic>> items;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>, bool) onToggle;
  final void Function(Map<String, dynamic>, String?) onMove;
  final void Function(Map<String, dynamic>) onDelete;
  final bool enabled;
  @override
  Widget build(BuildContext context) => const SizedBox();
}
