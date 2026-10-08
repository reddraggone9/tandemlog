import 'package:flutter/services.dart';

// Input-only normalization preserves historical titles until text is edited.
// Keep platform IME candidates intact until composition finishes.
class TitleLineFormatter extends TextInputFormatter {
  static final breaks = RegExp(r'\r\n|[\r\n\u2028\u2029]');
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    if (oldValue.text == newValue.text &&
        !(oldValue.composing.isValid && !oldValue.composing.isCollapsed)) {
      return newValue;
    }
    if (!breaks.hasMatch(newValue.text)) return newValue;
    int offset(int value) => value < 0
        ? value
        : newValue.text.substring(0, value).replaceAll(breaks, ' ').length;
    return newValue.copyWith(
      text: newValue.text.replaceAll(breaks, ' '),
      selection: TextSelection(
        baseOffset: offset(newValue.selection.baseOffset),
        extentOffset: offset(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }
}
