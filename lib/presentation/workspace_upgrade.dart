import 'package:flutter/material.dart';

import '../domain/event.dart' show isCanonicalId;
import '../storage/workspace_upgrade.dart';

/// Explicit preparation separates historical ownership from the installations
/// that must really acknowledge this upgrade. A log is not proof of a device
/// being online or stopped.
class WorkspaceUpgradeChoice {
  const WorkspaceUpgradeChoice(this.participants, this.knownOwners);
  final Set<String> participants, knownOwners;
}

class WorkspaceUpgradeDialog extends StatefulWidget {
  const WorkspaceUpgradeDialog({
    super.key,
    required this.writer,
    required this.inventory,
    required this.inspect,
  });
  final String writer;
  final WorkspaceUpgradeInventory inventory;
  final Future<WorkspaceUpgradeInventory> Function(Set<String>) inspect;

  @override
  State<WorkspaceUpgradeDialog> createState() => _WorkspaceUpgradeDialogState();
}

class _WorkspaceUpgradeDialogState extends State<WorkspaceUpgradeDialog> {
  late WorkspaceUpgradeInventory inventory = widget.inventory;
  late final selected = <String>{widget.writer};
  final ownerIds = TextEditingController();
  final deviceIds = TextEditingController();
  final deviceIdsFocus = FocusNode();
  final ownerIdsFocus = FocusNode();
  double? _viewportExtent;
  bool _idsRevealQueued = false;

  @override
  void initState() {
    super.initState();
    deviceIdsFocus.addListener(_queueFocusedIdsReveal);
    ownerIdsFocus.addListener(_queueFocusedIdsReveal);
  }

