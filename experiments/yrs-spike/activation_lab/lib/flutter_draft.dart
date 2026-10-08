// Controller adapter only; this experiment creates no platform UI.
import 'package:flutter/widgets.dart';
import 'activation.dart';

class LabDraftController extends TextEditingController {
  LabDraftController(this.draft)
    : super.fromValue(
        TextEditingValue(
          text: draft.value.text,
          selection: TextSelection(
            baseOffset: draft.value.selectionStart,
            extentOffset: draft.value.selectionEnd,
          ),
          composing: TextRange(
            start: draft.value.composingStart,
            end: draft.value.composingEnd,
          ),
        ),
      ) {
    addListener(_changed);
  }
  final LabDraft draft;
  void _changed() => draft.change(
    DraftValue(
      value.text,
      selectionStart: value.selection.baseOffset,
      selectionEnd: value.selection.extentOffset,
      composingStart: value.composing.start,
      composingEnd: value.composing.end,
    ),
  );
}
