import 'package:flutter/widgets.dart';

/// Physical editor gutters, unaffected by AlertDialog's text-scaled padding.
/// Pass zero horizontal title/content padding to AlertDialog itself.
class EditorDialogGutter extends StatelessWidget {
  const EditorDialogGutter({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );
}