  void _queueFocusedIdsReveal() {
    if (!mounted ||
        answered ||
        _idsRevealQueued ||
        MediaQuery.viewInsetsOf(context).bottom == 0 ||
        (!deviceIdsFocus.hasFocus && !ownerIdsFocus.hasFocus)) {
      return;
    }
    _idsRevealQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _idsRevealQueued = false;
      if (!mounted ||
          answered ||
          checking ||
          ModalRoute.isCurrentOf(context) != true ||
          MediaQuery.viewInsetsOf(context).bottom == 0) {
        return;
      }
      final focus = deviceIdsFocus.hasFocus
          ? deviceIdsFocus
          : ownerIdsFocus.hasFocus
          ? ownerIdsFocus
          : null;
      final editable = focus?.context
          ?.findAncestorStateOfType<EditableTextState>();
      if (editable != null && editable.mounted) {
        final selection = editable.widget.controller.selection;
        if (selection.isValid) {
          editable.bringIntoView(selection.extent);
          // The SDK's caret can be shorter than the current line's glyphs.
          // Reveal both after adjusting the editable's own scroll position.
          final render = editable.renderEditable;
          var reveal = render.getLocalRectForCaret(selection.extent);
          final line = render.getLineAtOffset(selection.extent);
          if (line.isValid && !line.isCollapsed) {
            for (final box in render.getBoxesForSelection(line)) {
              reveal = reveal.expandToInclude(box.toRect());
            }
          }
          render.showOnScreen(rect: reveal);
        }
      }
    });
    // Metrics notifications may arrive after a frame. Request the next layout
    // so the queued reveal observes the resized viewport without a timer.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _handleIdsViewportMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical &&
        notification.metrics.viewportDimension != _viewportExtent) {
      _viewportExtent = notification.metrics.viewportDimension;
      _queueFocusedIdsReveal();
    }
    return false;
  }

  bool confirmed = false, checking = false, answered = false;
  String? error;
  Set<String> get _owners => _ids(ownerIds.text);
  Set<String> _ids(String value) =>
      value.split(RegExp(r'[\s,;]+')).where((id) => id.isNotEmpty).toSet();

  @override
  void dispose() {
    deviceIdsFocus.removeListener(_queueFocusedIdsReveal);
    ownerIdsFocus.removeListener(_queueFocusedIdsReveal);
    deviceIdsFocus.dispose();
    ownerIdsFocus.dispose();
    ownerIds.dispose();
    deviceIds.dispose();
    super.dispose();
  }

  Future<void> _inspect() async {
    final ids = _owners;
    if (ids.any((id) => !isCanonicalId(id))) {
      setState(() => error = 'Enter complete installation IDs.');
      return;
    }
    setState(() {
      checking = true;
      error = null;
    });
    try {
      final result = await widget.inspect(ids);
      if (mounted) setState(() => inventory = result);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  void _begin() {
    if (answered || !(ModalRoute.isCurrentOf(context) ?? false)) return;
    final extra = _ids(deviceIds.text);
    if (extra.any((id) => !isCanonicalId(id)) ||
        _owners.any((id) => !isCanonicalId(id))) {
      setState(() => error = 'Enter complete installation IDs.');
      return;
    }
    if (!confirmed || checking || inventory.unresolvedFoodNames.isNotEmpty) {
      return;
    }
    answered = true;
    Navigator.pop(
      context,
      WorkspaceUpgradeChoice({...selected, ...extra}, _owners),
    );
  }

  void _later() {
    if (answered || !(ModalRoute.isCurrentOf(context) ?? false)) return;
    answered = true;
    Navigator.pop(context);
  }

  Widget _installationIdsField({
    required String fieldKey,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String helper,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Text(label, style: theme.textTheme.bodyLarge)),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          child: TextField(
            key: ValueKey(fieldKey),
            controller: controller,
            focusNode: focusNode,
            enabled: !checking,
            minLines: 1,
            maxLines: 4,
            onChanged: (_) => setState(() => confirmed = false),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          helper,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ids = {...inventory.owners, widget.writer}.toList()..sort();
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _handleIdsViewportMetrics,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Upgrade shared workspace'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use one Tasks and Food history per device. Tandemlog keeps '
                'the original logs and a verified recovery snapshot. Editing '
                'pauses on participating devices until the upgrade finishes.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Update every device that will keep editing to this version '
                'or newer. Let folder sync finish. Stop older apps and devices '
                'you will not include. An offline or unseen device cannot be '
                'verified by Tandemlog.',
              ),
              const SizedBox(height: 16),
              Text(
                'This installation',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SelectableText(widget.writer),
              const SizedBox(height: 16),
              Text(
                'Devices participating in this upgrade',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Text(
                'History below identifies past writers, not currently active '
                'devices. Select every installation that will keep writing. '
                'Leave retired installations unselected; their history stays.',
              ),
              for (final id in ids)
                CheckboxListTile(
                  key: ValueKey('upgrade-participant-$id'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    id == widget.writer ? 'This device' : 'Historical writer',
                  ),
                  subtitle: SelectableText(id),
                  value: selected.contains(id),
                  onChanged: checking || id == widget.writer
                      ? null
                      : (value) => setState(() {
                          value! ? selected.add(id) : selected.remove(id);
                          confirmed = false;
                        }),
                ),
              const SizedBox(height: 12),
              _installationIdsField(
                fieldKey: 'upgrade-extra-participants',
                controller: deviceIds,
                focusNode: deviceIdsFocus,
                label: 'Other participating installation IDs',
                helper:
                    'Optional. Find each full ID in Settings on that device.',
              ),
              if (inventory.unresolvedFoodNames.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Some Food history needs its original installation ID '
                  'before it can be matched safely. Use the ID from that '
                  'installation or a trusted profile backup.',
                ),
                for (final name in inventory.unresolvedFoodNames)
                  SelectableText(name),
              ],
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Historical installation IDs'),
                children: [
                  _installationIdsField(
                    fieldKey: 'upgrade-known-owners',
                    controller: ownerIds,
                    focusNode: ownerIdsFocus,
                    label: 'Additional historical installation IDs',
                    helper:
                        'These preserve ownership; they do not add participating devices.',
                  ),
                  TextButton(
                    onPressed: checking ? null : _inspect,
                    child: const Text('Check historical owners'),
                  ),
                ],
              ),
              CheckboxListTile(
                key: const ValueKey('upgrade-coordination-confirmation'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I checked all my devices: every device that will keep '
                  'editing is included, and other or older apps are stopped.',
                ),
                value: confirmed,
                onChanged: checking
                    ? null
                    : (value) => setState(() => confirmed = value!),
              ),
              const Text(
                'Once conversion is staged, resume this upgrade after an '
                'interruption. Do not reopen the upgraded workspace in an '
                'older app. This app also upgrades its local profile; stable '
                '2026.10.6 and RC.1 cannot reopen that profile.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (checking) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: checking ? null : _later,
            child: const Text('Later'),
          ),
          FilledButton(
            key: const ValueKey('begin-workspace-upgrade'),
            onPressed:
                confirmed && !checking && inventory.unresolvedFoodNames.isEmpty
                ? _begin
                : null,
            child: const Text('Pause editing and begin'),
          ),
        ],
      ),
    );
  }
}

