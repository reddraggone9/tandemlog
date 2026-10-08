// Dedicated test-only APK entrypoint; production lib/main.dart cannot reach it.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'harness.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _RecoveryApp()));
}

class _RecoveryApp extends StatefulWidget {
  const _RecoveryApp();
  @override
  State<_RecoveryApp> createState() => _RecoveryAppState();
}

class _RecoveryAppState extends State<_RecoveryApp> {
  bool busy = false;
  String output =
      'TEST ONLY • Six synthetic native recovery cases.\nChoose a NEW EMPTY folder for SAF. Evidence is retained.\nNo production profile is opened.';
  Future<void> run(bool saf) async {
    setState(() {
      busy = true;
    });
    try {
      LogFolder? folder;
      if (saf) {
        final uri = await AndroidLogFolder.pick();
        if (uri == null) return;
        folder = AndroidLogFolder(uri);
      }
      final documents = await getApplicationDocumentsDirectory();
      final root = await Directory(
        '${documents.path}/recovery-${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      final report = await runRecoveryHarness(
        root,
        sharedFolder: folder,
        progress: (line) {
          // Machine-readable lines are available through adb logcat.
          debugPrint('TANDEMLOG_RECOVERY $line');
          if (mounted) {
            setState(() {
              output += '\n$line';
            });
          }
        },
      );
      debugPrint('TANDEMLOG_RECOVERY_RESULT ${jsonEncode(report)}');
      setState(() {
        output +=
            '\n${report['passed'] == true ? 'PASS 6/6' : 'FAILED'}\nReport: ${root.path}/report.json';
      });
    } catch (error, stack) {
      debugPrint('TANDEMLOG_RECOVERY_FATAL $error\n$stack');
      setState(() {
        output += '\nFATAL $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TEST ONLY Recovery')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            children: [
              ElevatedButton(
                onPressed: busy ? null : () => run(false),
                child: const Text('Run private folder'),
              ),
              ElevatedButton(
                onPressed: busy ? null : () => run(true),
                child: const Text('Choose empty SAF folder'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: SingleChildScrollView(child: SelectableText(output))),
        ],
      ),
    ),
  );
}
