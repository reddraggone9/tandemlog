import 'package:flutter/material.dart';

/// Common section actions retain their icon metrics and comfortable targets.
Widget toolbarAction({
  Key? key,
  required bool compact,
  required String tooltip,
  required Widget icon,
  required VoidCallback? onPressed,
  String? label,
  double iconSize = 20,
}) {
  final glyph = IconTheme.merge(
    data: IconThemeData(size: iconSize),
    child: icon,
  );
  return compact
      ? IconButton(
          key: key,
          tooltip: tooltip,
          onPressed: onPressed,
          iconSize: iconSize,
          visualDensity: VisualDensity.standard,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: glyph,
        )
      : Tooltip(
          message: tooltip,
          child: OutlinedButton.icon(
            key: key,
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              visualDensity: VisualDensity.standard,
            ),
            icon: glyph,
            label: Text(label!),
          ),
        );
}

/// Popup menus own input/focus; their trigger shares the action icon policy.
Widget toolbarMenuAction<T>({
  Key? key,
  required BuildContext context,
  required bool compact,
  required String tooltip,
  required Widget icon,
  required String label,
  required PopupMenuItemBuilder<T> itemBuilder,
  required ValueChanged<T> onSelected,
  bool enabled = true,
}) => PopupMenuButton<T>(
  key: key,
  tooltip: tooltip,
  enabled: enabled,
  onSelected: onSelected,
  itemBuilder: itemBuilder,
  iconSize: 20,
  iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
  style: IconButton.styleFrom(
    minimumSize: const Size(48, 48),
    visualDensity: VisualDensity.standard,
  ),
  icon: compact
      ? IconTheme.merge(data: const IconThemeData(size: 20), child: icon)
      : null,
  child: compact
      ? null
      : Semantics(
          button: true,
          enabled: enabled,
          child: ExcludeFocus(
            child: ExcludeSemantics(
              child: IgnorePointer(
                // The native popup owns one focus/semantics/tap target. Reuse
                // the outlined action only as its visual trigger.
                child: toolbarAction(
                  compact: false,
                  tooltip: '',
                  icon: icon,
                  label: label,
                  onPressed: enabled ? () {} : null,
                ),
              ),
            ),
          ),
        ),
);

Widget toolbarProgress({required bool busy}) => RepaintBoundary(
  child: SizedBox(
    height: 2,
    child: busy ? const LinearProgressIndicator(minHeight: 2) : null,
  ),
);

Widget toolbarFilterIcon({required bool active}) =>
    Badge(isLabelVisible: active, child: const Icon(Icons.filter_list));
