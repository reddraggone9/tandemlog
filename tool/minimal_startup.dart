// Diagnostic baseline only. No task imports, database or file access.
import 'package:flutter/material.dart';

void main() {
  debugPrint('TANDEMLOG_MAIN');
  final watch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Minimal Flutter startup baseline')),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('TANDEMLOG_READY_MS=${watch.elapsedMilliseconds} FILES_READ=0');
  });
}
