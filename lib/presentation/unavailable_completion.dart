import 'package:flutter/material.dart';

import 'task_completion_checkbox.dart';

/// An unavailable-looking checkbox whose reason remains reachable by touch,
/// hover, keyboard focus and assistive technology. It never completes a task.
class UnavailableCompletion extends StatefulWidget {
  const UnavailableCompletion({
    super.key,
    required this.reason,
    required this.title,
    required this.onExplain,
    this.repeating = false,
  });
  final String reason;
  final String title;
  final VoidCallback onExplain;
  final bool repeating;

  @override
  State<UnavailableCompletion> createState() => _UnavailableCompletionState();
}

class _UnavailableCompletionState extends State<UnavailableCompletion> {
  final tooltip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Completion unavailable for ${widget.title}. ${widget.reason}',
    button: true,
    child: Tooltip(
      key: tooltip,
      message: widget.reason,
      excludeFromSemantics: true,
      child: InkWell(
        onTap: widget.onExplain,
        onFocusChange: (focused) {
          if (focused) tooltip.currentState?.ensureTooltipVisible();
        },
        customBorder: const CircleBorder(),
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: TaskCompletionCheckbox(
              repeating: widget.repeating,
              value: false,
              onChanged: null,
            ),
          ),
        ),
      ),
    ),
  );
}
