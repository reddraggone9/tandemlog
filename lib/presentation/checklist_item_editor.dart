import 'package:flutter/material.dart';
import '../application/task_text_session.dart';

class ChecklistItemEditor extends StatefulWidget {
  const ChecklistItemEditor({super.key, this.item, this.textSession, required this.save, this.hasPendingReceipt, this.onClose});
  final Map<String, dynamic>? item;
  final TaskTextSession? textSession;
  final Future<void> Function(String title, String notes) save;
  final bool Function()? hasPendingReceipt;
  final VoidCallback? onClose;
  @override
  ChecklistItemEditorState createState() => ChecklistItemEditorState();
}

class ChecklistItemEditorState extends State<ChecklistItemEditor> {
  Future<bool> canClose() async => false;
  @override
  Widget build(BuildContext context) => const SizedBox();
}
