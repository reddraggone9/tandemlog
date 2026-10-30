import 'dart:io';

import 'package:tandemlog/agent/cli.dart';
import 'package:tandemlog/agent/mcp_server.dart';

Future<void> main(List<String> argv) async {
  if (argv.isNotEmpty && argv.first == 'mcp') {
    String? option(String name) {
      final i = argv.indexOf('--$name');
      return i >= 0 && i + 1 < argv.length ? argv[i + 1] : null;
    }

    await McpServer(
      profile: option('profile'),
      timeZone: option('tz'),
    ).serve(stdin, stdout);
    await stdout.flush();
    exit(0);
  }
  final (code, output) = await runCli(argv);
  if (output.isNotEmpty) (code == 0 ? stdout : stderr).writeln(output);
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