/// The host owns command serialization, guards and recovery. This surface never
/// manufactures an acknowledgement or progresses without the host callback.
class WorkspaceUpgradePanel extends StatelessWidget {
  const WorkspaceUpgradePanel({
    super.key,
    required this.upgrade,
    required this.busy,
    required this.onAction,
    this.error,
  });
  final WorkspaceUpgrade upgrade;
  final bool busy;
  final String? error;
  final Future<void> Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final participant = upgrade.participants.contains(upgrade.writer);
    final input = upgrade.inputAcknowledged;
    final output = upgrade.outputAcknowledged;
    final phase = upgrade.phase;
    final (heading, explanation) = switch (phase) {
      'input' => (
        'Check and pause each device',
        'Each participating device must finish its pending saves and verify '
            'the same frozen history. Open this workspace on each device, '
            'join the upgrade. Tandemlog continues automatically when the '
            'required checks arrive through folder sync.',
      ),
      'staged' || 'staging' => (
        'Verify the converted history',
        'The original history and recovery snapshot are retained. Each '
            'participating device verifies the converted Tasks and Food. '
            'Tandemlog activates the upgrade when every check has arrived.',
      ),
      'ready' => (
        'Finish on this device',
        'The shared workspace is upgraded. Verify this device’s protected '
            'writer state before resuming Tasks and Food.',
      ),
      'invalidated' => (
        'The source history changed',
        'A late change arrived after the snapshot was chosen. Previous '
            'acknowledgements cannot activate it. Before conversion begins, '
            'the leading device can cancel and start again after every '
            'device and folder replica is settled. Preserve all files.',
      ),
      'complete' => (
        'Workspace upgraded',
        'Tasks and Food now share one history per device. Original logs and '
            'the verified recovery snapshot remain preserved.',
      ),
      _ => (
        'Resume workspace upgrade',
        'Keep this profile and folder. Check for updates to resume safely; '
            'do not replace the manifest or delete upgrade files.',
      ),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Workspace upgrade',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(heading, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(explanation),
              const SizedBox(height: 12),
              Text(
                upgrade.isCoordinator
                    ? 'This device leads the upgrade.'
                    : 'Another device leads the upgrade.',
              ),
              const SizedBox(height: 8),
              const Text('This installation'),
              SelectableText(upgrade.writer),
              if (!participant)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'This installation is not in the participating roster. '
                    'Keep editing stopped here. The leading device must '
                    'finish the upgrade before this installation can open it.',
                  ),
                ),
              const SizedBox(height: 16),
              for (final id in (upgrade.participants.toList()..sort()))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    output.contains(id)
                        ? Icons.verified_outlined
                        : input.contains(id)
                        ? Icons.pause_circle_outline
                        : Icons.hourglass_empty,
                  ),
                  title: Text(
                    id == upgrade.writer
                        ? 'This device'
                        : 'Participating device',
                  ),
                  subtitle: SelectableText(id),
                  trailing: Text(
                    output.contains(id)
                        ? 'Verified'
                        : input.contains(id)
                        ? 'Paused'
                        : 'Waiting',
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (busy) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (participant &&
                      !upgrade.hasLocalConsent &&
                      phase != 'invalidated' &&
                      phase != 'complete')
                    FilledButton(
                      key: const ValueKey('join-workspace-upgrade'),
                      onPressed: busy ? null : () => onAction('join'),
                      child: const Text('Join upgrade and pause editing'),
                    ),
                  if (participant &&
                      upgrade.hasLocalConsent &&
                      phase != 'invalidated' &&
                      phase != 'complete')
                    FilledButton(
                      key: const ValueKey('resume-workspace-upgrade'),
                      onPressed: busy ? null : () => onAction('resume'),
                      child: Text(
                        error == null ? 'Resume upgrade' : 'Retry upgrade',
                      ),
                    ),
                  if (phase == 'complete')
                    FilledButton(
                      onPressed: busy ? null : () => onAction('open'),
                      child: const Text('Open workspace'),
                    ),
                  if ((phase == 'input' || phase == 'invalidated') &&
                      participant &&
                      !input.contains(upgrade.writer))
                    OutlinedButton(
                      key: const ValueKey('recover-workspace-upgrade-saves'),
                      onPressed: busy ? null : () => onAction('recover'),
                      child: const Text('Finish earlier saves'),
                    ),
                  if (upgrade.canAbort)
                    TextButton(
                      key: const ValueKey('cancel-workspace-upgrade'),
                      onPressed: busy ? null : () => onAction('abort'),
                      child: const Text('Cancel upgrade'),
                    ),
                  OutlinedButton(
                    key: const ValueKey('restore-upgrade-folder-access'),
                    onPressed: busy ? null : () => onAction('restore-access'),
                    child: const Text('Restore access to this folder'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('refresh-workspace-upgrade'),
                    onPressed: busy ? null : () => onAction('refresh'),
                    child: const Text('Check for updates'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Folder sync cannot prove that an unseen offline device is '
                'stopped. Keep excluded and older apps closed. Unexpected '
                'legacy changes stop the upgrade or editing; preserve all '
                'files and use the recovery message.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
