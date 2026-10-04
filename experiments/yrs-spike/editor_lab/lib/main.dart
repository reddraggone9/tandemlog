import 'dart:io';

import 'package:flutter/material.dart';

import 'editor_session.dart';

void main() => runApp(const EditorLabApp());

class EditorLabApp extends StatelessWidget {
  const EditorLabApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Text merge lab',
    theme: ThemeData(colorSchemeSeed: const Color(0xff3b705d)),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xff3b705d),
      brightness: Brightness.dark,
    ),
    home: const EditorLab(),
  );
}

class EditorLab extends StatefulWidget {
  const EditorLab({super.key});
  @override
  State<EditorLab> createState() => _EditorLabState();
}

class _EditorLabState extends State<EditorLab> {
  late final EditorSession _session;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _patching = false;
  String? _error;
  int _inputCount = 0;
  @override
  void initState() {
    super.initState();
    _session = EditorSession()..addListener(_changed);
    _controller.addListener(_input);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _input() {
    if (_patching || !_session.editing) return;
    try {
      final value = _controller.value;
      _session.setComposing(
        value.composing.isValid && !value.composing.isCollapsed,
      );
      _session.replaceDraft(value.text);
      setState(() {
        _inputCount++;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _perform(VoidCallback action) {
    try {
      action();
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _begin() => _perform(() {
    _session.beginEdit();
    _patching = true;
    _controller.value = TextEditingValue(
      text: _session.draftText,
      selection: TextSelection.collapsed(offset: _session.draftText.length),
    );
    _patching = false;
    _focus.requestFocus();
  });
  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _controller.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Text merge lab'),
        actions: [
          IconButton(
            tooltip: 'Reset synthetic replicas',
            icon: const Icon(Icons.restart_alt),
            onPressed: _session.editing ? null : () => _perform(_session.reset),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Synthetic fixtures only • ${Platform.operatingSystem} native FFI',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  const Text('Committed A'),
                  Text(
                    _session.committedA,
                    key: const ValueKey('committed-a'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Replica B'),
                  Text(
                    _session.committedB,
                    key: const ValueKey('committed-b'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        key: const ValueKey('begin-edit'),
                        onPressed: _session.editing ? null : _begin,
                        child: const Text('Edit A'),
                      ),
                      TextFieldTapRegion(
                        child: OutlinedButton(
                          key: const ValueKey('remote-prefix'),
                          onPressed: () => _perform(_session.remotePrefix),
                          child: const Text('Receive remote prefix'),
                        ),
                      ),
                      OutlinedButton(
                        key: const ValueKey('undo'),
                        onPressed: _session.canUndo && !_session.editing
                            ? () => _perform(_session.undo)
                            : null,
                        child: const Text('Undo'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('redo'),
                        onPressed: _session.canRedo && !_session.editing
                            ? () => _perform(_session.redo)
                            : null,
                        child: const Text('Redo'),
                      ),
                    ],
                  ),
                  if (_session.editing) ...[
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('draft-field'),
                      controller: _controller,
                      focusNode: _focus,
                      minLines: 2,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Private captured draft',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'IME ${_session.composing ? 'composing ${v.composing.start}..${v.composing.end}' : 'committed'} • selection ${v.selection.start}..${v.selection.end} • inputs $_inputCount',
                      key: const ValueKey('ime-status'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          key: const ValueKey('save-draft'),
                          onPressed: _session.composing
                              ? null
                              : () => _perform(_session.save),
                          child: const Text('Save'),
                        ),
                        OutlinedButton(
                          key: const ValueKey('cancel-draft'),
                          onPressed: () => _perform(_session.cancel),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Published local batches: ${_session.publishedLocalUpdates}',
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 12),
                  ..._session.trace.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        e,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
