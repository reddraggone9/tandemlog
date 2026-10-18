// Separate debug QA entrypoint; never imported by production lib/main.dart.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'harness.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _UpgradeQaApp()));
}

class _UpgradeQaApp extends StatefulWidget {
  const _UpgradeQaApp();
  @override
  State<_UpgradeQaApp> createState() => _UpgradeQaState();
}

class _UpgradeQaState extends State<_UpgradeQaApp> {
  bool busy = false, freshFolderConfirmed = false;
  String output =
      'TEST ONLY. Creates synthetic history in a NEW EMPTY SAF folder.\n'
      'No normal Tandemlog profile is opened. The private report is retained.\n'
      'Two controlled interruptions use real provider writes, followed by SQLite '
      'close/reopen and core recovery. This is not provider-origin failure or '
      'Android process-kill coverage.';
  Map<String, Object?>? report;
  String? reportPath;
  Future<void> run() async {
    if (busy || !freshFolderConfirmed) return;
    setState(() {
      busy = true;
      report = null;
      reportPath = null;
    });
    try {
      final uri = await AndroidLogFolder.pick();
      if (uri == null) return;
      final folder = AndroidLogFolder(uri);
      if ((await folder.list()).isNotEmpty) {
        if (mounted) {
          setState(
            () => output +=
                '\nRejected: folder is not empty. Nothing was written.',
          );
        }
        return;
      }
      final documents = await getApplicationDocumentsDirectory();
      final root = await Directory(
        documents.path,
      ).createTemp('workspace-upgrade-qa-');
      reportPath = '${root.path}/report.json';
      report = await runWorkspaceUpgradeSafQa(
        root,
        folder,
        progress: (line) {
          if (mounted) setState(() => output += '\n$line');
        },
      );
      // Only result/path are logged; full private report is exported explicitly.
      debugPrint(
        'TANDEMLOG_UPGRADE_QA_RESULT ${jsonEncode({'passed': report!['passed'], 'reportPath': reportPath, 'source': report!['source'], 'testOnly': true})}',
      );
      if (mounted) {
        setState(() {
          output +=
              '\n${report!['passed'] == true ? 'PASS: two recovery cases' : 'FAILED: inspect private report'}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => output +=
              '\nFAILED (${error.runtimeType}); retained evidence is not deleted.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          freshFolderConfirmed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TEST ONLY Workspace upgrade QA')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I will choose a newly created empty synthetic folder, never an existing workspace.',
              ),
              value: freshFolderConfirmed,
              onChanged: busy
                  ? null
                  : (value) => setState(() => freshFolderConfirmed = value!),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: busy || !freshFolderConfirmed ? null : run,
                  child: const Text('Choose NEW EMPTY SAF folder and run'),
                ),
                OutlinedButton(
                  onPressed: busy || report == null
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: const JsonEncoder.withIndent(
                                '  ',
                              ).convert(report),
                            ),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Synthetic QA report copied'),
                              ),
                            );
                          }
                        },
                  child: const Text('Copy private synthetic report JSON'),
                ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(child: SelectableText(output)),
            ),
            if (reportPath != null)
              SelectableText('Private report: ${reportPath!}'),
          ],
        ),
      ),
    ),
  );
}
