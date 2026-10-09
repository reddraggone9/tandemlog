import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'harness.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: FaultApp()));
}

class FaultApp extends StatefulWidget {
  const FaultApp({super.key});
  @override
  State<FaultApp> createState() => _FaultAppState();
}

class _FaultAppState extends State<FaultApp> {
  String output =
      'TEST ONLY: private synthetic migration process-death harness';
  @override
  void initState() {
    super.initState();
    run();
  }

  void log(String text) {
    debugPrint('TANDEMLOG_STORAGE_FAULT $text');
    if (mounted) setState(() => output += '\n$text');
  }

  Future<void> run() async {
    final documents = await getApplicationDocumentsDirectory();
    final control = File('${documents.path}/storage-fault-control.json');
    log('source=$faultSource pid=$pid control=${control.path}');
    if (!control.existsSync()) {
      log('Write control then force-stop/relaunch this TEST ONLY package.');
      return;
    }
    try {
      final report = await runFaultCase(
        documents,
        jsonDecode(await control.readAsString()),
        progress: log,
      );
      log('RESULT ${jsonEncode(report)}');
    } catch (error, stack) {
      await durableJson(File('${documents.path}/storage-fault-error.json'), {
        'passed': false,
        'source': faultSource,
        'pid': pid,
        'error': '$error',
        'stack': '$stack',
      });
      log('ERROR $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TEST ONLY Storage Faults')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(output),
    ),
  );
}
