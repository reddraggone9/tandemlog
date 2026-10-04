import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ReleaseVersionTile extends StatefulWidget {
  const ReleaseVersionTile({super.key, this.version = appBuildName});

  final String? version;

  @override
  State<ReleaseVersionTile> createState() => _ReleaseVersionTileState();
}

class _ReleaseVersionTileState extends State<ReleaseVersionTile> {
  bool copied = false;
  bool failed = false;

  Future<void> copyVersion() async {
    final version = widget.version;
    if (version == null || version.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: version));
      if (mounted) {
        setState(() {
          copied = true;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          copied = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.version?.isNotEmpty ?? false;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Version'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(available ? widget.version! : 'Unavailable'),
          if (failed) const Text('Could not copy version. Try again.'),
        ],
      ),
      trailing: IconButton(
        tooltip: 'Copy version',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: available ? copyVersion : null,
        icon: Semantics(
          liveRegion: copied,
          label: copied ? 'Version copied' : null,
          child: Icon(copied ? Icons.check : Icons.content_copy_outlined),
        ),
      ),
    );
  }
}
